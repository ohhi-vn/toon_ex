defmodule ToonEx.Encode.ObjectsTest do
  use ExUnit.Case, async: true

  alias ToonEx.Encode.Objects

  describe "encode/3 with key_order" do
    test "uses path-specific key_order from map" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent: 2,
        indent_string: "  ",
        key_order: %{[] => ["name", "age"]},
        key_folding: :off
      }

      data = %{"age" => 30, "name" => "Alice"}
      result = Objects.encode(data, 0, opts) |> IO.iodata_to_binary()

      # Should use the specified order: name first, then age
      assert result == "name: Alice\nage: 30"
    end

    test "falls back to alphabetical when path not in key_order map" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent: 2,
        indent_string: "  ",
        key_order: %{["nested"] => ["x", "y"]},
        key_folding: :off
      }

      data = %{"age" => 30, "name" => "Alice"}
      result = Objects.encode(data, 0, opts) |> IO.iodata_to_binary()

      # Should use alphabetical order since [] path is not in key_order
      assert result == "age: 30\nname: Alice"
    end

    test "uses list key_order at root level" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent: 2,
        indent_string: "  ",
        key_order: ["name", "age"],
        key_folding: :off
      }

      data = %{"age" => 30, "name" => "Alice"}
      result = Objects.encode(data, 0, opts) |> IO.iodata_to_binary()

      assert result == "name: Alice\nage: 30"
    end

    test "falls back to alphabetical when list key_order is partial" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent: 2,
        indent_string: "  ",
        key_order: ["name"],
        key_folding: :off
      }

      data = %{"age" => 30, "name" => "Alice"}
      result = Objects.encode(data, 0, opts) |> IO.iodata_to_binary()

      # Falls back to alphabetical since key_order doesn't include all keys
      assert result == "age: 30\nname: Alice"
    end

    test "falls back to alphabetical when key_order is empty list" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent: 2,
        indent_string: "  ",
        key_order: [],
        key_folding: :off
      }

      data = %{"age" => 30, "name" => "Alice"}
      result = Objects.encode(data, 0, opts) |> IO.iodata_to_binary()

      assert result == "age: 30\nname: Alice"
    end

    test "falls back to alphabetical when key_order is nil" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent: 2,
        indent_string: "  ",
        key_order: nil,
        key_folding: :off
      }

      data = %{"age" => 30, "name" => "Alice"}
      result = Objects.encode(data, 0, opts) |> IO.iodata_to_binary()

      assert result == "age: 30\nname: Alice"
    end

    test "uses nested path key_order for nested objects" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent: 2,
        indent_string: "  ",
        key_order: %{["user"] => ["first", "last"]},
        key_folding: :off
      }

      data = %{"user" => %{"last" => "Smith", "first" => "John"}}
      result = Objects.encode(data, 0, opts) |> IO.iodata_to_binary()

      # Nested "user" object should use specified order: first, last
      assert result =~ "first: John"
      assert result =~ "last: Smith"
      # Verify "first" appears before "last" in the output
      first_pos = :binary.match(result, "first")
      last_pos = :binary.match(result, "last")
      assert elem(first_pos, 0) < elem(last_pos, 0)
    end
  end

  describe "encode_to_lines/3" do
    test "encodes map to lines with proper indentation" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent: 2,
        indent_string: "  ",
        key_order: nil,
        key_folding: :off
      }

      data = %{"a" => 1, "b" => 2}
      result = Objects.encode_to_lines(data, 0, opts) |> IO.iodata_to_binary()
      assert result =~ "a: 1"
      assert result =~ "b: 2"
    end

    test "encodes nested map with indentation" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent: 2,
        indent_string: "  ",
        key_order: nil,
        key_folding: :off
      }

      data = %{"outer" => %{"inner" => "value"}}
      result = Objects.encode_to_lines(data, 0, opts) |> IO.iodata_to_binary()
      assert result =~ "outer:"
      assert result =~ "inner: value"
    end

    test "encodes map with array value" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent: 2,
        indent_string: "  ",
        key_order: nil,
        key_folding: :off
      }

      data = %{"items" => [1, 2, 3]}
      result = Objects.encode_to_lines(data, 0, opts) |> IO.iodata_to_binary()
      assert result =~ "items"
    end

    test "encodes map with empty map value" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent: 2,
        indent_string: "  ",
        key_order: nil,
        key_folding: :off
      }

      data = %{"empty" => %{}}
      result = Objects.encode_to_lines(data, 0, opts) |> IO.iodata_to_binary()
      assert result =~ "empty:"
    end

    test "encodes map with nil value" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent: 2,
        indent_string: "  ",
        key_order: nil,
        key_folding: :off
      }

      data = %{"missing" => nil}
      result = Objects.encode_to_lines(data, 0, opts) |> IO.iodata_to_binary()
      assert result =~ "missing: null"
    end

    test "encodes map with boolean values" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent: 2,
        indent_string: "  ",
        key_order: nil,
        key_folding: :off
      }

      data = %{"active" => true, "deleted" => false}
      result = Objects.encode_to_lines(data, 0, opts) |> IO.iodata_to_binary()
      assert result =~ "active: true"
      assert result =~ "deleted: false"
    end

    test "encodes nested map with key_order as list at root" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent: 2,
        indent_string: "  ",
        key_order: ["z", "a", "m"],
        key_folding: :off
      }

      data = %{"a" => 1, "m" => 2, "z" => 3}
      result = Objects.encode_to_lines(data, 0, opts) |> IO.iodata_to_binary()
      assert result =~ "z: 3"
      assert result =~ "a: 1"
      assert result =~ "m: 2"
    end

    test "key_order list with partial match falls back to sort" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent: 2,
        indent_string: "  ",
        key_order: ["z"],
        key_folding: :off
      }

      data = %{"a" => 1, "m" => 2, "z" => 3}
      result = Objects.encode_to_lines(data, 0, opts) |> IO.iodata_to_binary()
      assert result =~ "a: 1"
      assert result =~ "m: 2"
      assert result =~ "z: 3"
    end

    test "encodes empty map as empty string" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent: 2,
        indent_string: "  ",
        key_order: nil,
        key_folding: :off
      }

      result = Objects.encode_to_lines(%{}, 0, opts) |> IO.iodata_to_binary()
      assert result == ""
    end

    test "encodes nested empty map" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent: 2,
        indent_string: "  ",
        key_order: nil,
        key_folding: :off
      }

      data = %{"outer" => %{}}
      result = Objects.encode_to_lines(data, 0, opts) |> IO.iodata_to_binary()
      assert result =~ "outer:"
    end

    test "encodes nested map with nested key_order" do
      opts = %{
        delimiter: ",",
        length_marker: nil,
        indent: 2,
        indent_string: "  ",
        key_order: %{[] => ["outer"], ["outer"] => ["y", "x"]},
        key_folding: :off
      }

      data = %{"outer" => %{"x" => 1, "y" => 2}}
      result = Objects.encode_to_lines(data, 0, opts) |> IO.iodata_to_binary()
      assert result =~ "outer:"
    end
  end
end
