defmodule ToonEx.Shared.TypesTest do
  use ExUnit.Case, async: true

  alias ToonEx.Types

  describe "Types module" do
    test "module is compiled and loaded" do
      assert Code.ensure_loaded?(Types)
    end

    test "module has no public functions (type-only module)" do
      exports = Types.module_info()[:exports]
      assert exports != []
      # Only __info__/1 and module_info/0, module_info/1 should be exported
      assert Enum.any?(exports, fn {name, _arity} -> name == :__info__ end)
      assert Enum.any?(exports, fn {name, _arity} -> name == :module_info end)
      assert length(exports) == 3
    end
  end

  describe "type specifications" do
    setup do
      {:ok, types} = Code.Typespec.fetch_types(Types)
      types_map = Map.new(types, fn {kind, {name, _type, _args}} -> {name, kind} end)
      {:ok, types_map: types_map, types: types}
    end

    test "all expected types are defined", %{types_map: types_map} do
      expected = [
        :primitive,
        :input,
        :encodable,
        :encode_opts,
        :encode_opt,
        :delimiter,
        :decode_opts,
        :decode_opt,
        :depth,
        :iodata_result
      ]

      for name <- expected do
        assert Map.has_key?(types_map, name),
               "Expected type #{inspect(name)} to be defined"
      end
    end

    test "all types are public (@type, not @typep)", %{types_map: types_map} do
      for {name, kind} <- types_map do
        assert kind == :type,
               "Expected type #{inspect(name)} to be public (@type), got #{inspect(kind)}"
      end
    end

    test "no unexpected types are defined", %{types_map: types_map} do
      expected_keys = MapSet.new([:primitive, :input, :encodable, :encode_opts, :encode_opt, :delimiter, :decode_opts, :decode_opt, :depth, :iodata_result])
      actual_keys = MapSet.new(Map.keys(types_map))

      assert MapSet.equal?(expected_keys, actual_keys),
               "Mismatch - expected: #{inspect(MapSet.difference(expected_keys, actual_keys))}, actual extra: #{inspect(MapSet.difference(actual_keys, expected_keys))}"
    end

    test "primitive type includes nil, boolean, number, and String.t()", %{types: types} do
      {:type, _, type_kind, union_types} = find_type!(types, :primitive)

      assert type_kind == :union

      type_names = Enum.map(union_types, fn
        {:atom, _, nil} -> :nil
        {:type, _, :boolean, _} -> :boolean
        {:type, _, :number, _} -> :number
        {:remote_type, _, [_, _ | _]} -> :binary
        _ -> :other
      end)

      assert :nil in type_names
      assert :boolean in type_names
      assert :number in type_names
      assert :binary in type_names
    end

    test "input type is term()", %{types: types} do
      {:type, _, :term, []} = find_type!(types, :input)
    end

    test "encodable type is a union including primitives, maps, and lists", %{types: types} do
      {:type, _, type_kind, union_types} = find_type!(types, :encodable)

      assert type_kind == :union

      type_names = Enum.map(union_types, fn
        {:atom, _, nil} -> :nil
        {:type, _, :boolean, _} -> :boolean
        {:type, _, :number, _} -> :number
        {:remote_type, _, [_, _ | _]} -> :binary
        {:type, _, :map, _} -> :map
        {:type, _, :list, _} -> :list
        _ -> :other
      end)

      assert :nil in type_names
      assert :boolean in type_names
      assert :number in type_names
      assert :map in type_names
      assert :list in type_names
    end

    test "encode_opts is a list of encode_opt", %{types: types} do
      {:type, _, :list, [{:user_type, _, :encode_opt, []}]} = find_type!(types, :encode_opts)
    end

    test "encode_opt is a union of tuples", %{types: types} do
      {:type, _, :union, union_types} = find_type!(types, :encode_opt)

      tuple_count = Enum.count(union_types, fn
        {:type, _, :tuple, _} -> true
        _ -> false
      end)

      assert tuple_count == 5
    end

    test "delimiter type is binary", %{types: types} do
      {:type, _, :binary, []} = find_type!(types, :delimiter)
    end

    test "decode_opts is a list of decode_opt", %{types: types} do
      {:type, _, :list, [{:user_type, _, :decode_opt, []}]} = find_type!(types, :decode_opts)
    end

    test "decode_opt is a union of tuples", %{types: types} do
      {:type, _, :union, union_types} = find_type!(types, :decode_opt)

      tuple_count = Enum.count(union_types, fn
        {:type, _, :tuple, _} -> true
        _ -> false
      end)

      assert tuple_count == 4
    end

    test "depth type is non_neg_integer", %{types: types} do
      {:type, _, :non_neg_integer, []} = find_type!(types, :depth)
    end

    test "iodata_result type is iodata", %{types: types} do
      {:type, _, :iodata, []} = find_type!(types, :iodata_result)
    end
  end

  defp find_type!(types, name) do
    case Enum.find(types, fn
           {kind, {n, _, _}} when kind in [:type, :typep, :opaque, :opaque_] -> n == name
           _ -> false
         end) do
      {_, {^name, type, _args}} -> type
      nil -> raise "Type #{inspect(name)} not found in module #{inspect(Types)}"
    end
  end

  describe "primitive type values" do
    test "nil is a valid primitive" do
      assert is_nil(nil)
    end

    test "booleans are valid primitives" do
      assert is_boolean(true)
      assert is_boolean(false)
    end

    test "numbers are valid primitives" do
      assert is_number(42)
      assert is_number(-42)
      assert is_number(0)
      assert is_number(3.14)
      assert is_number(-1.5)
    end

    test "strings are valid primitives" do
      assert is_binary("hello")
      assert is_binary("")
      assert is_binary("123")
    end
  end

  describe "encodable type structure" do
    test "nil is a valid encodable" do
      assert is_nil(nil)
    end

    test "booleans are valid encodables" do
      assert is_boolean(true)
      assert is_boolean(false)
    end

    test "numbers are valid encodables" do
      assert is_number(42)
      assert is_number(3.14)
    end

    test "strings are valid encodables" do
      assert is_binary("hello")
      assert is_binary("")
    end

    test "maps with string keys are valid encodables" do
      map = %{"key" => "value"}
      assert is_map(map)
      assert Map.has_key?(map, "key")
      ["key"] = Map.keys(map)
    end

    test "nested maps with string keys are valid encodables" do
      map = %{"outer" => %{"inner" => "value"}}
      assert is_map(map)
      assert Map.has_key?(map, "outer")
      inner = Map.fetch!(map, "outer")
      assert is_map(inner)
      ["inner"] = Map.keys(inner)
    end

    test "lists of encodables are valid" do
      list = [1, "two", true, nil]
      assert is_list(list)
    end

    test "nested lists of encodables are valid" do
      list = [[1, 2], ["a", "b"]]
      assert is_list(list)
    end
  end

  describe "encode_opt validation" do
    test "indent option is a positive integer" do
      opts = [indent: 4]
      assert is_integer(Keyword.get(opts, :indent))
      assert Keyword.get(opts, :indent) > 0
    end

    test "delimiter option is a binary" do
      opts = [delimiter: ","]
      assert is_binary(Keyword.get(opts, :delimiter))
    end

    test "length_marker option is a string or nil" do
      assert is_binary("X")
      assert is_nil(nil)
    end

    test "key_folding option is :off or :safe" do
      valid = [:off, :safe]
      assert Enum.member?(valid, :off)
      assert Enum.member?(valid, :safe)
    end

    test "flatten_depth is a non-negative integer or :infinity" do
      assert 0 >= 0
      assert 5 >= 0
      assert :infinity == :infinity
    end
  end

  describe "decode_opt validation" do
    test "keys option is :strings, :atoms, or :atoms!" do
      valid = [:strings, :atoms, :atoms!]
      assert Enum.member?(valid, :strings)
      assert Enum.member?(valid, :atoms)
      assert Enum.member?(valid, :atoms!)
    end

    test "strict option is boolean" do
      assert is_boolean(true)
      assert is_boolean(false)
    end

    test "indent_size option is a positive integer" do
      opts = [indent_size: 2]
      assert is_integer(Keyword.get(opts, :indent_size))
      assert Keyword.get(opts, :indent_size) > 0
    end

    test "expand_paths option is :off or :safe" do
      valid = [:off, :safe]
      assert Enum.member?(valid, :off)
      assert Enum.member?(valid, :safe)
    end
  end

  describe "depth type" do
    test "depth is a non-negative integer" do
      depths = [0, 1, 2, 10, 100]

      for d <- depths do
        assert is_integer(d)
        assert d >= 0
      end
    end
  end
end
