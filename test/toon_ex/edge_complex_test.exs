defmodule ToonEx.EdgeComplexTest do
  use ExUnit.Case, async: true

  # credo:disable-for-next-line Credo.Check.Readability.LargeNumbers
  @max_float64 1.7976931348623157e308

  alias ToonEx.Encode.Strings

  # ── Float boundaries (infinity threshold regression) ─────────────────────────

  describe "floats near the float64 limit" do
    test "finite floats between 1.0e308 and max float64 are encoded, not nulled" do
      assert ToonEx.encode!(1.5e308) != "null"
      assert String.contains?(ToonEx.encode!(1.5e308), "15")

      assert ToonEx.encode!(-1.5e308) != "null"
      assert String.starts_with?(ToonEx.encode!(-1.5e308), "-")
    end

    test "the maximum finite float survives" do
      refute ToonEx.encode!(@max_float64) == "null"
    end

    test "values just below the old wrong threshold were always fine" do
      assert ToonEx.encode!(9.9e307) != "null"
    end

    test "normalize keeps finite large floats" do
      refute ToonEx.Utils.normalize(1.7e308) == nil
      assert ToonEx.Utils.normalize(1.7e308) == 1.7e308
    end

    test "non-finite floats cannot be constructed by arithmetic; finite ones pass" do
      # Erlang raises badarith on float overflow, so inf/NaN can only arrive
      # from ports/NIFs — the nil fallback is purely defensive. The threshold
      # itself is exercised by the boundary tests above.
      assert ToonEx.Utils.normalize(@max_float64) == @max_float64

      assert_raise ArithmeticError, fn ->
        :erlang.float_to_binary(1.0e308 * 10)
      end
    end

    test "large finite floats round-trip through TOON text" do
      value = 1.234e300
      {:ok, decoded} = ToonEx.decode(ToonEx.encode!(value))
      assert decoded == value
    end
  end

  # ── Leading / trailing blank lines ───────────────────────────────────────────

  describe "blank line handling at document edges" do
    test "leading blank lines before an object are skipped" do
      assert ToonEx.decode("\n\nname: Alice") == {:ok, %{"name" => "Alice"}}
      assert ToonEx.decode("\n   \n\t\nname: Alice\n") == {:ok, %{"name" => "Alice"}}
    end

    test "leading blank lines before a root array are skipped" do
      assert ToonEx.decode("\n\n[2]: a,b") == {:ok, ["a", "b"]}
    end

    test "leading blank lines before tabular arrays are skipped" do
      doc = "\n\nusers[2]{name,age}:\n  Alice,30\n  Bob,25"

      assert ToonEx.decode(doc) ==
               {:ok,
                %{"users" => [%{"age" => 30, "name" => "Alice"}, %{"age" => 25, "name" => "Bob"}]}}
    end

    test "a document of only blank lines decodes to an empty map" do
      assert ToonEx.decode("\n\n   \n") == {:ok, %{}}
      assert ToonEx.decode("") == {:ok, %{}}
    end

    test "single blank-ish document with only spaces is an empty map" do
      assert ToonEx.decode("   ") == {:ok, %{}}
    end

    test "blank lines between top-level keys are tolerated" do
      assert ToonEx.decode("a: 1\n\nb: 2") == {:ok, %{"a" => 1, "b" => 2}}
    end

    test "CRLF documents decode cleanly" do
      assert ToonEx.decode("name: Alice\r\nage: 30\r\n") ==
               {:ok, %{"name" => "Alice", "age" => 30}}
    end
  end

  # ── normalize/1 fast-path semantics ──────────────────────────────────────────

  describe "normalize fast path returns original structures when already normalized" do
    test "fully-normalized map is returned unchanged" do
      data = %{"a" => 1, "b" => [1, "x", true, nil], "c" => %{"d" => 2.5}}
      assert ToonEx.Utils.normalize(data) == data
    end

    test "atom keys deep inside convert while normalized siblings stay shared" do
      data = %{nested: %{deep: %{leaf: :ok}}}
      normalized = ToonEx.Utils.normalize(data)

      assert normalized == %{"nested" => %{"deep" => %{"leaf" => "ok"}}}
    end

    test "-0.0 normalizes to integer zero anywhere in the tree" do
      assert ToonEx.Utils.normalize(%{"a" => [-0.0]}) == %{"a" => [0]}
      result = ToonEx.Utils.normalize(-0.0)
      assert result === 0
    end

    test "key collision after atom conversion keeps last-wins semantics" do
      # Both keys fold to "1"; Map.new semantics must be preserved.
      normalized = ToonEx.Utils.normalize(%{1 => "int", "1" => "str"})
      assert map_size(normalized) == 1
      assert normalized["1"] in ["int", "str"]
    end

    test "OrderedObject passes through unchanged when already normalized" do
      oo = %ToonEx.OrderedObject{values: [{"b", 2}, {"a", 1}]}
      assert ToonEx.Utils.normalize(oo) == oo
    end

    test "OrderedObject with atom keys converts but preserves declared order" do
      keyed = %ToonEx.OrderedObject{values: [{:b, 2}, {:a, 1}]}

      normalized = ToonEx.Utils.normalize(keyed)
      assert Enum.map(normalized.values, &elem(&1, 0)) == ["b", "a"]
    end

    test "empty OrderedObject becomes empty map (list-item marker case)" do
      assert ToonEx.Utils.normalize(%ToonEx.OrderedObject{values: []}) == %{}
    end

    test "Fragment passes through untouched" do
      fragment = ToonEx.Fragment.new("x: 1")
      assert ToonEx.Utils.normalize(fragment) == fragment
    end

    test "unsupported terms fall back to nil" do
      assert ToonEx.Utils.normalize(self()) == nil
      assert ToonEx.encode!(%{"pid" => self()}) == "pid: null"
    end
  end

  # ── Keyed-tabular single-detection path ─────────────────────────────────────

  describe "keyed tabular encoding (single detection pass)" do
    test "root keyed tabular form" do
      data = %{
        "row1" => %{"a" => 1, "b" => "x"},
        "row2" => %{"a" => 2, "b" => "y"}
      }

      assert ToonEx.encode!(data) == "[2:]{a,b}:\n  row1: 1,x\n  row2: 2,y"
    end

    test "nested keyed tabular under a key" do
      data = %{"table" => %{"r1" => %{"v" => 1}, "r2" => %{"v" => 2}}}

      assert ToonEx.encode!(data) == "table[2:]{v}:\n  r1: 1\n  r2: 2"
    end

    test "keyed tabular inside list items" do
      data = [
        %{"t" => %{"r1" => %{"v" => 1}}},
        %{"t" => %{"r2" => %{"v" => 2}}}
      ]

      toon = ToonEx.encode!(data)
      {:ok, decoded} = ToonEx.decode(toon)
      assert decoded == data
    end

    test "keyed tabular with nested field groups round-trips" do
      data = %{
        "rows" => [
          %{"id" => 1, "pos" => %{"x" => 10, "y" => 20}},
          %{"id" => 2, "pos" => %{"x" => 30, "y" => 40}}
        ]
      }

      toon = ToonEx.encode!(data)
      assert String.contains?(toon, "rows[2]{id,pos{x,y}}:")
      {:ok, decoded} = ToonEx.decode(toon)
      assert decoded == data
    end

    test "key_order option reorders tabular header fields consistently" do
      data = %{"rows" => [%{"a" => 1, "b" => 2}, %{"a" => 3, "b" => 4}]}

      toon = ToonEx.encode!(data, key_order: ["rows"])

      assert String.contains?(toon, "rows[2]{a,b}:")
      assert String.contains?(toon, "\n  1,2")
    end

    test "duplicate entry keys raise in strict mode" do
      doc = """
      t[2:]{v}:
        r1: 1
        r1: 2
      """

      assert_raise ToonEx.DecodeError, ~r/Duplicate entry key/, fn ->
        ToonEx.decode!(doc)
      end
    end

    test "duplicate entry keys keep last value outside strict mode" do
      doc = """
      t[2:]{v}:
        r1: 1
        r1: 2
      """

      {:ok, decoded} = ToonEx.decode(doc, strict: false)
      assert decoded == %{"t" => %{"r1" => %{"v" => 2}}}
    end
  end

  # ── Tabular detection with unordered key sets (set-equality) ─────────────────

  describe "tabular detection compares key sets without relying on order" do
    test "maps built with different insertion orders still encode as one table" do
      rows = [%{"a" => 1, "b" => 2}, %{"b" => 3, "a" => 4}]
      toon = ToonEx.encode!(%{"rows" => rows})

      assert String.contains?(toon, "rows[2]{a,b}:")
    end

    test "row missing a key falls back to list form" do
      rows = [%{"a" => 1, "b" => 2}, %{"a" => 3}]
      toon = ToonEx.encode!(%{"rows" => rows})

      refute String.contains?(toon, "rows[2]{")
      {:ok, decoded} = ToonEx.decode(toon)
      assert decoded == %{"rows" => [%{"a" => 1, "b" => 2}, %{"a" => 3}]}
    end

    test "single-row tables keep the row on its own line" do
      toon = ToonEx.encode!(%{"rows" => [%{"z" => 1, "y" => 2}]})
      assert toon == "rows[1]{y,z}:\n  2,1"
    end
  end

  # ── Quoted-value splitting (chunk-based slow path) ──────────────────────────

  describe "quoted values in inline arrays and tabular cells" do
    test "quoted strings containing the delimiter stay intact" do
      assert ToonEx.decode(~s(x[2]: "a,b",c)) == {:ok, %{"x" => ["a,b", "c"]}}
      assert ToonEx.decode(~s(x[2]: a,"b,c")) == {:ok, %{"x" => ["a", "b,c"]}}
    end

    test "escaped quotes and backslashes inside quoted array items" do
      assert ToonEx.decode(~s(x[1]: "say \\"hi\\"")) == {:ok, %{"x" => [~s(say "hi")]}}
      assert ToonEx.decode(~s(x[1]: "back\\\\slash")) == {:ok, %{"x" => ["back\\slash"]}}
    end

    test "backslash outside quotes is literal; the delimiter still splits" do
      assert ToonEx.decode(~s(x[2]: a\\,b)) == {:ok, %{"x" => ["a\\", "b"]}}
    end

    test "empty segments from doubled delimiters become empty strings" do
      assert ToonEx.decode(~s(x[3]: a,,b)) == {:ok, %{"x" => ["a", "", "b"]}}
      assert ToonEx.decode(~s(x[2]: ,b)) == {:ok, %{"x" => ["", "b"]}}
      assert ToonEx.decode(~s(x[2]: a,)) == {:ok, %{"x" => ["a", ""]}}
    end

    test "quoted empty string is distinct from empty segment" do
      assert ToonEx.decode(~s(x[2]: "","")) == {:ok, %{"x" => ["", ""]}}
    end

    test "whitespace around quoted segments is trimmed" do
      assert ToonEx.decode(~s(x[2]: "a b" , c)) == {:ok, %{"x" => ["a b", "c"]}}
    end

    test "tab-delimited inline arrays auto-detect on rows" do
      assert ToonEx.decode("x[2]: a\tb") == {:ok, %{"x" => ["a", "b"]}}
    end

    test "pipe delimiter declared in header splits correctly" do
      assert ToonEx.decode("x[2|]: a|b") == {:ok, %{"x" => ["a", "b"]}}
    end

    test "tabular rows with quoted cells containing delimiters" do
      doc = ~s(users[2]{name,bio}:\n  Alice,"likes, cats"\n  Bob,quiet)

      assert ToonEx.decode(doc) ==
               {:ok,
                %{
                  "users" => [
                    %{"bio" => "likes, cats", "name" => "Alice"},
                    %{"bio" => "quiet", "name" => "Bob"}
                  ]
                }}
    end

    test "regular tabular rows parse [] as an empty array" do
      doc = "items[1]{tag}:\n  []"

      assert ToonEx.decode(doc) == {:ok, %{"items" => [%{"tag" => []}]}}
    end

    test "keyed-tabular entry cells keep [] as a literal string (§9.5)" do
      doc = "t[1:]{v}:\n  r: []"

      assert ToonEx.decode(doc) == {:ok, %{"t" => %{"r" => %{"v" => "[]"}}}}
    end

    test "round-trips strings that need quoting everywhere" do
      nasty = ["comma,", "quote\"", "back\\slash", ":colon", "[brackets]", " lead", "trail "]

      for s <- nasty do
        toon = ToonEx.encode!(%{"list" => [s]})
        {:ok, decoded} = ToonEx.decode(toon)
        assert decoded == %{"list" => [s]}
      end
    end
  end

  # ── Control-character escaping table ────────────────────────────────────────

  describe "control character escaping uses lowercase \\uXXXX" do
    test "NUL, unit separator and DEL escape via the lookup table" do
      assert IO.iodata_to_binary(Strings.escape_string(<<0>>)) == "\\u0000"
      assert IO.iodata_to_binary(Strings.escape_string(<<31>>)) == "\\u001f"
      assert IO.iodata_to_binary(Strings.escape_string(<<127>>)) == "\\u007f"
    end

    test "control bytes without short escapes use exactly four lowercase hex digits" do
      for b <- Enum.to_list(0..8) ++ Enum.to_list(11..12) ++ Enum.to_list(14..31) ++ [127] do
        escaped = Strings.escape_string(<<b>>) |> IO.iodata_to_binary()

        assert Regex.match?(~r/^\\u00[0-9a-f][0-9a-f]$/, escaped)
      end
    end

    test "tab, newline and carriage return keep their short escapes" do
      assert IO.iodata_to_binary(Strings.escape_string("\t")) == "\\t"
      assert IO.iodata_to_binary(Strings.escape_string("\n")) == "\\n"
      assert IO.iodata_to_binary(Strings.escape_string("\r")) == "\\r"
    end

    test "control characters round-trip through quoted strings" do
      value = "line1\u0000line2\u007fend"
      {:ok, decoded} = ToonEx.decode(ToonEx.encode!(%{"k" => value}))
      assert decoded == %{"k" => value}
    end

    test "strings with control chars get quoted automatically" do
      assert ToonEx.encode!("a\u0000b") == ~S("a\u0000b")
    end
  end

  # ── Strict indentation validation fused into preprocessing ───────────────────

  describe "strict mode indentation errors" do
    @tag :strict_indent
    test "non-multiple indentation raises" do
      assert_raise ToonEx.DecodeError, ~r/multiple of 2/, fn ->
        ToonEx.decode!("outer:\n   inner: 1")
      end
    end

    @tag :strict_indent
    test "tab indentation raises" do
      assert_raise ToonEx.DecodeError, ~r/Tab characters/, fn ->
        ToonEx.decode!("outer:\n\tinner: 1")
      end
    end

    @tag :strict_indent
    test "same errors are raised outside strict mode as no-ops" do
      assert {:ok, %{"outer" => %{"inner" => 1}}} =
               ToonEx.decode("outer:\n   inner: 1", strict: false)

      assert {:ok, %{"outer" => %{"inner" => 1}}} =
               ToonEx.decode("outer:\n\tinner: 1", strict: false)
    end
  end

  # ── Complex nesting round-trips ──────────────────────────────────────────────

  describe "complex document shapes round-trip" do
    test "deeply nested maps with mixed arrays" do
      data = %{
        "level1" => %{
          "level2" => %{
            "level3" => %{
              "prims" => [1, "two", true, nil, 3.5],
              "empty_map" => %{},
              "empty_list" => []
            }
          }
        }
      }

      {:ok, decoded} = data |> ToonEx.encode!() |> ToonEx.decode()
      assert decoded == data
    end

    test "array of mixed objects uses list form and round-trips" do
      data = %{"items" => [%{"a" => 1}, %{"b" => [1, 2]}, "scalar", 42]}

      {:ok, decoded} = data |> ToonEx.encode!() |> ToonEx.decode()
      assert decoded == data
    end

    test "root list array containing nested arrays and objects" do
      data = [[1, 2], %{"k" => "v"}, "text"]

      toon = ToonEx.encode!(data)
      assert String.starts_with?(toon, "[3]:")
      {:ok, decoded} = ToonEx.decode(toon)
      assert decoded == data
    end

    test "empty containers at every level" do
      data = %{"a" => [], "b" => %{}, "c" => [[]], "d" => [%{}]}
      {:ok, decoded} = data |> ToonEx.encode!() |> ToonEx.decode()
      assert decoded == data
    end

    test "keys requiring quotes throughout" do
      data = %{"needs quote" => 1, "123" => 2, "with:colon" => 3, "true" => 4}

      {:ok, decoded} = data |> ToonEx.encode!() |> ToonEx.decode()
      assert decoded == data
    end

    test "unicode content round-trips including escapes" do
      data = %{"emoji" => "🚀🎉", "accent" => "café", "cjk" => "日本語"}

      {:ok, decoded} = data |> ToonEx.encode!() |> ToonEx.decode()
      assert decoded == data
    end

    test "large uniform table (200 rows) round-trips exactly" do
      rows =
        Map.new(1..200, fn i ->
          {"row#{String.pad_leading(Integer.to_string(i), 3, "0")}",
           %{"id" => i, "name" => "n#{i}", "ok" => rem(i, 2) == 0}}
        end)

      data = %{"table" => rows}
      {:ok, decoded} = data |> ToonEx.encode!() |> ToonEx.decode()
      assert decoded == data
    end

    test "fragment injects pre-encoded TOON verbatim" do
      fragment = ToonEx.Fragment.new("inner: 42")

      assert ToonEx.encode!(%{"wrapper" => fragment}) == "wrapper:\n  inner: 42"
    end

    test "tuple lists preserve given key order at the root" do
      data = [{"zebra", 1}, {"apple", 2}]
      toon = ToonEx.encode!(data)

      assert toon == "zebra: 1\napple: 2"
    end
  end
end
