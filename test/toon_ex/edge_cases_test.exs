defmodule ToonEx.EdgeCasesTest do
  @moduledoc """
  Tests for edge cases not covered by the main roundtrip suite:
  escape sequences, unicode, boundary values, large inputs, decode+encode symmetry.
  """
  use ExUnit.Case, async: true

  # ── escape sequences ─────────────────────────────────────────────────────────

  describe "escape sequences — roundtrip" do
    for {name, value} <- [
          {"backslash", "\\"},
          {"double-quote", "\""},
          {"newline", "\n"},
          {"carriage return", "\r"},
          {"tab", "\t"},
          {"backslash+quote", "\\\""},
          {"multiple escapes", "a\\b\nc\td"},
          {"only backslashes", "\\\\\\\\"}
        ] do
      @value value
      test "roundtrip: #{name}" do
        enc = ToonEx.encode!(%{"s" => @value})
        {:ok, dec} = ToonEx.decode(enc)
        assert dec["s"] == @value
      end
    end
  end

  # ── unicode ───────────────────────────────────────────────────────────────────

  describe "unicode strings" do
    test "ASCII-only value" do
      assert {:ok, %{"x" => "hello"}} = ToonEx.decode("x: hello")
    end

    test "unicode value round-trips when quoted" do
      enc = ToonEx.encode!(%{"x" => "héllo"})
      {:ok, dec} = ToonEx.decode(enc)
      assert dec["x"] == "héllo"
    end

    test "CJK characters round-trip" do
      enc = ToonEx.encode!(%{"x" => "日本語"})
      {:ok, dec} = ToonEx.decode(enc)
      assert dec["x"] == "日本語"
    end

    test "emoji round-trip" do
      enc = ToonEx.encode!(%{"x" => "🎉"})
      {:ok, dec} = ToonEx.decode(enc)
      assert dec["x"] == "🎉"
    end

    test "unicode key round-trips when quoted" do
      enc = ToonEx.encode!(%{"名前" => "Alice"})
      {:ok, dec} = ToonEx.decode(enc)
      assert dec["名前"] == "Alice"
    end
  end

  # ── number boundary values ────────────────────────────────────────────────────

  describe "number boundaries" do
    test "max safe integer round-trips" do
      # 2^53 - 1
      assert {:ok, %{"n" => 9_007_199_254_740_991}} =
               ToonEx.decode("n: 9007199254740991")
    end

    test "very small positive float" do
      {:ok, r} = ToonEx.decode("x: 1.0e-15")
      assert_in_delta r["x"], 1.0e-15, 1.0e-25
    end

    test "float encode/decode preserves value" do
      value = 1.0 / 3.0
      enc = ToonEx.encode!(%{"x" => value})
      {:ok, dec} = ToonEx.decode(enc)
      assert_in_delta dec["x"], value, 1.0e-14
    end

    # Infinity cannot be constructed via arithmetic on all BEAM versions —
    # float overflow raises badarith rather than producing :infinity.
    # The is_finite guard in Utils (abs > 1.0e308) is covered by the
    # normalize tests; we only verify the max finite value here.
    test "max representable float encodes to a value, not null" do
      result = ToonEx.encode!(%{"x" => 1.0e308})
      refute result == "x: null"
    end
  end

  # ── large documents ───────────────────────────────────────────────────────────

  describe "large documents" do
    test "map with 200 keys round-trips" do
      data = for i <- 1..200, into: %{}, do: {"key_#{i}", i}
      enc = ToonEx.encode!(data)
      {:ok, dec} = ToonEx.decode(enc)
      assert dec == data
    end

    test "tabular array with 500 rows round-trips" do
      data = for i <- 1..500, do: %{"id" => i, "name" => "item_#{i}"}
      enc = ToonEx.encode!(data)
      {:ok, dec} = ToonEx.decode(enc)
      assert length(dec) == 500
      assert hd(dec)["id"] == 1
      assert List.last(dec)["id"] == 500
    end

    test "list with 100 elements round-trips" do
      data = Enum.to_list(1..100)
      enc = ToonEx.encode!(data)
      {:ok, dec} = ToonEx.decode(enc)
      assert dec == data
    end

    test "deeply nested object 10 levels" do
      data =
        Enum.reduce(1..10, %{"leaf" => "val"}, fn i, acc ->
          %{"level_#{i}" => acc}
        end)

      enc = ToonEx.encode!(data)
      {:ok, dec} = ToonEx.decode(enc)
      assert dec == ToonEx.Utils.normalize(data)
    end
  end

  # ── blank-line handling ───────────────────────────────────────────────────────

  describe "blank lines" do
    test "trailing blank lines are ignored" do
      assert {:ok, %{"x" => 1}} = ToonEx.decode("x: 1\n\n\n")
    end

    test "leading blank lines produce empty map" do
      assert {:ok, %{}} = ToonEx.decode("\n\n")
    end

    test "blank line between top-level keys is tolerated" do
      {:ok, r} = ToonEx.decode("a: 1\n\nb: 2")
      assert r == %{"a" => 1, "b" => 2}
    end

    test "blank line inside nested object non-strict" do
      {:ok, r} = ToonEx.decode("parent:\n  a: 1\n\n  b: 2", strict: false)
      assert r["parent"] == %{"a" => 1, "b" => 2}
    end

    test "blank line after nested object, sibling follows" do
      {:ok, r} = ToonEx.decode("parent:\n  a: 1\n\nsibling: 99", strict: false)
      assert r["sibling"] == 99
      assert r["parent"] == %{"a" => 1}
    end

    test "multiple consecutive blank lines inside nested non-strict" do
      {:ok, r} = ToonEx.decode("parent:\n  a: 1\n\n\n\n  b: 2", strict: false)
      assert r["parent"] == %{"a" => 1, "b" => 2}
    end
  end

  # ── key_order option ──────────────────────────────────────────────────────────

  describe "key_order encoding option" do
    test "key_order list controls output order" do
      data = %{"z" => 1, "a" => 2, "m" => 3}
      result = ToonEx.encode!(data, key_order: ["m", "a", "z"])
      assert result == "m: 3\na: 2\nz: 1"
    end

    test "partial key_order falls back to alphabetical" do
      data = %{"z" => 1, "a" => 2}
      # missing "a"
      result = ToonEx.encode!(data, key_order: ["z"])
      assert result == "a: 2\nz: 1"
    end

    test "key_order does not affect decode" do
      {:ok, r} = ToonEx.decode("z: 1\na: 2")
      assert Map.keys(r) |> Enum.sort() == ["a", "z"]
    end

    test "tabular array uses key_order for column order" do
      data = [%{"z" => 1, "a" => 2}]
      result = ToonEx.encode!(data, key_order: ["z", "a"])
      assert result =~ "{z,a}:"
    end
  end

  # ── length_marker option ──────────────────────────────────────────────────────

  describe "length_marker encoding option" do
    test "length_marker prefix is added to array header" do
      {:ok, r} = ToonEx.encode(%{"x" => [1, 2]}, length_marker: "#")
      assert r == "x[#2]: 1,2"
    end

    test "length_marker prefix added to tabular array" do
      data = [%{"a" => 1}]
      {:ok, r} = ToonEx.encode(%{"rows" => data}, length_marker: "#")
      assert r =~ "[#1]{"
    end

    test "length_marker prefix added to empty array" do
      {:ok, r} = ToonEx.encode(%{"x" => []}, length_marker: "#")
      assert r == "x[#0]:"
    end

    # length_marker is an encoder-only decoration. The standard decoder does
    # not accept the # prefix inside []; encode and decode are not symmetric
    # when this option is used.
  end

  # ── ToonEx.encode! / ToonEx.decode! error propagation ────────────────────────────

  describe "bang function error propagation" do
    test "decode! raises DecodeError on invalid input" do
      assert_raise ToonEx.DecodeError, fn -> ToonEx.decode!("x[3]: a,b") end
    end

    # encode! wraps option errors as ToonEx.EncodeError, not ArgumentError.
    # (ArgumentError is only raised by validate!/1 when called directly.)
    test "encode! raises ToonEx.EncodeError on invalid options" do
      assert_raise ToonEx.EncodeError, fn -> ToonEx.encode!(%{}, indent: 0) end
    end

    test "decode! returns value directly on success" do
      assert ToonEx.decode!("x: 1") == %{"x" => 1}
    end

    test "encode! returns string directly on success" do
      assert ToonEx.encode!(%{"x" => 1}) == "x: 1"
    end
  end

  # ── decode then encode identity ───────────────────────────────────────────────

  describe "decode → encode → decode identity" do
    @samples [
      "name: Alice\nage: 30",
      "tags[3]: a,b,c",
      "rows[2]{x,y}:\n  1,2\n  3,4",
      "items[2]:\n  - a: 1\n  - b: 2"
    ]

    for toon <- @samples do
      @toon toon
      test "decode→encode→decode: #{String.replace(@toon, "\n", "↵")}" do
        {:ok, d1} = ToonEx.decode(@toon)
        enc = ToonEx.encode!(d1)
        {:ok, d2} = ToonEx.decode(enc)
        assert d1 == d2
      end
    end
  end

  # ── coverage: decoder edge cases ────────────────────────────────────────────

  describe "decoder coverage" do
    test "nested object followed by sibling exits scope" do
      assert {:ok, result} = ToonEx.decode("parent:\n  child: v\nsibling: x")
      assert result == %{"parent" => %{"child" => "v"}, "sibling" => "x"}
    end

    test "atoms! key mode" do
      _ = String.to_atom("id")
      _ = String.to_atom("name")
      assert {:ok, result} = ToonEx.decode("id: 1\nname: Alice", keys: :atoms!)
      assert result == %{id: 1, name: "Alice"}
    end

    test "blank lines inside tabular array (non-strict)" do
      assert {:ok, result} =
               ToonEx.decode("rows[2]{a,b}:\n  1,2\n\n  3,4", strict: false)

      assert result == %{"rows" => [%{"a" => 1, "b" => 2}, %{"a" => 3, "b" => 4}]}
    end

    test "blank lines inside list array (non-strict)" do
      assert {:ok, result} =
               ToonEx.decode("items[2]:\n  - a: 1\n\n  - b: 2", strict: false)

      assert result == %{"items" => [%{"a" => 1}, %{"b" => 2}]}
    end

    test "empty nested object" do
      assert {:ok, result} = ToonEx.decode("parent:\nchild: x")
      assert result == %{"child" => "x", "parent" => %{}}
    end

    test "inline array with empty values" do
      assert {:ok, result} = ToonEx.decode("x[3]: ")
      assert result == %{"x" => []}
    end

    test "string starting with underscore" do
      assert {:ok, result} = ToonEx.decode("x: _private")
      assert result == %{"x" => "_private"}
    end

    test "line with delimiter before colon" do
      assert {:ok, result} = ToonEx.decode("items[2]{a,b}:\n  1,2:3\n  4,5:6")
      assert result == %{"items" => [%{"a" => 1, "b" => "2:3"}, %{"a" => 4, "b" => "5:6"}]}
    end

    test "unicode escape in quoted string" do
      assert {:ok, result} = ToonEx.decode(~S(x: "hello\u0041world"))
      assert result == %{"x" => "helloAworld"}
    end

    test "escaped quote inside field name" do
      assert {:ok, result} = ToonEx.decode(~S(items[1]{"field\"name",other}:) <> "\n  1,2")
      assert result == %{"items" => [%{"field\"name" => 1, "other" => 2}]}
    end

    test "nested list array count mismatch errors in strict mode" do
      assert_raise ToonEx.DecodeError, fn ->
        ToonEx.decode!("items[3]:\n  - a: 1\n  - b: 2", strict: true)
      end
    end

    test "empty keyed header without fields" do
      assert {:ok, result} = ToonEx.decode("items[2]:\n  - a: 1\n  - b: 2")
      assert result == %{"items" => [%{"a" => 1}, %{"b" => 2}]}
    end

    test "dotted key path with uppercase and underscore" do
      assert {:ok, result} = ToonEx.decode("User.name: Alice\n_Private.key: x")
      assert result == %{"User.name" => "Alice", "_Private.key" => "x"}
    end

    test "value with only digits parsed as integer" do
      assert {:ok, result} = ToonEx.decode("x: 42")
      assert result == %{"x" => 42}
    end

    test "blank lines between sibling entries (non-strict)" do
      assert {:ok, result} =
               ToonEx.decode("a: 1\n\nb: 2", strict: false)

      assert result == %{"a" => 1, "b" => 2}
    end

    test "tab character as auto-detected delimiter" do
      assert {:ok, result} =
               ToonEx.decode("rows[2]{a,b}:\n\t1,2\n\t3,4", strict: false)

      assert result == %{"rows" => [%{"a" => 1, "b" => 2}, %{"a" => 3, "b" => 4}]}
    end
  end
end
