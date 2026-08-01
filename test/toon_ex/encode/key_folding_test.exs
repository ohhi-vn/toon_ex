defmodule ToonEx.Encode.KeyFoldingTest do
  use ExUnit.Case, async: true

  defp enc(data, opts \\ []), do: ToonEx.encode!(data, opts)

  defp rt(data, opts) do
    encoded = enc(data, opts)
    {:ok, decoded} = ToonEx.decode(encoded)
    {encoded, decoded}
  end

  # ── off (default) ────────────────────────────────────────────────────────────

  describe "key_folding: off" do
    test "single-key chain stays nested" do
      assert enc(%{"a" => %{"b" => %{"c" => 1}}}) == "a:\n  b:\n    c: 1"
    end
  end

  # ── safe — basic folding ──────────────────────────────────────────────────────

  describe "key_folding: safe — basic" do
    test "two-segment chain" do
      assert enc(%{"a" => %{"b" => 1}}, key_folding: :safe) == "a.b: 1"
    end

    test "three-segment chain" do
      assert enc(%{"a" => %{"b" => %{"c" => 1}}}, key_folding: :safe) == "a.b.c: 1"
    end

    test "folds to inline array" do
      result = enc(%{"data" => %{"meta" => %{"items" => ["x", "y"]}}}, key_folding: :safe)
      assert result == "data.meta.items[2]: x,y"
    end

    test "folds chain ending with empty object" do
      assert enc(%{"a" => %{"b" => %{"c" => %{}}}}, key_folding: :safe) == "a.b.c:"
    end

    test "folds chain ending with list" do
      result = enc(%{"x" => %{"y" => [1, 2]}}, key_folding: :safe)
      assert result == "x.y[2]: 1,2"
    end

    test "folds chain ending with nil" do
      result = enc(%{"x" => %{"y" => nil}}, key_folding: :safe)
      assert result == "x.y: null"
    end

    test "folds chain ending with boolean" do
      result = enc(%{"x" => %{"y" => true}}, key_folding: :safe)
      assert result == "x.y: true"
    end
  end

  # ── safe — segment validation ─────────────────────────────────────────────────

  describe "key_folding: safe — segment validation" do
    test "segment with hyphen stops folding" do
      result = enc(%{"a" => %{"b-c" => %{"d" => 1}}}, key_folding: :safe)
      # "b-c" is not a valid IdentifierSegment → fold stops after "a"
      assert result == "a:\n  \"b-c\":\n    d: 1"
    end

    test "segment starting with digit stops folding" do
      result = enc(%{"a" => %{"1b" => 1}}, key_folding: :safe)
      # "1b" is not a valid IdentifierSegment
      refute String.contains?(result, "a.1b")
    end

    test "segment with space stops folding" do
      result = enc(%{"a" => %{"b c" => 1}}, key_folding: :safe)
      refute String.contains?(result, "a.b c")
    end
  end

  # ── safe — multi-key sibling maps (no folding) ────────────────────────────────

  describe "key_folding: safe — no folding when map has siblings" do
    test "map with two sibling keys is NOT folded" do
      result = enc(%{"a" => %{"b" => 1, "c" => 2}}, key_folding: :safe)
      # {a: {b:1, c:2}} has two keys — can't fold "a" into a dotted path
      assert result == "a:\n  b: 1\n  c: 2"
    end

    test "chain breaks at multi-key node" do
      result = enc(%{"a" => %{"b" => %{"c" => 1, "d" => 2}}}, key_folding: :safe)
      assert result == "a.b:\n  c: 1\n  d: 2"
    end
  end

  # ── safe — collision detection ────────────────────────────────────────────────

  describe "key_folding: safe — collision prevention" do
    test "does not fold when literal dotted key exists at same path" do
      input = %{
        "data" => %{"meta" => %{"items" => [1, 2]}},
        "data.meta.items" => "literal"
      }

      result = enc(input, key_folding: :safe)
      # "data" must NOT fold to "data.meta.items" because that key already exists
      assert result =~ "data.meta.items: literal"
      assert result =~ "data:\n"
    end
  end

  # ── flatten_depth ────────────────────────────────────────────────────────────

  describe "flatten_depth" do
    test "flatten_depth: 0 disables all folding" do
      result = enc(%{"a" => %{"b" => %{"c" => 1}}}, key_folding: :safe, flatten_depth: 0)
      assert result == "a:\n  b:\n    c: 1"
    end

    test "flatten_depth: 1 has no practical effect (need ≥2 segments)" do
      result = enc(%{"a" => %{"b" => %{"c" => 1}}}, key_folding: :safe, flatten_depth: 1)
      assert result == "a:\n  b:\n    c: 1"
    end

    test "flatten_depth: 2 folds two levels only" do
      result =
        enc(%{"a" => %{"b" => %{"c" => %{"d" => 1}}}}, key_folding: :safe, flatten_depth: 2)

      assert result == "a.b:\n  c:\n    d: 1"
    end

    test "flatten_depth: 3 folds three levels" do
      result =
        enc(%{"a" => %{"b" => %{"c" => %{"d" => 1}}}}, key_folding: :safe, flatten_depth: 3)

      assert result == "a.b.c:\n  d: 1"
    end

    test "flatten_depth: :infinity folds all (default)" do
      result =
        enc(%{"a" => %{"b" => %{"c" => %{"d" => 1}}}},
          key_folding: :safe,
          flatten_depth: :infinity
        )

      assert result == "a.b.c.d: 1"
    end
  end

  # ── roundtrip ─────────────────────────────────────────────────────────────────

  describe "key_folding roundtrip" do
    test "folded output decodes back to original" do
      input = %{"a" => %{"b" => %{"c" => 1}}}
      {_enc, decoded} = rt(input, key_folding: :safe)
      assert decoded == %{"a.b.c" => 1}
      # Note: folded keys are read back as dotted literal keys by default decoder
      # To recover the original structure, use expand_paths: safe on decode
    end

    test "folded output + expand_paths recovers original structure" do
      input = %{"a" => %{"b" => %{"c" => 1}}}
      encoded = enc(input, key_folding: :safe)
      {:ok, decoded} = ToonEx.decode(encoded, expand_paths: :safe)
      assert decoded == input
    end

    test "folded array roundtrip with expand_paths" do
      input = %{"data" => %{"items" => ["x", "y"]}}
      encoded = enc(input, key_folding: :safe)
      {:ok, decoded} = ToonEx.decode(encoded, expand_paths: :safe)
      assert decoded == input
    end
  end
end
