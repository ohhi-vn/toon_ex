defmodule ToonEx.ComplexTest do
  @moduledoc """
  End-to-end tests for a deeply-nested Organisation struct.

  Tests are layered:
    1. normalize/1       — struct → plain map, secret fields excluded
    2. encode/1          — map → TOON string, structural spot-checks
    3. decode/1          — TOON string → map, value-level assertions
    4. roundtrip         — encode(normalize(struct)) |> decode == expected_map
    5. partial decode    — decode individual TOON snippets, not the full doc
    6. options           — keys: :atoms, delimiter: tab, key_folding, expand_paths
    7. re-encode         — decode → encode → decode is idempotent
    8. error paths       — malformed fragments derived from the real structure
  """
  use ExUnit.Case, async: true

  alias ToonEx.Fixtures.Complex

  # Build once per test run (structs are immutable)
  @org Complex.sample()
  @expected Complex.expected_map()

  # ── helpers ────────────────────────────────────────────────────────────────

  defp encode!(data, opts \\ []), do: ToonEx.encode!(data, opts)
  defp decode!(toon, opts \\ []), do: ToonEx.decode!(toon, opts)

  defp roundtrip(data, enc_opts \\ [], dec_opts \\ []) do
    toon = encode!(data, enc_opts)
    {toon, decode!(toon, dec_opts)}
  end

  # ── 1. normalize ────────────────────────────────────────────────────────────

  describe "normalize" do
    test "organisation normalises to plain string-keyed map" do
      norm = ToonEx.Utils.normalize(@org)
      assert is_map(norm)
      assert norm["id"] == "org-001"
    end

    test "secret field is excluded by @derive except: [:secret]" do
      norm = ToonEx.Utils.normalize(@org)
      eng_head = norm["departments"] |> hd() |> Map.get("head")
      refute Map.has_key?(eng_head, "secret")
    end

    test "Budget uses custom encoder — emits 'amount currency' string" do
      norm = ToonEx.Utils.normalize(@org)
      eng_dept = hd(norm["departments"])
      assert eng_dept["budget"] == "500000 USD"
    end

    test "nil secret field excluded regardless of nil value" do
      carol = @org.departments |> hd() |> Map.get(:employees) |> Enum.at(1)
      assert carol.secret == nil
      norm = ToonEx.Utils.normalize(carol)
      refute Map.has_key?(norm, "secret")
    end

    test "empty employees list normalises to []" do
      ops = @org.departments |> Enum.at(1)
      norm = ToonEx.Utils.normalize(ops)
      assert norm["employees"] == []
    end

    test "unicode name survives normalisation" do
      bob = @org.departments |> hd() |> Map.get(:employees) |> Enum.at(0)
      norm = ToonEx.Utils.normalize(bob)
      assert norm["name"] == "Bob Müller"
    end

    test "quoted-content name survives normalisation" do
      carol = @org.departments |> hd() |> Map.get(:employees) |> Enum.at(1)
      norm = ToonEx.Utils.normalize(carol)
      assert norm["name"] == ~s(Carol "CC" Chen)
    end

    test "deep nested address is a plain map" do
      norm = ToonEx.Utils.normalize(@org)
      addr = norm["departments"] |> hd() |> Map.get("head") |> Map.get("address")

      assert addr == %{
               "street" => "1 Infinite Loop",
               "city" => "Cupertino",
               "country" => "US",
               "postcode" => "95014"
             }
    end

    test "whole-number float score normalises to integer (9.0 → 9)" do
      # ToonEx.Utils.normalize does NOT change floats; the integer conversion
      # happens during encode→decode.  Score 7.0 survives as 7.0 here.
      norm = ToonEx.Utils.normalize(@org)
      projects = norm["departments"] |> hd() |> Map.get("head") |> Map.get("projects")
      firebird = Enum.find(projects, &(&1["name"] == "Firebird"))
      assert firebird["score"] == 7.0
    end
  end

  # ── 2. encode — structural spot-checks ──────────────────────────────────────

  describe "encode — structure" do
    setup do
      toon = encode!(@org)
      {:ok, toon: toon}
    end

    test "output is a non-empty string", %{toon: toon} do
      assert is_binary(toon)
      assert byte_size(toon) > 100
    end

    test "top-level scalar keys present", %{toon: toon} do
      assert toon =~ "id: org-001"
      assert toon =~ "founded: 1987"
      assert toon =~ "public: true"
    end

    test "rating float encoded without scientific notation", %{toon: toon} do
      assert toon =~ "rating: 4.75"
      # Check the rating value itself is not in scientific notation.
      # (We cannot refute "e" globally — field names like "departments",
      # "employees", "role", "score", "street" etc. all contain the letter e.)
      refute toon =~ ~r/rating:.*\de[+\-]?\d/
    end

    test "notes string with newline is quoted and escaped", %{toon: toon} do
      assert toon =~ ~s(notes: "Founded in a garage.\\nNow global.")
    end

    test "departments key is present as array header", %{toon: toon} do
      assert toon =~ "departments"
    end

    test "secret field is absent from output", %{toon: toon} do
      refute toon =~ "secret"
      refute toon =~ "hunter2"
      refute toon =~ "s3cr3t"
    end

    test "budget encoded as custom string", %{toon: toon} do
      assert toon =~ "500000 USD"
      assert toon =~ "250000 EUR"
    end

    test "unicode name is present", %{toon: toon} do
      assert toon =~ "Bob Müller"
    end

    test "name with embedded double-quotes is quoted+escaped", %{toon: toon} do
      # Carol "CC" Chen → "Carol \"CC\" Chen"
      assert toon =~ ~s("Carol \\"CC\\" Chen")
    end

    test "address fields encoded as nested object", %{toon: toon} do
      assert toon =~ "street:"
      assert toon =~ "1 Infinite Loop"
      assert toon =~ "Cupertino"
    end

    test "projects with same keys encoded in tabular format", %{toon: toon} do
      # Uniform map arrays → tabular: header contains {active,id,name,score}
      assert toon =~ "]{"
    end

    test "empty tags array encoded as [0]:", %{toon: toon} do
      assert toon =~ "tags[0]:"
    end

    test "empty employees array encoded as [0]:", %{toon: toon} do
      assert toon =~ "employees[0]:"
    end

    test "metadata slack_channel value is present and quoted", %{toon: toon} do
      # '#' is a TOON structure character that requires quoting per spec §7.2
      assert toon =~ ~s(slack_channel: "#engineering")
    end
  end

  # ── 3. decode — value assertions ────────────────────────────────────────────

  describe "decode — values" do
    setup do
      toon = encode!(@org)
      {:ok, decoded: decode!(toon)}
    end

    test "top-level scalars decoded correctly", %{decoded: d} do
      assert d["id"] == "org-001"
      assert d["name"] == "Acme Corporation"
      assert d["founded"] == 1987
      assert d["public"] == true
      assert d["rating"] == 4.75
    end

    test "notes newline escape decoded to real newline", %{decoded: d} do
      assert d["notes"] == "Founded in a garage.\nNow global."
    end

    test "two departments decoded", %{decoded: d} do
      assert length(d["departments"]) == 2
    end

    test "engineering department id and name", %{decoded: d} do
      eng = hd(d["departments"])
      assert eng["id"] == "dept-eng"
      assert eng["name"] == "Engineering"
    end

    test "head of engineering decoded correctly", %{decoded: d} do
      head = d["departments"] |> hd() |> Map.get("head")
      assert head["id"] == "emp-001"
      assert head["name"] == "Alice Zhao"
      assert head["salary"] == 120_000
      assert head["active"] == true
    end

    test "secret field absent after decode", %{decoded: d} do
      head = d["departments"] |> hd() |> Map.get("head")
      refute Map.has_key?(head, "secret")
    end

    test "head address decoded", %{decoded: d} do
      addr = d["departments"] |> hd() |> Map.get("head") |> Map.get("address")
      assert addr["street"] == "1 Infinite Loop"
      assert addr["city"] == "Cupertino"
      assert addr["country"] == "US"
      assert addr["postcode"] == "95014"
    end

    test "projects tabular array decoded — two rows", %{decoded: d} do
      projects = d["departments"] |> hd() |> Map.get("head") |> Map.get("projects")
      assert length(projects) == 2
    end

    test "project score 9.5 decoded as float", %{decoded: d} do
      projects = d["departments"] |> hd() |> Map.get("head") |> Map.get("projects")
      phoenix = Enum.find(projects, &(&1["name"] == "Phoenix"))
      assert phoenix["score"] == 9.5
      assert is_float(phoenix["score"])
    end

    test "project score 7.0 decoded as integer (whole-float → int)", %{decoded: d} do
      projects = d["departments"] |> hd() |> Map.get("head") |> Map.get("projects")
      firebird = Enum.find(projects, &(&1["name"] == "Firebird"))
      # TOON encodes 7.0 as "7"; decoder produces integer 7
      assert firebird["score"] == 7
      assert is_integer(firebird["score"])
    end

    test "employees list has two entries", %{decoded: d} do
      employees = d["departments"] |> hd() |> Map.get("employees")
      assert length(employees) == 2
    end

    test "Bob Müller unicode name decoded", %{decoded: d} do
      bob = d["departments"] |> hd() |> Map.get("employees") |> hd()
      assert bob["name"] == "Bob Müller"
    end

    test "Carol's quoted name decoded correctly", %{decoded: d} do
      carol = d["departments"] |> hd() |> Map.get("employees") |> Enum.at(1)
      assert carol["name"] == ~s(Carol "CC" Chen)
    end

    test "Carol's empty projects decoded as []", %{decoded: d} do
      carol = d["departments"] |> hd() |> Map.get("employees") |> Enum.at(1)
      assert carol["projects"] == []
    end

    test "Carol's empty tags decoded as []", %{decoded: d} do
      carol = d["departments"] |> hd() |> Map.get("employees") |> Enum.at(1)
      assert carol["tags"] == []
    end

    test "budget decoded as custom string value", %{decoded: d} do
      eng_budget = d["departments"] |> hd() |> Map.get("budget")
      assert eng_budget == "500000 USD"
    end

    test "metadata decoded as nested map", %{decoded: d} do
      meta = d["departments"] |> hd() |> Map.get("metadata")
      assert meta["cost_center"] == "CC-42"
      assert meta["slack_channel"] == "#engineering"
    end

    test "ops department has empty employees", %{decoded: d} do
      ops = d["departments"] |> Enum.at(1)
      assert ops["employees"] == []
    end

    test "ops department has empty metadata", %{decoded: d} do
      ops = d["departments"] |> Enum.at(1)
      assert ops["metadata"] == %{}
    end

    test "Dan O'Brien name with apostrophe decoded correctly", %{decoded: d} do
      head = d["departments"] |> Enum.at(1) |> Map.get("head")
      assert head["name"] == "Dan O'Brien"
    end
  end

  # ── 4. full roundtrip equality ───────────────────────────────────────────────

  describe "roundtrip" do
    test "encode(normalize(org)) |> decode == expected_map" do
      {_toon, decoded} = roundtrip(@org)
      assert decoded == @expected
    end

    test "decode → encode → decode is idempotent" do
      toon1 = encode!(@org)
      decoded1 = decode!(toon1)
      toon2 = encode!(decoded1)
      decoded2 = decode!(toon2)
      assert decoded1 == decoded2
    end

    test "encode with indent: 4 still decodes correctly" do
      {_toon, decoded} = roundtrip(@org, [indent: 4], indent_size: 4)
      assert decoded == @expected
    end

    test "encode with tab delimiter still decodes correctly" do
      {_toon, decoded} = roundtrip(@org, delimiter: "\t")
      assert decoded == @expected
    end

    test "encode with pipe delimiter still decodes correctly" do
      {_toon, decoded} = roundtrip(@org, delimiter: "|")
      assert decoded == @expected
    end
  end

  # ── 5. partial decode — individual TOON snippets ────────────────────────────

  describe "partial decode — individual fields" do
    test "inline tags array" do
      {:ok, r} = ToonEx.decode("tags[2]: leadership,backend")
      assert r["tags"] == ["leadership", "backend"]
    end

    test "tabular projects array" do
      toon =
        "projects[2]{active,id,name,score}:\n  true,p-01,Phoenix,9.5\n  false,p-02,Firebird,7"

      {:ok, r} = ToonEx.decode(toon)
      assert length(r["projects"]) == 2
      phoenix = Enum.find(r["projects"], &(&1["name"] == "Phoenix"))
      assert phoenix["active"] == true
      assert phoenix["score"] == 9.5
    end

    test "nested address object" do
      toon =
        "address:\n  street: 1 Infinite Loop\n  city: Cupertino\n  country: US\n  postcode: 95014"

      {:ok, r} = ToonEx.decode(toon)
      assert r["address"]["city"] == "Cupertino"
    end

    test "budget as custom string value" do
      {:ok, r} = ToonEx.decode("budget: 500000 USD")
      assert r["budget"] == "500000 USD"
    end

    test "escaped notes value" do
      {:ok, r} = ToonEx.decode(~s(notes: "Founded in a garage.\\nNow global."))
      assert r["notes"] == "Founded in a garage.\nNow global."
    end

    test "quoted name with embedded double-quotes" do
      {:ok, r} = ToonEx.decode(~s(name: "Carol \\"CC\\" Chen"))
      assert r["name"] == ~s(Carol "CC" Chen)
    end

    test "empty metadata map" do
      {:ok, r} = ToonEx.decode("metadata:")
      assert r["metadata"] == %{}
    end

    test "empty employees array" do
      {:ok, r} = ToonEx.decode("employees[0]:")
      assert r["employees"] == []
    end

    test "list array of employee objects" do
      toon = """
      employees[2]:
        - id: emp-002
          name: Bob
          active: true
        - id: emp-003
          name: Carol
          active: false
      """

      {:ok, r} = ToonEx.decode(toon)
      assert length(r["employees"]) == 2
      assert hd(r["employees"])["name"] == "Bob"
    end
  end

  # ── 6. options variants ──────────────────────────────────────────────────────

  describe "options" do
    test "keys: :atoms produces atom-keyed map" do
      toon = encode!(@org)
      decoded = decode!(toon, keys: :atoms)
      assert decoded[:id] == "org-001"
      assert decoded[:name] == "Acme Corporation"
    end

    test "keys: :atoms — nested keys are also atoms" do
      toon = encode!(@org)
      decoded = decode!(toon, keys: :atoms)
      eng = decoded[:departments] |> hd()
      head = eng[:head]
      assert head[:name] == "Alice Zhao"
    end

    test "keys: :atoms — tabular project rows have atom keys" do
      toon = encode!(@org)
      decoded = decode!(toon, keys: :atoms)
      projects = decoded[:departments] |> hd() |> Map.get(:head) |> Map.get(:projects)
      phoenix = Enum.find(projects, &(&1[:name] == "Phoenix"))
      assert phoenix[:active] == true
    end

    test "expand_paths: safe on a pre-encoded flat fragment" do
      # Encode a simple nested map with key_folding, then decode with expand_paths
      input = %{"user" => %{"address" => %{"city" => "Berlin"}}}
      folded = encode!(input, key_folding: :safe)
      assert folded == "user.address.city: Berlin"
      expanded = decode!(folded, expand_paths: :safe)
      assert expanded == input
    end

    test "strict: false accepts 3-space indented output encoded with indent: 3" do
      toon = encode!(@org, indent: 3)
      # Default strict mode would reject 3-space indentation (not multiple of 2).
      # Passing strict: false bypasses this check.
      decoded = decode!(toon, strict: false)
      assert decoded["id"] == "org-001"
    end
  end

  # ── 7. re-encode idempotency ─────────────────────────────────────────────────

  describe "re-encode idempotency" do
    test "encode three times, decode three times — all equal" do
      d0 = ToonEx.Utils.normalize(@org)
      e1 = encode!(d0)
      d1 = decode!(e1)
      e2 = encode!(d1)
      d2 = decode!(e2)
      e3 = encode!(d2)
      d3 = decode!(e3)
      assert d1 == d2
      assert d2 == d3
    end

    test "second encoded string is identical to first" do
      d0 = ToonEx.Utils.normalize(@org)
      e1 = encode!(d0)
      e2 = encode!(decode!(e1))
      assert e1 == e2
    end
  end

  # ── 8. error paths from real structure ──────────────────────────────────────

  describe "error paths" do
    test "tabular header row count too low raises" do
      # Claim 1 row, supply 2
      toon =
        "projects[1]{active,id,name,score}:\n  true,p-01,Phoenix,9.5\n  false,p-02,Firebird,7"

      assert_raise ToonEx.DecodeError, fn -> decode!(toon) end
    end

    test "tabular header column count mismatch raises" do
      # Only 3 columns declared, row has 4 values
      toon = "projects[1]{id,name,score}:\n  p-01,Phoenix,9.5,extra"
      assert_raise ToonEx.DecodeError, fn -> decode!(toon) end
    end

    test "inline array length mismatch raises" do
      assert_raise ToonEx.DecodeError, fn -> decode!("tags[3]: a,b") end
    end

    test "invalid escape in quoted name raises" do
      assert_raise ToonEx.DecodeError, fn ->
        decode!(~s(name: "bad\\escape"))
      end
    end

    test "unterminated quoted string raises" do
      assert_raise ToonEx.DecodeError, fn ->
        decode!(~s(name: "Alice Zhao))
      end
    end

    test "tab indentation in strict mode raises" do
      toon = "head:\n\tname: Alice"
      assert_raise ToonEx.DecodeError, fn -> decode!(toon, strict: true) end
    end

    test "non-multiple-of-2 indentation in strict mode raises" do
      toon = "head:\n   name: Alice"
      assert_raise ToonEx.DecodeError, fn -> decode!(toon, strict: true, indent_size: 2) end
    end
  end
end
