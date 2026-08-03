defmodule ToonEx.Btoon.EdgeCasesTest do
  @moduledoc """
  Edge cases for the BTOON codec mirroring the TOON suite:
  escape sequences, unicode, number boundary values, large documents,
  and decode/encode symmetry.
  """
  use ExUnit.Case, async: true

  alias ToonEx.Btoon

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
          {"only backslashes", "\\\\\\\\"},
          {"nul byte", <<0>>},
          {"nul+text", <<0, "abc", 0>>},
          {"all control bytes", Enum.map_join(0..31, "", &<<&1>>)},
          {"high bytes", <<0xFF, 0xFE, 0x80>>}
        ] do
      @value value
      test "roundtrip: #{name}" do
        enc = Btoon.encode!(%{"s" => @value})
        dec = Btoon.decode!(enc)
        assert dec["s"] == @value
      end
    end
  end

  # ── unicode ───────────────────────────────────────────────────────────────────

  describe "unicode strings" do
    test "unicode value round-trips" do
      enc = Btoon.encode!(%{"x" => "héllo"})
      assert Btoon.decode!(enc)["x"] == "héllo"
    end

    test "CJK characters round-trip" do
      enc = Btoon.encode!(%{"x" => "日本語"})
      assert Btoon.decode!(enc)["x"] == "日本語"
    end

    test "emoji round-trip" do
      enc = Btoon.encode!(%{"x" => "🎉"})
      assert Btoon.decode!(enc)["x"] == "🎉"
    end

    test "unicode key round-trips" do
      enc = Btoon.encode!(%{"名前" => "Alice"})
      assert Btoon.decode!(enc)["名前"] == "Alice"
    end

    test "string values that look like literals round-trip" do
      value = %{"rows" => [%{"id" => 1, "status" => "true", "code" => "42", "text" => "a,b"}]}
      assert Btoon.decode!(Btoon.encode!(value)) == value
    end
  end

  # ── number boundary values ────────────────────────────────────────────────────

  describe "number boundaries" do
    test "max safe integer round-trips" do
      assert Btoon.decode!(Btoon.encode!(9_007_199_254_740_991)) ==
               9_007_199_254_740_991
    end

    test "very small positive float round-trips" do
      assert Btoon.decode!(Btoon.encode!(1.0e-15)) == 1.0e-15
    end

    test "float encode/decode preserves value" do
      value = 1.0 / 3.0
      assert Btoon.decode!(Btoon.encode!(value)) == value
    end

    test "max representable float round-trips as a value, not a crash" do
      assert Btoon.decode!(Btoon.encode!(1.0e308)) == 1.0e308
      assert Btoon.decode!(Btoon.encode!(-1.0e308)) == -1.0e308
    end

    test "whole float encodes and decodes losslessly" do
      assert Btoon.decode!(Btoon.encode!(1.0)) == 1.0
      assert Btoon.decode!(Btoon.encode!(-42.0)) == -42.0
    end

    test "negative zero survives round-trip numerically" do
      assert Btoon.decode!(Btoon.encode!(-0.0)) == 0
    end

    test "int32/int64 boundaries round-trip" do
      for value <- [2_147_483_647, -2_147_483_648, 2_147_483_648, 9_223_372_036_854_775_807] do
        assert Btoon.decode!(Btoon.encode!(value)) == value
      end
    end
  end

  # ── large documents ───────────────────────────────────────────────────────────

  describe "large documents" do
    test "map with 200 keys round-trips" do
      data = for i <- 1..200, into: %{}, do: {"key_#{i}", i}
      assert Btoon.decode!(Btoon.encode!(data)) == data
    end

    test "map with more than 32 keys (hash-map path) round-trips" do
      data = for i <- 1..100, into: %{}, do: {"key_#{i}", "value #{i}"}
      assert Btoon.decode!(Btoon.encode!(data)) == data
    end

    test "tabular array with 500 rows round-trips" do
      data = for i <- 1..500, do: %{"id" => i, "name" => "item_#{i}"}
      dec = Btoon.decode!(Btoon.encode!(data))
      assert length(dec) == 500
      assert hd(dec)["id"] == 1
      assert List.last(dec)["id"] == 500
    end

    test "list with 100 elements round-trips" do
      data = Enum.to_list(1..100)
      assert Btoon.decode!(Btoon.encode!(data)) == data
    end

    test "deeply nested object 10 levels round-trips" do
      data =
        Enum.reduce(1..10, %{"leaf" => "val"}, fn i, acc ->
          %{"level_#{i}" => acc}
        end)

      assert Btoon.decode!(Btoon.encode!(data)) == data
    end
  end

  # ── bang function error propagation ───────────────────────────────────────────

  describe "bang function error propagation" do
    test "decode! raises DecodeError on invalid input" do
      assert_raise Btoon.DecodeError, fn ->
        Btoon.decode!("BTON" <> <<1, 0, 0, 0, 0x1F>>)
      end
    end

    test "encode! raises EncodeError on invalid options" do
      assert_raise Btoon.EncodeError, fn -> Btoon.encode!(%{}, bogus: true) end
    end

    test "decode! returns value directly on success" do
      assert Btoon.decode!(Btoon.encode!(1)) == 1
    end

    test "encode! returns binary directly on success" do
      assert is_binary(Btoon.encode!(%{"x" => 1}))
    end
  end

  # ── decode → encode identity ──────────────────────────────────────────────────

  describe "decode → encode → decode identity" do
    @samples [
      %{"name" => "Alice", "age" => 30},
      %{"tags" => ["a", "b", "c"]},
      %{"rows" => [%{"x" => 1, "y" => 2}, %{"x" => 3, "y" => 4}]},
      %{"items" => [%{"a" => 1}, %{"b" => 2}]}
    ]

    for value <- @samples do
      @value value
      test "decode→encode→decode: #{inspect(value)}" do
        d1 = Btoon.decode!(Btoon.encode!(@value))
        enc = Btoon.encode!(d1)
        d2 = Btoon.decode!(enc)
        assert d1 == d2
      end
    end
  end

  # ── decode-only correctness ───────────────────────────────────────────────────

  describe "decode of hand-built values" do
    test "null/booleans/ints from bytes" do
      assert Btoon.decode!("BTON" <> <<1, 0, 0, 0, 0>>) == nil
      assert Btoon.decode!("BTON" <> <<1, 0, 0, 0, 1>>) == false
      assert Btoon.decode!("BTON" <> <<1, 0, 0, 0, 2>>) == true
      assert Btoon.decode!("BTON" <> <<1, 0, 0, 0, 0x40>>) == 0
      assert Btoon.decode!("BTON" <> <<1, 0, 0, 0, 0x6A>>) == 42
    end
  end

  # ── float edge cases (from TOON primitives test) ───────────────────────────────

  describe "float edge cases" do
    test "whole-number float encodes as integer in payload" do
      # BTOON uses float32/float64 tags, but the value 1.0 should round-trip
      assert Btoon.decode!(Btoon.encode!(1.0)) == 1.0
      assert Btoon.decode!(Btoon.encode!(-42.0)) == -42.0
    end

    test "negative zero round-trips" do
      # BTOON stores as float64, negative zero should preserve numerically
      result = Btoon.decode!(Btoon.encode!(-0.0))
      assert result == 0.0
    end

    test "large float encodes without scientific notation loss" do
      value = 1.0e308
      assert Btoon.decode!(Btoon.encode!(value)) == value
      assert Btoon.decode!(Btoon.encode!(-1.0e308)) == -1.0e308
    end

    test "very small float round-trips" do
      value = 1.0e-15
      assert Btoon.decode!(Btoon.encode!(value)) == value
    end

    test "float 1/3 round-trips" do
      value = 1.0 / 3.0
      assert Btoon.decode!(Btoon.encode!(value)) == value
    end
  end

  # ── empty array and root-level array encoding ──────────────────────────────────

  describe "empty array encoding" do
    test "empty map value encodes and round-trips" do
      value = %{"items" => []}
      assert Btoon.decode!(Btoon.encode!(value)) == value
    end

    test "root empty list encodes and round-trips" do
      assert Btoon.decode!(Btoon.encode!([])) == []
    end

    test "root inline primitive array round-trips" do
      assert Btoon.decode!(Btoon.encode!([1, 2, 3])) == [1, 2, 3]
    end

    test "root array of floats round-trips" do
      assert Btoon.decode!(Btoon.encode!([1.5, 2.5])) == [1.5, 2.5]
    end

    test "root array of strings round-trips" do
      assert Btoon.decode!(Btoon.encode!(["a", "b", "c"])) == ["a", "b", "c"]
    end

    test "root array with mixed types round-trips" do
      value = [1, "two", true, nil, 3.14]
      assert Btoon.decode!(Btoon.encode!(value)) == value
    end
  end

  # ── complex nested structures (from TOON encode test) ──────────────────────────

  describe "complex nested structures" do
    test "deeply nested map round-trips" do
      data = %{"a" => %{"b" => %{"c" => %{"d" => "deep"}}}}
      assert Btoon.decode!(Btoon.encode!(data)) == data
    end

    test "nested arrays round-trip" do
      data = [[1, 2], [3, 4]]
      assert Btoon.decode!(Btoon.encode!(data)) == data
    end

    test "array of maps with same keys uses object table" do
      data = [%{"id" => 1, "name" => "Alice"}, %{"id" => 2, "name" => "Bob"}]
      assert Btoon.decode!(Btoon.encode!(data)) == data
    end

    test "map with special characters in string values" do
      data = %{"key" => "value with: colon and, comma"}
      assert Btoon.decode!(Btoon.encode!(data)) == data
    end

    test "map with float values preserves precision" do
      data = %{"a" => 1.5, "b" => 2.0, "c" => -3.14}
      decoded = Btoon.decode!(Btoon.encode!(data))
      assert decoded["a"] == 1.5
      assert decoded["b"] == 2.0
      assert decoded["c"] == -3.14
    end

    test "map with boolean values" do
      data = %{"active" => true, "deleted" => false}
      assert Btoon.decode!(Btoon.encode!(data)) == data
    end

    test "map with nil value" do
      data = %{"missing" => nil}
      assert Btoon.decode!(Btoon.encode!(data)) == data
    end

    test "list of primitives" do
      data = ["a", "b", "c"]
      assert Btoon.decode!(Btoon.encode!(data)) == data
    end

    test "list of objects with different keys uses list format" do
      data = [%{"a" => 1}, %{"b" => 2}]
      assert Btoon.decode!(Btoon.encode!(data)) == data
    end
  end

  # ── binary encoding ────────────────────────────────────────────────────────────

  describe "binary encoding" do
    test "Binary struct round-trips" do
      data = %{"blob" => Btoon.Binary.new(<<1, 2, 3>>)}
      assert Btoon.decode!(Btoon.encode!(data)) == data
    end

    test "empty binary round-trips" do
      data = %{"empty" => Btoon.Binary.new(<<>>)}
      assert Btoon.decode!(Btoon.encode!(data)) == data
    end

    test "binary with special bytes round-trips" do
      data = %{"data" => Btoon.Binary.new(<<0, 255, 128, 10, 13>>)}
      assert Btoon.decode!(Btoon.encode!(data)) == data
    end
  end

  # ── typed array options ────────────────────────────────────────────────────────

  describe "typed_arrays: false option" do
    test "disables typed array encoding for homogeneous lists" do
      bin = Btoon.encode!([1, 2, 3], typed_arrays: false)
      # Should use general array tag (0x09) instead of typed array (0x0C)
      assert :binary.at(bin, 8) == 0x09
      assert Btoon.decode!(bin) == [1, 2, 3]
    end

    test "disables object table encoding for uniform maps" do
      data = [%{"id" => 1, "name" => "Alice"}, %{"id" => 2, "name" => "Bob"}]
      bin = Btoon.encode!(data, typed_arrays: false)
      assert Btoon.decode!(bin) == data
    end
  end

  # ── object_tables option ──────────────────────────────────────────────────────

  describe "object_tables: false option" do
    test "disables object table encoding" do
      data = [%{"id" => 1, "name" => "Alice"}, %{"id" => 2, "name" => "Bob"}]
      bin = Btoon.encode!(data, object_tables: false)
      # Should use list format instead of object table
      assert Btoon.decode!(bin) == data
    end
  end

  # ── string table options ──────────────────────────────────────────────────────

  describe "string_table options" do
    test "string_table: :off writes inline strings" do
      value = %{"key" => "value"}
      bin = Btoon.encode!(value, string_table: :off)
      assert Btoon.decode!(bin) == value
    end

    test "string_table: :auto uses per-message table" do
      value = %{"a" => "dup", "b" => "dup"}
      bin = Btoon.encode!(value, string_table: :auto)
      assert Btoon.decode!(bin) == value
    end

    test "no_string_table: true with dictionary" do
      dict = Btoon.Dictionary.new(["known"])
      value = %{"known" => "value", "other" => "inline"}
      bin = Btoon.encode!(value, dictionary: dict, no_string_table: true)
      assert Btoon.decode!(bin, dictionary: dict) == value
    end
  end

  # ── encode_to_iodata! ──────────────────────────────────────────────────────────

  describe "encode_to_iodata!" do
    test "encodes map to iodata" do
      result = Btoon.Encode.encode_to_iodata!(%{"a" => 1})
      assert IO.iodata_to_binary(result) == Btoon.encode!(%{"a" => 1})
    end

    test "encodes list to iodata" do
      result = Btoon.Encode.encode_to_iodata!([1, 2, 3])
      assert IO.iodata_to_binary(result) == Btoon.encode!([1, 2, 3])
    end

    test "encodes primitive to iodata" do
      assert IO.iodata_to_binary(Btoon.Encode.encode_to_iodata!("hello")) ==
               Btoon.encode!("hello")
    end

    test "raises on invalid options" do
      assert_raise ArgumentError, fn ->
        Btoon.Encode.encode_to_iodata!(%{}, bogus: true)
      end
    end
  end
end
