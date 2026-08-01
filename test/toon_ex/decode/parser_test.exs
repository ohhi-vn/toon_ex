defmodule ToonEx.Decode.ParserTest do
  use ExUnit.Case, async: true

  alias ToonEx.Decode.Parser

  describe "ToonEx.Decode.Parser.parse_number/1" do
    test "parses integer" do
      assert Parser.parse_number("42") == 42
      assert Parser.parse_number("-42") == -42
      assert Parser.parse_number("0") == 0
    end

    test "parses float" do
      assert Parser.parse_number("3.14") == 3.14
      assert Parser.parse_number("-3.14") == -3.14
      assert Parser.parse_number("0.5") == 0.5
    end

    test "parses scientific notation lowercase e" do
      assert Parser.parse_number("1e6") == 1_000_000.0
      assert Parser.parse_number("1e-6") == 1.0e-6
      assert Parser.parse_number("2.5e3") == 2500.0
    end

    test "parses scientific notation uppercase E" do
      assert Parser.parse_number("1E6") == 1_000_000.0
      assert Parser.parse_number("1E+03") == 1000.0
      assert Parser.parse_number("2.5E-2") == 0.025
    end

    test "returns string for invalid float" do
      result = Parser.parse_number("not_a_number")
      assert is_binary(result)
    end

    test "returns integer when float is whole number" do
      assert Parser.parse_number("1e3") == 1000
      assert is_integer(Parser.parse_number("1e3"))
    end
  end

  describe "ToonEx.Decode.Parser.make_kv/1" do
    test "creates key-value tuple from parsed result" do
      result = Parser.make_kv([{:key, "name"}, {:string, "Alice"}])
      assert result == {"name", "Alice"}
    end

    test "handles different value types" do
      assert Parser.make_kv([{:key, "age"}, {:number, 30}]) == {"age", 30}
      assert Parser.make_kv([{:key, "active"}, {:bool, true}]) == {"active", true}
      assert Parser.make_kv([{:key, "empty"}, {:null, nil}]) == {"empty", nil}
    end
  end

  describe "ToonEx.Decode.Parser.make_empty_kv/1" do
    test "creates key with empty map" do
      result = Parser.make_empty_kv([{:key, "nested"}])
      assert result == {"nested", %{}}
    end
  end

  describe "ToonEx.Decode.Parser.make_empty_array_kv/1" do
    test "creates key with empty array" do
      result = Parser.make_empty_array_kv([{:key, "items"}, {:array_length, 3}])
      assert result == {"items", []}
    end
  end

  describe "ToonEx.Decode.Parser.make_array_kv/1" do
    test "creates key with array values" do
      values = [{:string, "a"}, {:string, "b"}, {:string, "c"}]
      result = Parser.make_array_kv([{:key, "tags"}, {:array_length, 3}, {:inline_array, values}])
      assert result == {"tags", ["a", "b", "c"]}
    end

    test "handles empty array" do
      result = Parser.make_array_kv([{:key, "empty"}, {:array_length, 0}, {:inline_array, []}])
      assert result == {"empty", []}
    end
  end

  describe "ToonEx.Decode.Parser.parse_line/1 (public API via defparsec)" do
    test "parses simple key-value" do
      {:ok, result, _rest, _context, _line, _col} = Parser.parse_line("name: Alice")
      assert result == [{"name", "Alice"}]
    end

    test "parses key with number value" do
      {:ok, result, _rest, _context, _line, _col} = Parser.parse_line("age: 30")
      assert result == [{"age", 30}]
    end

    test "parses key with boolean value" do
      {:ok, result, _rest, _context, _line, _col} = Parser.parse_line("active: true")
      assert result == [{"active", true}]

      {:ok, result, _rest, _context, _line, _col} = Parser.parse_line("active: false")
      assert result == [{"active", false}]
    end

    test "parses key with null value" do
      {:ok, result, _rest, _context, _line, _col} = Parser.parse_line("data: null")
      assert result == [{"data", nil}]
    end

    test "parses quoted key" do
      {:ok, result, _rest, _context, _line, _col} = Parser.parse_line(~s("full name": Alice))
      assert result == [{"full name", "Alice"}]
    end

    test "parses quoted value" do
      {:ok, result, _rest, _context, _line, _col} = Parser.parse_line(~s(name: "Alice"))
      assert result == [{"name", "Alice"}]
    end

    test "parses inline array" do
      {:ok, result, _rest, _context, _line, _col} = Parser.parse_line("tags[3]: a,b,c")
      assert result == [{"tags", ["a", "b", "c"]}]
    end

    test "parses empty inline array" do
      {:ok, result, _rest, _context, _line, _col} = Parser.parse_line("tags[0]:")
      assert result == [{"tags", []}]
    end
  end
end