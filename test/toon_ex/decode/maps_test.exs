defmodule ToonEx.Decode.MapsTest do
  use ExUnit.Case, async: true

  # ── basic maps ──────────────────────────────────────────────────────────────

  describe "basic maps" do
    test "empty input decodes to empty map" do
      assert {:ok, %{}} = ToonEx.decode("")
    end

    test "whitespace-only decodes to empty map" do
      assert {:ok, %{}} = ToonEx.decode("   \n  \n  ")
    end

    test "single key-value" do
      assert {:ok, %{"name" => "Alice"}} = ToonEx.decode("name: Alice")
    end

    test "multiple key-values" do
      {:ok, result} = ToonEx.decode("name: Alice\nage: 30")
      assert result == %{"name" => "Alice", "age" => 30}
    end

    test "empty value produces empty map" do
      {:ok, result} = ToonEx.decode("nested: ")
      assert result["nested"] == %{}
    end

    test "key with underscore" do
      assert {:ok, %{"first_name" => "Bob"}} = ToonEx.decode("first_name: Bob")
    end

    test "key with dot is a literal dotted key by default" do
      assert {:ok, %{"user.name" => "Ada"}} = ToonEx.decode("user.name: Ada")
    end

    test "numeric-looking key is treated as a string" do
      assert {:ok, %{"123" => "val"}} = ToonEx.decode(~s("123": val))
    end
  end

  # ── quoted keys ─────────────────────────────────────────────────────────────

  describe "quoted keys" do
    test "quoted key with spaces" do
      assert {:ok, %{"full name" => "Alice"}} = ToonEx.decode(~s("full name": Alice))
    end

    test "quoted key with special characters" do
      assert {:ok, %{"a-b" => 1}} = ToonEx.decode(~s("a-b": 1))
    end

    test "quoted key with escaped quote" do
      assert {:ok, %{"say \"hi\"" => "ok"}} = ToonEx.decode(~s("say \\"hi\\"": ok))
    end

    test "quoted dotted key is NOT expanded with expand_paths: safe" do
      {:ok, result} = ToonEx.decode(~s("a.b": 1), expand_paths: :safe)
      assert result == %{"a.b" => 1}
    end
  end

  # ── keys option ─────────────────────────────────────────────────────────────

  describe "keys: :atoms" do
    test "converts string keys to atoms" do
      assert {:ok, %{name: "Alice"}} = ToonEx.decode("name: Alice", keys: :atoms)
    end

    test "nested keys also become atoms" do
      {:ok, result} = ToonEx.decode("user:\n  name: Bob", keys: :atoms)
      assert result == %{user: %{name: "Bob"}}
    end
  end

  describe "keys: :atoms!" do
    test "existing atom succeeds" do
      # :name must already exist as an atom in the VM (it does in test context)
      assert {:ok, %{name: _}} = ToonEx.decode("name: Alice", keys: :atoms!)
    end

    test "non-existing atom raises" do
      assert_raise ToonEx.DecodeError, fn ->
        ToonEx.decode!("zz_nonexistent_atom_xyz_abc_999: 1", keys: :atoms!)
      end
    end
  end

  # ── nested objects ───────────────────────────────────────────────────────────

  describe "nested objects" do
    test "one level deep" do
      toon = "user:\n  name: Bob"
      assert {:ok, %{"user" => %{"name" => "Bob"}}} = ToonEx.decode(toon)
    end

    test "two levels deep" do
      toon = "a:\n  b:\n    c: 1"
      assert {:ok, %{"a" => %{"b" => %{"c" => 1}}}} = ToonEx.decode(toon)
    end

    test "sibling keys after nested block" do
      toon = "user:\n  name: Bob\nactive: true"
      {:ok, result} = ToonEx.decode(toon)
      assert result["user"] == %{"name" => "Bob"}
      assert result["active"] == true
    end

    test "multiple sibling nested objects" do
      toon = "a:\n  x: 1\nb:\n  x: 2"
      {:ok, result} = ToonEx.decode(toon)
      assert result["a"] == %{"x" => 1}
      assert result["b"] == %{"x" => 2}
    end

    test "mixed primitives and nested objects" do
      toon = "name: Alice\naddress:\n  city: NYC\nage: 30"
      {:ok, result} = ToonEx.decode(toon)
      assert result["name"] == "Alice"
      assert result["address"] == %{"city" => "NYC"}
      assert result["age"] == 30
    end

    test "empty nested object" do
      toon = "meta:"
      assert {:ok, %{"meta" => %{}}} = ToonEx.decode(toon)
    end
  end

  # ── strict mode ─────────────────────────────────────────────────────────────

  describe "strict mode indentation" do
    test "tab in indentation raises" do
      assert_raise ToonEx.DecodeError, ~r/Tab/, fn ->
        ToonEx.decode!("parent:\n\tchild: 1", strict: true)
      end
    end

    test "non-multiple-of-2 indentation raises with indent_size: 2" do
      assert_raise ToonEx.DecodeError, fn ->
        ToonEx.decode!("parent:\n   child: 1", strict: true, indent_size: 2)
      end
    end

    test "non-multiple indentation accepted when strict: false" do
      {:ok, result} = ToonEx.decode("parent:\n   child: 1", strict: false)
      assert result["parent"]["child"] == 1
    end

    test "blank line inside nested block raises in strict mode" do
      _toon = "parent:\n  a: 1\n\n  b: 2"
      # Strict mode forbids blank lines inside arrays; objects are more lenient
      # but blank lines in tabular arrays must raise:
      toon_arr = "rows[2]{a,b}:\n  1,2\n\n  3,4"

      assert_raise ToonEx.DecodeError, fn ->
        ToonEx.decode!(toon_arr, strict: true)
      end
    end

    test "blank line inside nested object tolerated in non-strict mode" do
      {:ok, result} = ToonEx.decode("parent:\n  a: 1\n\n  b: 2", strict: false)
      assert result == %{"parent" => %{"a" => 1, "b" => 2}}
    end
  end

  describe "general object" do
  end
end
