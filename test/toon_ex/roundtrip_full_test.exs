defmodule ToonEx.Roundtrip.FullTest do
  @moduledoc """
  Exhaustive roundtrip: encode(x) |> decode() == normalize(x) for all value shapes.

  Every test follows the same pattern — the assertion is always:
    decoded == ToonEx.Utils.normalize(input)

  This ensures the encoder and decoder agree on every type and nesting depth.
  """
  use ExUnit.Case, async: true

  defp rt(value, opts \\ []) do
    encoded = ToonEx.encode!(value, opts)
    # When encoding with a non-default indent, pass matching indent_size to
    # the decoder so strict indentation validation does not reject valid output.
    indent_size = Keyword.get(opts, :indent, 2)

    decode_opts =
      opts
      |> Keyword.take([:keys, :expand_paths])
      |> Keyword.put(:indent_size, indent_size)

    {:ok, decoded} = ToonEx.decode(encoded, decode_opts)
    normalized = ToonEx.Utils.normalize(value)
    {encoded, decoded, normalized}
  end

  defp assert_rt(value, opts \\ []) do
    {_enc, decoded, norm} = rt(value, opts)

    assert decoded == norm,
           "Roundtrip failed\nInput:      #{inspect(value)}\nNormalized: #{inspect(norm)}\nDecoded:    #{inspect(decoded)}"
  end

  # ── primitives ───────────────────────────────────────────────────────────────

  describe "primitives" do
    test "nil" do
      assert_rt(nil)
    end

    test "true" do
      assert_rt(true)
    end

    test "false" do
      assert_rt(false)
    end

    test "zero" do
      assert_rt(0)
    end

    test "positive integer" do
      assert_rt(42)
    end

    test "negative integer" do
      assert_rt(-17)
    end

    test "large integer" do
      assert_rt(999_999_999)
    end

    test "float" do
      assert_rt(3.14)
    end

    test "negative float" do
      assert_rt(-2.5)
    end

    test "whole float" do
      assert_rt(1.0)
    end

    test "empty string" do
      assert_rt("")
    end

    test "simple string" do
      assert_rt("hello")
    end

    test "string with colon" do
      assert_rt("a:b")
    end

    test "string with bracket" do
      assert_rt("a[1]")
    end

    test "string with newline" do
      assert_rt("line1\nline2")
    end

    test "string with backslash" do
      assert_rt("a\\b")
    end

    test "string with tab" do
      assert_rt("a\tb")
    end

    test "atom → string" do
      {_, d, n} = rt(:hello)
      assert d == n
    end

    test "negative zero → 0" do
      {_, d, _} = rt(-0.0)
      assert d === 0
      assert is_integer(d)
    end

    test "small float no scientific notation" do
      {enc, decoded, norm} = rt(1.0e-10)
      refute String.contains?(enc, "e")
      assert_in_delta decoded, norm, 1.0e-20
    end

    # Infinity cannot be constructed via arithmetic on all BEAM versions.
    # The is_finite boundary is tested in ToonEx.Utils.NormalizeTest.

    test "large float no scientific notation" do
      value = 1.234_567_89e15
      {enc, decoded, norm} = rt(value)
      refute String.contains?(enc, "e")
      assert decoded == norm
    end
  end

  # ── maps ─────────────────────────────────────────────────────────────────────

  describe "maps" do
    test "empty map" do
      assert_rt(%{})
    end

    test "single key" do
      assert_rt(%{"a" => 1})
    end

    test "multiple keys" do
      assert_rt(%{"a" => 1, "b" => 2})
    end

    test "atom keys" do
      {_, d, n} = rt(%{a: 1, b: 2})
      assert d == n
    end

    test "nested map 1 level" do
      assert_rt(%{"a" => %{"b" => 1}})
    end

    test "nested map 2 levels" do
      assert_rt(%{"a" => %{"b" => %{"c" => 1}}})
    end

    test "nested map 5 levels" do
      assert_rt(%{"a" => %{"b" => %{"c" => %{"d" => %{"e" => 42}}}}})
    end

    test "mixed value types" do
      assert_rt(%{"s" => "hi", "n" => 1, "f" => 1.5, "b" => true, "nil" => nil})
    end

    test "empty nested map" do
      assert_rt(%{"x" => %{}})
    end

    test "key with dot" do
      assert_rt(%{"a.b" => 1})
    end

    test "key requiring quotes" do
      assert_rt(%{"full name" => "Alice"})
    end

    test "sibling after nested" do
      assert_rt(%{"user" => %{"name" => "Bob"}, "active" => true})
    end
  end

  # ── lists ────────────────────────────────────────────────────────────────────

  describe "lists" do
    test "empty list" do
      assert_rt([])
    end

    test "list of integers" do
      assert_rt([1, 2, 3])
    end

    test "list of strings" do
      assert_rt(["a", "b", "c"])
    end

    test "list of booleans" do
      assert_rt([true, false])
    end

    test "list of nulls" do
      assert_rt([nil, nil])
    end

    test "list of atoms" do
      {_, d, n} = rt([:a, :b])
      assert d == n
    end

    test "mixed primitive list" do
      assert_rt([1, "two", nil, true])
    end

    test "list with empty object" do
      assert_rt([%{}, 1, %{}])
    end

    test "list of maps same keys (tabular)" do
      assert_rt([%{"x" => 1, "y" => 2}, %{"x" => 3, "y" => 4}])
    end

    test "list of maps diff keys (list format)" do
      assert_rt([%{"a" => 1}, %{"b" => 2}])
    end

    test "list of maps with nested values (list format)" do
      assert_rt([%{"id" => 1, "meta" => %{"x" => 1}}, %{"id" => 2, "meta" => %{"x" => 2}}])
    end

    test "nested lists 2 levels" do
      assert_rt([[1, 2], [3, 4]])
    end

    test "nested lists 3 levels" do
      assert_rt([[[1]]])
    end

    test "nested lists 4 levels" do
      assert_rt([[[[1]]]])
    end

    test "nested lists 5 levels" do
      assert_rt([[[[[1]]]]])
    end

    test "nested lists mixed depths" do
      assert_rt([[1], [[2]], [[[3]]]])
    end

    test "empty nested lists" do
      assert_rt([[]])
    end

    test "double empty nested" do
      assert_rt([[[]]])
    end

    test "sibling empty lists" do
      assert_rt([[], []])
    end

    test "map inside list" do
      assert_rt([%{"a" => 1, "b" => 2}])
    end

    test "list inside map" do
      assert_rt(%{"items" => [1, 2, 3]})
    end

    test "list inside nested map" do
      assert_rt(%{"a" => %{"items" => ["x", "y"]}})
    end
  end

  # ── delimiter variants ────────────────────────────────────────────────────────

  describe "delimiter variants" do
    test "comma (default)" do
      assert_rt([1, 2, 3])
    end

    test "tab delimiter" do
      assert_rt([1, 2, 3], delimiter: "\t")
    end

    test "pipe delimiter" do
      assert_rt([1, 2, 3], delimiter: "|")
    end

    test "tab delimiter preserves string with comma" do
      data = %{"x" => ["a,b", "c"]}
      {_enc, decoded, _norm} = rt(data, delimiter: "\t")
      assert decoded["x"] == ["a,b", "c"]
    end

    test "pipe delimiter preserves string with comma" do
      data = %{"x" => ["a,b", "c"]}
      {_enc, decoded, _norm} = rt(data, delimiter: "|")
      assert decoded["x"] == ["a,b", "c"]
    end
  end

  # ── indent variants ───────────────────────────────────────────────────────────

  describe "indent variants" do
    for i <- [1, 2, 4, 8] do
      @i i
      test "indent: #{i}" do
        assert_rt(%{"a" => %{"b" => 1}}, indent: @i)
      end
    end
  end

  # ── decode-only correctness ───────────────────────────────────────────────────

  describe "decode correctness — values not from encode" do
    test "leading zero is string" do
      {:ok, r} = ToonEx.decode("x: 05")
      assert r["x"] == "05"
    end

    test "minus-zero is integer 0" do
      {:ok, r} = ToonEx.decode("x: -0")
      assert r["x"] === 0
    end

    test "quoted number remains string" do
      {:ok, r} = ToonEx.decode(~s(x: "42"))
      assert r["x"] == "42"
      assert is_binary(r["x"])
    end

    test "quoted true remains string" do
      {:ok, r} = ToonEx.decode(~s(x: "true"))
      assert r["x"] == "true"
      assert is_binary(r["x"])
    end

    test "quoted null remains string" do
      {:ok, r} = ToonEx.decode(~s(x: "null"))
      assert r["x"] == "null"
    end

    test "empty inline array" do
      {:ok, r} = ToonEx.decode("x[0]:")
      assert r["x"] == []
    end

    test "spaces around comma delimiter in inline array" do
      {:ok, r} = ToonEx.decode("x[2]: a , b")
      assert r["x"] == ["a", "b"]
    end

    test "empty token in inline array" do
      {:ok, r} = ToonEx.decode("x[3]: a,,c")
      assert r["x"] == ["a", "", "c"]
    end

    test "tab-delimited inline array" do
      {:ok, r} = ToonEx.decode("x[3\t]: 1\t2\t3")
      assert r["x"] == [1, 2, 3]
    end
  end

  # ── error cases ───────────────────────────────────────────────────────────────

  describe "decode errors" do
    test "array length mismatch" do
      assert_raise ToonEx.DecodeError, fn -> ToonEx.decode!("x[3]: a,b") end
    end

    test "tabular row count mismatch" do
      assert_raise ToonEx.DecodeError, fn ->
        ToonEx.decode!("rows[3]{a}:\n  1\n  2")
      end
    end

    test "tabular column count mismatch" do
      assert_raise ToonEx.DecodeError, fn ->
        ToonEx.decode!("rows[1]{a,b}:\n  1,2,3")
      end
    end

    test "invalid escape in quoted string" do
      assert_raise ToonEx.DecodeError, fn -> ToonEx.decode!(~s(x: "\\q")) end
    end

    test "unterminated quoted string" do
      assert_raise ToonEx.DecodeError, fn -> ToonEx.decode!(~s(x: "no end)) end
    end

    test "tab in strict-mode indentation" do
      assert_raise ToonEx.DecodeError, fn ->
        ToonEx.decode!("a:\n\tb: 1", strict: true)
      end
    end

    test "non-existent atom with keys: :atoms!" do
      assert_raise ToonEx.DecodeError, fn ->
        ToonEx.decode!("zz_unique_nonexistent_key_xyz_999: 1", keys: :atoms!)
      end
    end
  end
end
