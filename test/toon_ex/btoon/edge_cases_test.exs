defmodule ToonEx.Btoon.EdgeCasesTest do
  @moduledoc """
  Edge cases for the BTOON codec mirroring the TOON suite:
  escape sequences, unicode, number boundary values, large documents,
  and decode/encode symmetry.
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
          {"only backslashes", "\\\\\\\\"},
          {"nul byte", <<0>>},
          {"nul+text", <<0, "abc", 0>>},
          {"all control bytes", Enum.map_join(0..31, "", &<<&1>>)},
          {"high bytes", <<0xFF, 0xFE, 0x80>>}
        ] do
      @value value
      test "roundtrip: #{name}" do
        enc = ToonEx.Btoon.encode!(%{"s" => @value})
        dec = ToonEx.Btoon.decode!(enc)
        assert dec["s"] == @value
      end
    end
  end

  # ── unicode ───────────────────────────────────────────────────────────────────

  describe "unicode strings" do
    test "unicode value round-trips" do
      enc = ToonEx.Btoon.encode!(%{"x" => "héllo"})
      assert ToonEx.Btoon.decode!(enc)["x"] == "héllo"
    end

    test "CJK characters round-trip" do
      enc = ToonEx.Btoon.encode!(%{"x" => "日本語"})
      assert ToonEx.Btoon.decode!(enc)["x"] == "日本語"
    end

    test "emoji round-trip" do
      enc = ToonEx.Btoon.encode!(%{"x" => "🎉"})
      assert ToonEx.Btoon.decode!(enc)["x"] == "🎉"
    end

    test "unicode key round-trips" do
      enc = ToonEx.Btoon.encode!(%{"名前" => "Alice"})
      assert ToonEx.Btoon.decode!(enc)["名前"] == "Alice"
    end

    test "string values that look like literals round-trip" do
      value = %{"rows" => [%{"id" => 1, "status" => "true", "code" => "42", "text" => "a,b"}]}
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(value)) == value
    end
  end

  # ── number boundary values ────────────────────────────────────────────────────

  describe "number boundaries" do
    test "max safe integer round-trips" do
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(9_007_199_254_740_991)) ==
               9_007_199_254_740_991
    end

    test "very small positive float round-trips" do
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(1.0e-15)) == 1.0e-15
    end

    test "float encode/decode preserves value" do
      value = 1.0 / 3.0
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(value)) == value
    end

    test "max representable float round-trips as a value, not a crash" do
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(1.0e308)) == 1.0e308
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(-1.0e308)) == -1.0e308
    end

    test "whole float encodes and decodes losslessly" do
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(1.0)) == 1.0
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(-42.0)) == -42.0
    end

    test "negative zero survives round-trip numerically" do
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(-0.0)) == 0
    end

    test "int32/int64 boundaries round-trip" do
      for value <- [2_147_483_647, -2_147_483_648, 2_147_483_648, 9_223_372_036_854_775_807] do
        assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(value)) == value
      end
    end
  end

  # ── large documents ───────────────────────────────────────────────────────────

  describe "large documents" do
    test "map with 200 keys round-trips" do
      data = for i <- 1..200, into: %{}, do: {"key_#{i}", i}
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(data)) == data
    end

    test "map with more than 32 keys (hash-map path) round-trips" do
      data = for i <- 1..100, into: %{}, do: {"key_#{i}", "value #{i}"}
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(data)) == data
    end

    test "tabular array with 500 rows round-trips" do
      data = for i <- 1..500, do: %{"id" => i, "name" => "item_#{i}"}
      dec = ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(data))
      assert length(dec) == 500
      assert hd(dec)["id"] == 1
      assert List.last(dec)["id"] == 500
    end

    test "list with 100 elements round-trips" do
      data = Enum.to_list(1..100)
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(data)) == data
    end

    test "deeply nested object 10 levels round-trips" do
      data =
        Enum.reduce(1..10, %{"leaf" => "val"}, fn i, acc ->
          %{"level_#{i}" => acc}
        end)

      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(data)) == data
    end
  end

  # ── bang function error propagation ───────────────────────────────────────────

  describe "bang function error propagation" do
    test "decode! raises DecodeError on invalid input" do
      assert_raise ToonEx.Btoon.DecodeError, fn ->
        ToonEx.Btoon.decode!("BTON" <> <<1, 0, 0, 0, 0x1F>>)
      end
    end

    test "encode! raises EncodeError on invalid options" do
      assert_raise ToonEx.Btoon.EncodeError, fn -> ToonEx.Btoon.encode!(%{}, bogus: true) end
    end

    test "decode! returns value directly on success" do
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(1)) == 1
    end

    test "encode! returns binary directly on success" do
      assert is_binary(ToonEx.Btoon.encode!(%{"x" => 1}))
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
        d1 = ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(@value))
        enc = ToonEx.Btoon.encode!(d1)
        d2 = ToonEx.Btoon.decode!(enc)
        assert d1 == d2
      end
    end
  end

  # ── decode-only correctness ───────────────────────────────────────────────────

  describe "decode of hand-built values" do
    test "null/booleans/ints from bytes" do
      assert ToonEx.Btoon.decode!("BTON" <> <<1, 0, 0, 0, 0>>) == nil
      assert ToonEx.Btoon.decode!("BTON" <> <<1, 0, 0, 0, 1>>) == false
      assert ToonEx.Btoon.decode!("BTON" <> <<1, 0, 0, 0, 2>>) == true
      assert ToonEx.Btoon.decode!("BTON" <> <<1, 0, 0, 0, 0x40>>) == 0
      assert ToonEx.Btoon.decode!("BTON" <> <<1, 0, 0, 0, 0x6A>>) == 42
    end
  end
end
