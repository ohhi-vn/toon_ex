defmodule ToonEx.Encode.StreamTest do
  use ExUnit.Case, async: true

  alias ToonEx.Encode.Stream

  defp streamed(data, opts \\ []) do
    data
    |> Stream.encode_stream(opts)
    |> Enum.map_join("", &IO.iodata_to_binary/1)
  end

  defp assert_matches_direct(data, opts \\ []) do
    assert streamed(data, opts) == ToonEx.encode!(data, opts)
  end

  describe "output equals the non-streamed encoder" do
    test "root primitives are not supported by the stream encoder" do
      assert_raise FunctionClauseError, fn ->
        Stream.encode_stream(42) |> Enum.to_list()
      end
    end

    test "small flat map" do
      assert_matches_direct(%{"a" => 1, "b" => "two", "c" => true, "d" => nil})
    end

    test "nested maps and arrays" do
      data = %{
        "user" => %{"name" => "Ada", "tags" => ["x", "y"]},
        "scores" => [1, 2, 3],
        "empty" => [],
        "nothing" => %{}
      }

      assert_matches_direct(data)
    end

    # Root lists encode as if wrapped under a synthetic "items" key, per the
    # module's fragment contract.
    test "root inline array wraps under items" do
      assert streamed([1, "a", true]) == ToonEx.encode!(%{"items" => [1, "a", true]})
    end

    test "root empty array wraps under items" do
      assert streamed([]) == "items: []"
    end

    test "root tabular array wraps under items with newline-separated rows" do
      assert streamed([%{"a" => 1, "b" => 2}, %{"a" => 3, "b" => 4}]) ==
               ToonEx.encode!(%{"items" => [%{"a" => 1, "b" => 2}, %{"a" => 3, "b" => 4}]})
    end

    test "root list array (mixed) wraps under items with newline-separated items" do
      assert streamed([%{"a" => 1}, [1, 2], "s"]) ==
               ToonEx.encode!(%{"items" => [%{"a" => 1}, [1, 2], "s"]})
    end

    test "OrderedObject values" do
      oo = %ToonEx.OrderedObject{values: [{"z", 1}, {"a", %{"n" => 2}}]}
      assert_matches_direct(%{"wrap" => oo})
    end

    test "fragment value" do
      fragment = ToonEx.Fragment.new("inner: 1")
      assert_matches_direct(%{"f" => fragment})
    end

    test "unsupported entry becomes null" do
      assert streamed(%{"pid" => self()}) == "pid: null"
    end

    test "delimiter and length marker options are honored" do
      assert_matches_direct(%{"t" => [1, 2, 3]}, delimiter: "\t", length_marker: "#")
    end

    test "key folding safe mode" do
      data = %{"outer" => %{"inner" => %{"leaf" => 1}}, "plain" => 2}
      assert_matches_direct(data, key_folding: :safe)
    end
  end

  describe "chunking" do
    test "small documents yield a single chunk" do
      chunks = Stream.encode_stream(%{"a" => 1}) |> Enum.to_list()
      assert length(chunks) == 1
    end

    test "maps over the flush threshold split into multiple chunks" do
      data = Map.new(1..250, fn i -> {"k#{String.pad_leading(to_string(i), 4, "0")}", i} end)

      chunks =
        Stream.encode_stream(data) |> Enum.map(&IO.iodata_to_binary/1)

      assert length(chunks) > 1
      assert Enum.map_join(chunks, "", & &1) == ToonEx.encode!(data)
    end

    test "exactly at the threshold stays correct" do
      data = Map.new(1..100, fn i -> {"k#{String.pad_leading(to_string(i), 4, "0")}", i} end)

      chunks = Stream.encode_stream(data) |> Enum.map(&IO.iodata_to_binary/1)
      assert Enum.join(chunks, "") == ToonEx.encode!(data)
    end

    test "flush boundary does not duplicate or drop lines" do
      data = Map.new(1..350, fn i -> {"k#{String.pad_leading(to_string(i), 4, "0")}", i} end)

      joined =
        Stream.encode_stream(data) |> Enum.map_join("", &IO.iodata_to_binary/1)

      direct_lines = String.split(ToonEx.encode!(data), "\n")
      stream_lines = String.split(joined, "\n")

      assert Enum.sort(stream_lines) == Enum.sort(direct_lines)
      assert length(stream_lines) == length(direct_lines)
    end

    test "large tabular payload splits correctly" do
      data = %{"rows" => Enum.map(1..300, &%{"id" => &1, "name" => "row#{&1}"})}
      chunks = Stream.encode_stream(data) |> Enum.map(&IO.iodata_to_binary/1)

      assert Enum.join(chunks, "") == ToonEx.encode!(data)
    end

    test "chunks contain no trailing newline artifacts" do
      data = Map.new(1..120, fn i -> {"k#{i}", i} end)

      joined = Stream.encode_stream(data) |> Enum.map_join("", &IO.iodata_to_binary/1)

      refute String.ends_with?(joined, "\n")
      assert joined == ToonEx.encode!(data)
    end
  end

  describe "fragment handling" do
    test "fragment at the root is emitted as a single chunk" do
      fragment = ToonEx.Fragment.new("a: 1\nb: 2")

      assert streamed(fragment) == "a: 1\nb: 2"
    end

    test "multi-line fragment iodata containing codepoints splits into indented lines" do
      # Exercise the iodata-splitting branches: nested lists and integer codepoints.
      fragment =
        ToonEx.Fragment.new(["x: ", ["1", ?\n], ["nested: ", ["2", ?\n], "tail"], ?\n, "end: 3"])

      out = streamed(%{"wrap" => fragment})

      assert out =~ "  x: 1"
      assert out =~ "  nested: 2"
      assert out =~ "  tail"
      assert out =~ "  end: 3"
    end

    test "empty fragment contributes nothing" do
      data = %{"e" => ToonEx.Fragment.new("")}

      assert streamed(data) == ToonEx.encode!(data)
    end
  end

  describe "options validation" do
    test "invalid options raise ArgumentError" do
      assert_raise ArgumentError, fn ->
        Stream.encode_stream(%{}, indent: -3)
      end
    end

    test "invalid delimiter raises" do
      assert_raise ArgumentError, fn ->
        Stream.encode_stream(%{}, delimiter: ";")
      end
    end
  end

  describe "keyed tabular at root" do
    test "uniform map-of-maps uses the keyless keyed header" do
      data = %{"r1" => %{"v" => 1}, "r2" => %{"v" => 2}}

      assert streamed(data) == "[2:]{v}:\n  r1: 1\n  r2: 2"
    end

    test "large keyed tables still match direct encoding" do
      data =
        Map.new(1..150, fn i ->
          {"row#{String.pad_leading(to_string(i), 4, "0")}", %{"v" => i}}
        end)

      assert_matches_direct(data)
    end
  end

  describe "key ordering patterns" do
    test "list key_order at the root reorders keys" do
      data = %{"b" => 1, "a" => 2}
      assert streamed(data, key_order: ["a", "b"]) == ToonEx.encode!(data, key_order: ["a", "b"])

      assert String.starts_with?(streamed(data, key_order: ["a", "b"]), "a: 2")
    end

    test "map-shaped key_order selects per-path order" do
      data = %{"b" => 1, "a" => 2}

      assert streamed(data, key_order: %{[] => ["a", "b"]}) == "a: 2\nb: 1"
    end

    test "key_order covering nothing keeps natural order" do
      data = %{"b" => 1, "a" => 2}
      out = streamed(data, key_order: ["zzz"])
      assert out == ToonEx.encode!(data)
    end
  end

  describe "key folding shapes" do
    test "folding stops at multi-key maps and renders them nested" do
      data = %{"outer" => %{"inner" => %{"x" => 1, "y" => 2}}}
      out = streamed(data, key_folding: :safe)

      assert out == ToonEx.encode!(data, key_folding: :safe)
      assert out =~ "inner:"
    end

    test "folding through single-key chains joins dotted keys" do
      data = %{"a" => %{"b" => %{"c" => 3}}}
      assert streamed(data, key_folding: :safe) == "a.b.c: 3"
    end

    test "folding respects flatten_depth limits" do
      data = %{"a" => %{"b" => %{"c" => 3}}}

      limited = streamed(data, key_folding: :safe, flatten_depth: 1)
      assert limited == ToonEx.encode!(data, key_folding: :safe, flatten_depth: 1)
      refute limited == "a.b.c: 3"
    end

    test "folded final value that is a non-tabular map nests under dotted key" do
      data = %{"a" => %{"m" => %{"x" => 1, "y" => 2}}}
      out = streamed(data, key_folding: :safe)

      assert out == ToonEx.encode!(data, key_folding: :safe)
      assert out =~ "a.m:"
    end

    test "invalid segment keys block folding" do
      data = %{"with space" => %{"leaf" => 1}}
      assert streamed(data, key_folding: :safe) == ToonEx.encode!(data, key_folding: :safe)
    end
  end

  describe "fragment chunk splitting corner cases" do
    test "empty-string pieces inside fragment iodata are skipped" do
      fragment = ToonEx.Fragment.new(["", "k: ", "", "1"])
      assert streamed(%{"w" => fragment}) == "w:\n  k: 1"
    end

    test "single-line fragment without newline yields one indented line" do
      fragment = ToonEx.Fragment.new("only")
      assert streamed(%{"w" => fragment}) == "w:\n  only"
    end
  end

  describe "OrderedObject at top level streams directly" do
    test "ordered entries keep their declared sequence" do
      oo = %ToonEx.OrderedObject{values: [{"second", 2}, {"first", 1}]}
      assert streamed(oo) == ToonEx.encode!(oo)
      assert String.starts_with?(streamed(oo), "second: 2")
    end
  end
end
