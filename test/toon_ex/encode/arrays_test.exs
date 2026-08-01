defmodule ToonEx.Encode.ArraysTest do
  use ExUnit.Case, async: true

  alias ToonEx.Encode.Arrays

  describe "encode_empty/2" do
    test "encodes empty array with default length_marker" do
      result = Arrays.encode_empty("items")
      assert IO.iodata_to_binary(result) == "items[0]:"
    end

    test "encodes empty array with nil length_marker" do
      result = Arrays.encode_empty("items", nil)
      assert IO.iodata_to_binary(result) == "items[0]:"
    end

    test "encodes empty array with custom length_marker" do
      result = Arrays.encode_empty("items", "#")
      assert IO.iodata_to_binary(result) == "items[#0]:"
    end
  end

  describe "encode_tabular/4 with key_order" do
    test "uses key_order when it matches all keys" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent_string: "  ",
        key_order: ["name", "age"]
      }

      users = [%{"name" => "Alice", "age" => 30}, %{"name" => "Bob", "age" => 25}]

      [header | rows] = Arrays.encode_tabular("users", users, 0, opts)

      assert IO.iodata_to_binary(header) == "users[2]{name,age}:"
      assert Enum.map(rows, &IO.iodata_to_binary/1) == ["Alice,30", "Bob,25"]
    end

    test "falls back to sorted keys when key_order is partial" do
      # key_order doesn't include all keys, so it falls back to alphabetical sort
      opts = %{delimiter: ",", length_marker: nil, indent_string: "  ", key_order: ["name"]}
      users = [%{"name" => "Alice", "age" => 30}]

      [header | _rows] = Arrays.encode_tabular("users", users, 0, opts)

      # Falls back to alphabetical: age, name
      assert IO.iodata_to_binary(header) == "users[1]{age,name}:"
    end

    test "handles empty key_order list" do
      opts = %{delimiter: ",", length_marker: nil, indent_string: "  ", key_order: []}
      users = [%{"name" => "Alice", "age" => 30}]

      [header | _rows] = Arrays.encode_tabular("users", users, 0, opts)

      # Falls back to alphabetical: age, name
      assert IO.iodata_to_binary(header) == "users[1]{age,name}:"
    end

    test "handles empty list input" do
      opts = %{delimiter: ",", length_marker: nil, indent_string: "  ", key_order: nil}

      [header] = Arrays.encode_tabular("users", [], 0, opts)

      assert IO.iodata_to_binary(header) == "users[0]{}:"
    end
  end

  describe "encode_list/4 edge cases" do
    test "encodes list with empty object" do
      opts = %{delimiter: ",", length_marker: nil, indent_string: "  ", key_order: nil}
      items = [%{}]

      [header | item_lines] = Arrays.encode_list("items", items, 0, opts)

      assert IO.iodata_to_binary(header) == "items[1]:"
      assert Enum.map(item_lines, &IO.iodata_to_binary/1) == ["-"]
    end

    test "encodes list with nested empty array" do
      opts = %{delimiter: ",", length_marker: nil, indent_string: "  ", key_order: nil}
      items = [[]]

      [header | item_lines] = Arrays.encode_list("items", items, 0, opts)

      assert IO.iodata_to_binary(header) == "items[1]:"
      assert Enum.map(item_lines, &IO.iodata_to_binary/1) == ["- [0]:"]
    end

    test "encodes list with nested primitive array" do
      opts = %{delimiter: ",", length_marker: nil, indent_string: "  ", key_order: nil}
      items = [[1, 2, 3]]

      [header | item_lines] = Arrays.encode_list("items", items, 0, opts)

      assert IO.iodata_to_binary(header) == "items[1]:"
      assert Enum.map(item_lines, &IO.iodata_to_binary/1) == ["- [3]: 1,2,3"]
    end

    test "encodes list with nested map" do
      opts = %{delimiter: ",", length_marker: nil, indent_string: "  ", key_order: nil}
      items = [%{"a" => 1}]

      [header | item_lines] = Arrays.encode_list("items", items, 0, opts)

      assert IO.iodata_to_binary(header) == "items[1]:"
      assert Enum.map(item_lines, &IO.iodata_to_binary/1) == ["- a: 1"]
    end

    test "encodes list with nested tabular array" do
      opts = %{delimiter: ",", length_marker: nil, indent_string: "  ", key_order: nil}
      items = [%{"a" => 1, "b" => 2}]

      [header | item_lines] = Arrays.encode_list("items", items, 0, opts)

      assert IO.iodata_to_binary(header) == "items[1]:"
      assert Enum.map(item_lines, &IO.iodata_to_binary/1) == ["- a: 1", "  b: 2"]
    end

    test "encodes list with nested list array" do
      opts = %{delimiter: ",", length_marker: nil, indent_string: "  ", key_order: nil}
      items = [%{"nested" => [1, 2]}]

      [header | item_lines] = Arrays.encode_list("items", items, 0, opts)

      assert IO.iodata_to_binary(header) == "items[1]:"
      assert Enum.at(item_lines, 0) |> IO.iodata_to_binary() =~ "nested"
    end

    test "encodes list with deeply nested structure" do
      opts = %{delimiter: ",", length_marker: nil, indent: 2, indent_string: "  ", key_order: nil}
      items = [%{"a" => %{"b" => %{"c" => "deep"}}}]

      [header | item_lines] = Arrays.encode_list("items", items, 0, opts)

      assert IO.iodata_to_binary(header) == "items[1]:"
      assert Enum.at(item_lines, 0) |> IO.iodata_to_binary() =~ "a:"
    end

    test "encodes list with empty map items" do
      opts = %{delimiter: ",", length_marker: nil, indent: 2, indent_string: "  ", key_order: nil}
      items = [%{}]

      [header | _item_lines] = Arrays.encode_list("items", items, 0, opts)

      assert IO.iodata_to_binary(header) == "items[1]:"
    end

    test "encodes list with null values in items" do
      opts = %{delimiter: ",", length_marker: nil, indent: 2, indent_string: "  ", key_order: nil}
      items = [%{"name" => nil}]

      [header | item_lines] = Arrays.encode_list("items", items, 0, opts)

      assert IO.iodata_to_binary(header) == "items[1]:"
      assert Enum.at(item_lines, 0) |> IO.iodata_to_binary() =~ "name: null"
    end

    test "encodes list with boolean values in items" do
      opts = %{delimiter: ",", length_marker: nil, indent: 2, indent_string: "  ", key_order: nil}
      items = [%{"active" => true, "deleted" => false}]

      [header | item_lines] = Arrays.encode_list("items", items, 0, opts)

      assert IO.iodata_to_binary(header) == "items[1]:"
      assert Enum.at(item_lines, 0) |> IO.iodata_to_binary() =~ "active: true"
    end

    test "encodes list with numeric values in items" do
      opts = %{delimiter: ",", length_marker: nil, indent: 2, indent_string: "  ", key_order: nil}
      items = [%{"count" => 42, "price" => 3.14}]

      [header | item_lines] = Arrays.encode_list("items", items, 0, opts)

      assert IO.iodata_to_binary(header) == "items[1]:"
      assert Enum.at(item_lines, 0) |> IO.iodata_to_binary() =~ "count: 42"
    end
  end
end
