defmodule ToonEx.Shared.UtilsTest do
  use ExUnit.Case, async: true

  alias ToonEx.Utils

  describe "primitive?/1" do
    test "returns true for nil" do
      assert Utils.primitive?(nil) == true
    end

    test "returns true for booleans" do
      assert Utils.primitive?(true) == true
      assert Utils.primitive?(false) == true
    end

    test "returns true for numbers" do
      assert Utils.primitive?(42) == true
      assert Utils.primitive?(-42) == true
      assert Utils.primitive?(3.14) == true
      assert Utils.primitive?(0) == true
    end

    test "returns true for binaries" do
      assert Utils.primitive?("hello") == true
      assert Utils.primitive?("") == true
    end

    test "returns false for maps" do
      assert Utils.primitive?(%{}) == false
      assert Utils.primitive?(%{"a" => 1}) == false
    end

    test "returns false for lists" do
      assert Utils.primitive?([]) == false
      assert Utils.primitive?([1, 2, 3]) == false
    end

    test "returns false for structs" do
      struct = %ToonEx.Fixtures.Person{name: "Alice", age: 30}
      assert Utils.primitive?(struct) == false
    end

    test "returns false for tuples" do
      assert Utils.primitive?({:ok, "value"}) == false
    end

    test "returns false for pids" do
      assert Utils.primitive?(self()) == false
    end

    test "returns false for references" do
      assert Utils.primitive?(make_ref()) == false
    end
  end

  describe "map?/1" do
    test "returns true for empty map" do
      assert Utils.map?(%{}) == true
    end

    test "returns true for non-empty map" do
      assert Utils.map?(%{"key" => "value"}) == true
    end

    test "returns false for lists" do
      assert Utils.map?([]) == false
      assert Utils.map?([1, 2, 3]) == false
    end

    test "returns false for binaries" do
      assert Utils.map?("string") == false
    end

    test "returns false for integers" do
      assert Utils.map?(42) == false
    end

    test "returns false for nil" do
      assert Utils.map?(nil) == false
    end

    test "returns true for structs (structs are maps)" do
      struct = %ToonEx.Fixtures.Person{name: "Alice", age: 30}
      assert Utils.map?(struct) == true
    end
  end

  describe "list?/1" do
    test "returns true for empty list" do
      assert Utils.list?([]) == true
    end

    test "returns true for non-empty list" do
      assert Utils.list?([1, 2, 3]) == true
    end

    test "returns false for maps" do
      assert Utils.list?(%{}) == false
      assert Utils.list?(%{"a" => 1}) == false
    end

    test "returns false for binaries" do
      assert Utils.list?("string") == false
    end

    test "returns false for integers" do
      assert Utils.list?(42) == false
    end

    test "returns false for nil" do
      assert Utils.list?(nil) == false
    end

    test "returns false for tuples" do
      assert Utils.list?({1, 2}) == false
    end
  end

  describe "all_primitives?/1" do
    test "returns true for empty list" do
      assert Utils.all_primitives?([]) == true
    end

    test "returns true for list of integers" do
      assert Utils.all_primitives?([1, 2, 3]) == true
    end

    test "returns true for list of strings" do
      assert Utils.all_primitives?(["a", "b", "c"]) == true
    end

    test "returns true for mixed primitives" do
      assert Utils.all_primitives?([1, "hello", true, nil, 3.14]) == true
    end

    test "returns false for list containing map" do
      assert Utils.all_primitives?([1, %{}]) == false
    end

    test "returns false for list containing list" do
      assert Utils.all_primitives?([1, [2, 3]]) == false
    end

    test "returns false for list containing struct" do
      struct = %ToonEx.Fixtures.Person{name: "Alice", age: 30}
      assert Utils.all_primitives?([1, struct]) == false
    end
  end

  describe "normalize/1" do
    test "returns nil as is" do
      assert Utils.normalize(nil) == nil
    end

    test "returns booleans as is" do
      assert Utils.normalize(true) == true
      assert Utils.normalize(false) == false
    end

    test "returns numbers as is" do
      assert Utils.normalize(42) == 42
      assert Utils.normalize(-42) == -42
      assert Utils.normalize(3.14) == 3.14
    end

    test "returns zero as zero" do
      assert Utils.normalize(0) == 0
    end

    test "returns non-finite atoms as strings" do
      assert Utils.normalize(:infinity) == "infinity"
    end

    test "converts atom to string" do
      assert Utils.normalize(:hello) == "hello"
      assert Utils.normalize(:"user name") == "user name"
    end

    test "converts atom-like atoms to string" do
      assert Utils.normalize(:infinity) == "infinity"
      assert Utils.normalize(:neg_infinity) == "neg_infinity"
    end

    test "converts map with atom keys to string keys" do
      input = %{name: "Alice", age: 30}
      expected = %{"name" => "Alice", "age" => 30}
      assert Utils.normalize(input) == expected
    end

    test "returns map with string keys as is" do
      input = %{"name" => "Alice", "age" => 30}
      assert Utils.normalize(input) == input
    end

    test "converts nested maps with atom keys" do
      input = %{user: %{name: "Alice", age: 30}}
      expected = %{"user" => %{"name" => "Alice", "age" => 30}}
      assert Utils.normalize(input) == expected
    end

    test "converts list with nested atom-key maps" do
      input = [%{name: "Alice"}, %{name: "Bob"}]
      expected = [%{"name" => "Alice"}, %{"name" => "Bob"}]
      assert Utils.normalize(input) == expected
    end

    test "converts list of primitives" do
      input = [1, "hello", true, nil]
      assert Utils.normalize(input) == input
    end

    test "converts list containing map" do
      input = [%{name: "Alice"}, "hello"]
      expected = [%{"name" => "Alice"}, "hello"]
      assert Utils.normalize(input) == expected
    end

    test "converts struct via Encoder protocol" do
      struct = %ToonEx.Fixtures.CustomDate{year: 2024, month: 1, day: 15}
      result = Utils.normalize(struct)
      assert result == "2024-01-15"
    end

    test "converts list of structs" do
      structs = [
        %ToonEx.Fixtures.CustomDate{year: 2024, month: 1, day: 15},
        %ToonEx.Fixtures.CustomDate{year: 2024, month: 2, day: 1}
      ]

      result = Utils.normalize(structs)
      assert result == ["2024-01-15", "2024-02-01"]
    end

    test "handles unsupported types by returning nil" do
      assert Utils.normalize({:ok, "value"}) == nil
      assert Utils.normalize(self()) == nil
      assert Utils.normalize(make_ref()) == nil
    end

    test "list of tuples becomes list of nils (tuples unsupported)" do
      input = [{:name, "Alice"}, {:age, 30}]
      result = Utils.normalize(input)
      assert result == [nil, nil]
    end

    test "keyword list becomes list of nils (tuples unsupported)" do
      input = [name: "Alice", age: 30]
      result = Utils.normalize(input)
      assert result == [nil, nil]
    end

    test "tuple list with atom keys becomes list of nils" do
      input = [{:name, "Alice"}, {:age, 30}]
      result = Utils.normalize(input)
      assert result == [nil, nil]
    end
  end

  describe "all_maps?/1" do
    test "returns true for empty list" do
      assert Utils.all_maps?([]) == true
    end

    test "returns true for list of empty maps" do
      assert Utils.all_maps?([%{}, %{}]) == true
    end

    test "returns true for list of non-empty maps" do
      assert Utils.all_maps?([%{"a" => 1}, %{"b" => 2}]) == true
    end

    test "returns false for list containing non-map" do
      assert Utils.all_maps?([%{}, 1]) == false
    end

    test "returns false for list containing list" do
      assert Utils.all_maps?([%{}, []]) == false
    end

    test "returns true for list containing struct (structs are maps)" do
      struct = %ToonEx.Fixtures.Person{name: "Alice", age: 30}
      assert Utils.all_maps?([%{}, struct]) == true
    end
  end

  describe "same_keys?/1" do
    test "returns true for empty list" do
      assert Utils.same_keys?([]) == true
    end

    test "returns false for list of empty maps" do
      assert Utils.same_keys?([%{}, %{}]) == false
    end

    test "returns true for maps with same single key" do
      assert Utils.same_keys?([%{"a" => 1}, %{"a" => 2}]) == true
    end

    test "returns true for maps with same multiple keys" do
      assert Utils.same_keys?([%{"a" => 1, "b" => 2}, %{"a" => 3, "b" => 4}]) == true
    end

    test "returns false for maps with different keys" do
      assert Utils.same_keys?([%{"a" => 1}, %{"b" => 2}]) == false
    end

    test "returns false for maps with different number of keys" do
      assert Utils.same_keys?([%{"a" => 1}, %{"a" => 1, "b" => 2}]) == false
    end

    test "returns false for non-map in list" do
      assert Utils.same_keys?([%{"a" => 1}, 1]) == false
    end
  end

  describe "all_primitive_values?/1" do
    test "returns true for empty list" do
      assert Utils.all_primitive_values?([]) == true
    end

    test "returns true for list of maps with primitive values" do
      assert Utils.all_primitive_values?([%{"a" => 1}, %{"a" => 2}]) == true
    end

    test "returns true for list of maps with mixed primitive values" do
      assert Utils.all_primitive_values?([%{"a" => 1, "b" => "x"}, %{"a" => 2, "b" => "y"}]) ==
               true
    end

    test "returns false for list containing map with nested map" do
      assert Utils.all_primitive_values?([%{"a" => %{"nested" => 1}}]) == false
    end

    test "returns false for list containing map with list value" do
      assert Utils.all_primitive_values?([%{"a" => [1, 2]}]) == false
    end

    test "returns false for list containing non-map" do
      assert Utils.all_primitive_values?([1, %{"a" => 1}]) == false
    end
  end

  describe "repeat/2" do
    test "returns empty string for zero times" do
      assert Utils.repeat("  ", 0) == ""
    end

    test "returns string once for times = 1" do
      assert Utils.repeat("  ", 1) == "  "
    end

    test "returns string repeated n times" do
      assert Utils.repeat("  ", 3) == "      "
    end

    test "works with different strings" do
      assert Utils.repeat("-", 5) == "-----"
    end
  end

  describe "map_values_primitive?/1" do
    test "returns true for map with primitive values" do
      assert Utils.map_values_primitive?(%{"a" => 1, "b" => "x"}) == true
    end

    test "returns true for map with boolean values" do
      assert Utils.map_values_primitive?(%{"a" => true, "b" => false}) == true
    end

    test "returns true for map with nil values" do
      assert Utils.map_values_primitive?(%{"a" => nil}) == true
    end

    test "returns true for map with float values" do
      assert Utils.map_values_primitive?(%{"a" => 3.14}) == true
    end

    test "returns true for empty map" do
      assert Utils.map_values_primitive?(%{}) == true
    end

    test "returns false for map with nested map value" do
      assert Utils.map_values_primitive?(%{"a" => %{"nested" => 1}}) == false
    end

    test "returns false for map with list value" do
      assert Utils.map_values_primitive?(%{"a" => [1, 2]}) == false
    end

    test "returns false for map with struct value" do
      struct = %ToonEx.Fixtures.Person{name: "Alice", age: 30}
      assert Utils.map_values_primitive?(%{"a" => struct}) == false
    end

    test "returns false for map with tuple value" do
      assert Utils.map_values_primitive?(%{"a" => {:ok, "value"}}) == false
    end

    test "returns false for map with mixed primitive and non-primitive values" do
      assert Utils.map_values_primitive?(%{"a" => 1, "b" => %{nested: 1}}) == false
    end
  end

  describe "detect_array_type/1" do
    test "returns {:primitive, count} for list of primitives" do
      assert Utils.detect_array_type([1, 2, 3]) == {:primitive, 3}
    end

    test "returns {:primitive, count} for list of mixed primitives" do
      assert Utils.detect_array_type([1, "hello", true, nil, 3.14]) == {:primitive, 5}
    end

    test "returns {:primitive, 0} for empty list" do
      assert Utils.detect_array_type([]) == {:primitive, 0}
    end

    test "returns {:tabular, count, keys} for list of maps with same keys" do
      assert Utils.detect_array_type([%{"a" => 1}, %{"a" => 2}]) == {:tabular, 2, ["a"]}
    end

    test "returns {:tabular, count, keys} for list of maps with same multiple keys" do
      result = Utils.detect_array_type([%{"a" => 1, "b" => 2}, %{"a" => 3, "b" => 4}])
      assert result == {:tabular, 2, ["a", "b"]}
    end

    test "returns {:list, count} for mixed primitives and maps" do
      assert Utils.detect_array_type([1, %{"a" => 1}]) == {:list, 2}
    end

    test "returns {:list, count} for maps with different keys" do
      assert Utils.detect_array_type([%{"a" => 1}, %{"b" => 2}]) == {:list, 2}
    end

    test "returns {:list, count} for maps with non-primitive values" do
      assert Utils.detect_array_type([%{"a" => %{"nested" => 1}}]) == {:list, 1}
    end

    test "returns {:list, count} for maps with list values" do
      assert Utils.detect_array_type([%{"a" => [1, 2]}]) == {:list, 1}
    end

    test "returns {:list, count} for list with non-map non-primitive first element" do
      assert Utils.detect_array_type([:atom, 1, 2]) == {:list, 3}
    end

    test "returns {:list, count} for list with tuple elements" do
      assert Utils.detect_array_type([{:a, 1}, {:b, 2}]) == {:list, 2}
    end

    test "returns {:list, count} for list with map followed by non-map" do
      assert Utils.detect_array_type([%{"a" => 1}, 1]) == {:list, 2}
    end

    test "returns {:list, count} for list with primitive followed by map with different keys" do
      result = Utils.detect_array_type([1, %{"a" => 1}, %{"b" => 2}])
      assert result == {:list, 3}
    end

    test "returns {:list, count} for list with map having nil values (primitive)" do
      assert Utils.detect_array_type([%{"a" => nil}, %{"a" => nil}]) == {:tabular, 2, ["a"]}
    end

    test "returns {:list, count} for list with struct elements" do
      struct = %ToonEx.Fixtures.Person{name: "Alice", age: 30}
      assert Utils.detect_array_type([struct]) == {:list, 1}
    end
  end

  describe "format_length_marker/2" do
    test "returns string representation of length when marker is nil" do
      assert Utils.format_length_marker(5, nil) == "5"
    end

    test "returns string for zero length with nil marker" do
      assert Utils.format_length_marker(0, nil) == "0"
    end

    test "returns iolist with marker prefix when marker is provided" do
      result = Utils.format_length_marker(5, "n")
      assert IO.iodata_to_binary(result) == "n5"
    end

    test "returns iolist with marker for zero length" do
      result = Utils.format_length_marker(0, "#")
      assert IO.iodata_to_binary(result) == "#0"
    end

    test "returns iolist with multi-character marker" do
      result = Utils.format_length_marker(10, "len=")
      assert IO.iodata_to_binary(result) == "len=10"
    end
  end

  describe "format_delimiter_marker/1" do
    test "returns empty string for comma delimiter" do
      assert Utils.format_delimiter_marker(",") == ""
    end

    test "returns the delimiter for tab" do
      assert Utils.format_delimiter_marker("\t") == "\t"
    end

    test "returns the delimiter for pipe" do
      assert Utils.format_delimiter_marker("|") == "|"
    end

    test "returns the delimiter for semicolon" do
      assert Utils.format_delimiter_marker(";") == ";"
    end
  end

  describe "same_keys?/1 edge cases" do
    test "returns false for non-list input (nil)" do
      assert Utils.same_keys?(nil) == false
    end

    test "returns false for non-list input (string)" do
      assert Utils.same_keys?("string") == false
    end

    test "returns false for non-list input (integer)" do
      assert Utils.same_keys?(42) == false
    end

    test "returns false for list with non-map first element" do
      assert Utils.same_keys?([1, 2, 3]) == false
    end

    test "returns false for list with empty map as first element" do
      assert Utils.same_keys?([%{}, %{"a" => 1}]) == false
    end

    test "returns false for list with empty map first and non-empty second" do
      assert Utils.same_keys?([%{}, %{"a" => 1}]) == false
    end

    test "returns true for single map with keys" do
      assert Utils.same_keys?([%{"a" => 1}]) == true
    end

    test "returns false for list with map followed by non-map" do
      assert Utils.same_keys?([%{"a" => 1}, 2, 3]) == false
    end
  end

  describe "all_primitive_values?/1 edge cases" do
    test "returns false for non-list input" do
      assert Utils.all_primitive_values?(nil) == false
      assert Utils.all_primitive_values?("string") == false
      assert Utils.all_primitive_values?(42) == false
    end

    test "returns false for list with non-map elements" do
      assert Utils.all_primitive_values?([1, %{"a" => 1}]) == false
      assert Utils.all_primitive_values?([%{"a" => 1}, "string"]) == false
    end

    test "returns true for list with maps containing nil values" do
      assert Utils.all_primitive_values?([%{"a" => nil}, %{"a" => nil}]) == true
    end

    test "returns true for list with maps containing boolean values" do
      assert Utils.all_primitive_values?([%{"a" => true}, %{"a" => false}]) == true
    end

    test "returns true for list with maps containing float values" do
      assert Utils.all_primitive_values?([%{"a" => 3.14}, %{"a" => 2.71}]) == true
    end

    test "returns false for list with maps containing struct values" do
      struct = %ToonEx.Fixtures.Person{name: "Alice", age: 30}
      assert Utils.all_primitive_values?([%{"a" => struct}]) == false
    end

    test "returns false for list with maps containing tuple values" do
      assert Utils.all_primitive_values?([%{"a" => {:ok, "value"}}]) == false
    end

    test "returns true for list with maps containing mixed primitive values" do
      assert Utils.all_primitive_values?([%{"a" => 1, "b" => "x", "c" => true, "d" => nil}]) == true
    end

    test "returns true for list with empty maps" do
      assert Utils.all_primitive_values?([%{}, %{}]) == true
    end
  end
end
