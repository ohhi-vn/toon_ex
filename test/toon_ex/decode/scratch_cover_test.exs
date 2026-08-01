defmodule ToonEx.Decode.ScratchCoverTest do
  use ExUnit.Case, async: false

  alias ToonEx.Decode
  alias ToonEx.Decode.StructuralParser
  alias ToonEx.Decode.StructuralParserV2

  @opts %{strict: true, indent_size: 2, keys: :strings}
  @ns %{strict: false, indent_size: 2, keys: :strings}

  describe "Decode public API target lines" do
    test "invalid options" do
      assert {:error, %ToonEx.DecodeError{reason: %{key: :bad_opt}}} =
               Decode.decode("a: 1", bad_opt: true)
    end

    test "non-DecodeError rescue from atoms! key" do
      assert {:error, %ToonEx.DecodeError{}} = Decode.decode("1a: b", keys: :atoms!)
    end
  end

  describe "V1 target lines" do
    test "single-line tabular header routes to object error" do
      assert {:error, _} = StructuralParser.parse("items[2]{a,b}:", @opts)
    end

    test "root primitive comma invalid" do
      assert {:error, _} = StructuralParser.parse("a,b", @opts)
    end

    test "root primitive digit-then-letter" do
      assert {:ok, {result, _}} = StructuralParser.parse("12x", @opts)
      assert result == "12x"
    end

    test "root primitive frac exp variants" do
      assert {:ok, {_, _}} = StructuralParser.parse("1.2e3", @opts)
      assert {:ok, {_, _}} = StructuralParser.parse("1.2e+3", @opts)
      assert {:ok, {"1.2e", _}} = StructuralParser.parse("1.2e", @opts)
      assert {:ok, {"1.2e3x", _}} = StructuralParser.parse("1.2e3x", @opts)
      assert {:ok, {"1.2x", _}} = StructuralParser.parse("1.2x", @opts)
    end

    test "root array bad headers" do
      assert {:error, _} = StructuralParser.parse("[]", @opts)
      assert {:ok, {["a", "b"], _}} = StructuralParser.parse("[]: a,b", @opts)
    end

    test "inline array empty with nested" do
      assert {:ok, {result, _}} =
               StructuralParser.parse("\"a b\"[0]:\n    y: 1", %{@ns | keys: :strings})
    end

    test "over-indented after inline array strict" do
      assert {:error, _} = StructuralParser.parse("items[1]: a\n    x: 1", @opts)
    end

    test "over-indented after inline array non-strict" do
      assert {:ok, {result, _}} = StructuralParser.parse("items[1]: a\n    x: 1", @ns)
    end

    test "list item nested key with more fields" do
      toon = "items[1]:\n  - args:\n      device_id: val\n    extra: 1"
      assert {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == %{"items" => [%{"args" => %{"device_id" => "val"}, "extra" => 1}]}
    end

    test "list item nested key atoms keys" do
      toon = "items[1]:\n  - args:\n      device_id: val"
      assert {:ok, {result, _}} =
               StructuralParser.parse(toon, %{@opts | keys: :atoms})
    end

    test "list item nested key atoms! keys" do
      toon = "items[1]:\n  - args:\n      device_id: val"
      assert {:ok, {result, _}} =
               StructuralParser.parse(toon, %{@opts | keys: :atoms!})
    end

    test "nested value via map placeholder" do
      assert {:ok, {result, _}} = StructuralParser.parse("a: \n  b: 1", @opts)
      assert result == %{"a" => %{"b" => 1}}
    end

    test "primitive followed by nested non-strict" do
      assert {:ok, {result, _}} = StructuralParser.parse("a: hi\n  b: 1", @ns)
      assert result == %{"a" => %{"b" => 1}}
    end

    test "tabular row indent jump strict" do
      assert {:error, _} = StructuralParser.parse("users[2]{name,age}:\n    A,30\n    B,25", @opts)
    end

    test "tabular over-indented row strict" do
      assert {:error, _} = StructuralParser.parse("users[2]{name,age}:\n  A,30\n    B,25", @opts)
    end

    test "tabular strict success with blank filtered" do
      assert {:ok, {result, _}} =
               StructuralParser.parse("users[1]{name,age}:\n  A,30", @opts)
      assert result == %{"users" => [%{"name" => "A", "age" => 30}]}
    end

    test "tabular non-strict path" do
      assert {:ok, {result, _}} =
               StructuralParser.parse("users[2]{name,age}:\n  A,30\n  B,25", @ns)
      assert result == %{"users" => [%{"name" => "A", "age" => 30}, %{"name" => "B", "age" => 25}]}
    end

    test "blank row inside tabular strict" do
      assert {:error, _} = StructuralParser.parse("users[3]{name,age}:\n  A,30\n\n  B,25", @opts)
    end

    test "blank row inside tabular non-strict" do
      assert {:ok, {_, _}} =
               StructuralParser.parse("users[3]{name,age}:\n  A,30\n\n  B,25", @ns)
    end

    test "row value count mismatch" do
      assert {:error, _} = StructuralParser.parse("users[1]{name,age}:\n  A", @opts)
    end

    test "list array length mismatch nested" do
      assert {:error, _} = StructuralParser.parse("items[3]:\n  - a\n  - b", @opts)
    end

    test "inconsistent list item indent strict" do
      toon = "items[2]:\n  - a\n    - b"
      assert {:error, _} = StructuralParser.parse(toon, @opts)
    end

    test "non-list marker line inside list array" do
      toon = "items[2]:\n  - a\n  junk\n  - b"
      assert {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
    end

    test "list item with array then following field (tabular)" do
      toon = "items[1]:\n  - data[1]{a,b}:\n      1,2\n    next: x"
      assert {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == %{"items" => [%{"data" => [%{"a" => 1, "b" => 2}], "next" => "x"}]}
    end

    test "list item with list array then following field" do
      toon = "items[1]:\n  - data[2]:\n      - 1\n      - 2\n    next: x"
      assert {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
    end

    test "list item bad tabular header" do
      toon = "items[1]:\n  - data[1]{a,b"
      assert {:ok, {_, _}} = StructuralParser.parse(toon, @opts)
    end

    test "list item bad list header" do
      toon = "items[1]:\n  - data[2"
      assert {:ok, {_, _}} = StructuralParser.parse(toon, @opts)
    end

    test "nested list array within list item" do
      toon = "items[1]:\n  - data[2]:\n      - 1\n      - 2"
      assert {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == %{"items" => [%{"data" => [1, 2]}]}
    end

    test "root list array with no nested items (empty)" do
      assert {:error, _} = StructuralParser.parse("[1]:", @opts)
    end

    test "list item simple value parse_error strip comma" do
      toon = "items[1]:\n  - value,"
      assert {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == %{"items" => ["value"]}
    end

    test "unterminated escape / lone backslash" do
      assert {:error, _} = StructuralParser.parse("a: \"bad\\x\"", @opts)
      assert {:error, _} = StructuralParser.parse("a: \"x\\", @opts)
    end

    test "root primitive quote-unrelated fallback string unquoted" do
      assert {:ok, {"plain", _}} = StructuralParser.parse("plain", @opts)
    end
  end

  describe "V2 target lines" do
    test "v2 non-binary input rescue" do
      assert {:error, _} = StructuralParserV2.parse("a: 1", %{})
    end

    test "v2 single-line tabular header" do
      assert {:error, _} = StructuralParserV2.parse("items[2]{a,b}:", @opts)
    end

    test "v2 root primitive comma" do
      assert {:error, _} = StructuralParserV2.parse("a,b", @opts)
    end

    test "v2 root primitive number variants" do
      assert {:ok, {_, _}} = StructuralParserV2.parse("1.2e3", @opts)
      assert {:ok, {_, _}} = StructuralParserV2.parse("1.2e+3", @opts)
      assert {:ok, {"1.2e", _}} = StructuralParserV2.parse("1.2e", @opts)
      assert {:ok, {"1.2e3x", _}} = StructuralParserV2.parse("1.2e3x", @opts)
      assert {:ok, {"1.2x", _}} = StructuralParserV2.parse("1.2x", @opts)
      assert {:ok, {"1.2ex", _}} = StructuralParserV2.parse("1.2ex", @opts)
      assert {:ok, {"-", _}} = StructuralParserV2.parse("-", @opts)
      assert {:ok, {"12x", _}} = StructuralParserV2.parse("12x", @opts)
    end

    test "v2 root tabular pipe fields" do
      assert {:ok, {result, _}} =
               StructuralParserV2.parse("[2|]{name|age}:\n  A|30\n  B|25", @opts)
      assert result == [%{"name" => "A", "age" => 30}, %{"name" => "B", "age" => 25}]
    end

    test "v2 root tabular row mismatch" do
      assert {:error, _} = StructuralParserV2.parse("[2]{a,b}:\n  1,2\n  3,4\n  5,6", @opts)
    end

    test "v2 root list length mismatch" do
      assert {:error, _} = StructuralParserV2.parse("[3]:\n  - a\n  - b", @opts)
    end

    test "v2 bad root inline array header" do
      assert {:error, _} = StructuralParserV2.parse("[a]]: x", @opts)
    end

    test "v2 over-indented after inline array non-strict" do
      assert {:ok, {_, _}} = StructuralParserV2.parse("items[1]: a\n    x: 1", @ns)
    end

    test "v2 nested value via map placeholder" do
      assert {:ok, {result, _}} = StructuralParserV2.parse("a: \n  b: 1", @opts)
      assert result == %{"a" => %{"b" => 1}}
    end

    test "v2 list item nested key with more fields" do
      toon = "items[1]:\n  - args:\n      device_id: val\n    extra: 1"
      assert {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == %{"items" => [%{"args" => %{"device_id" => "val"}}]}
    end

    test "v2 list item with array then following field (tabular)" do
      toon = "items[1]:\n  - data[1]{a,b}:\n      1,2\n    next: x"
      assert {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == %{"items" => [%{"data" => [%{"a" => 1, "b" => 2}]}]}
    end

    test "v2 list item with list array then following field" do
      toon = "items[1]:\n  - data[2]:\n      - 1\n      - 2\n    next: x"
      assert {:ok, {_, _}} = StructuralParserV2.parse(toon, @opts)
    end

    test "v2 nested list array within list item" do
      toon = "items[1]:\n  - data[2]:\n      - 1\n      - 2"
      assert {:ok, {_, _}} = StructuralParserV2.parse(toon, @opts)
    end

    test "v2 list item bad headers" do
      assert {:ok, {_, _}} = StructuralParserV2.parse("items[1]:\n  - data[1]{a,b", @opts)
      assert {:ok, {_, _}} = StructuralParserV2.parse("items[1]:\n  - data[2", @opts)
    end

    test "v2 list item simple value strip comma" do
      toon = "items[1]:\n  - value,"
      assert {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == %{"items" => ["value"]}
    end

    test "v2 unterminated quoted key and escape errors" do
      assert {:error, _} = StructuralParserV2.parse("\"abc: 1", @opts)
      assert {:error, _} = StructuralParserV2.parse("a: \"bad\\x\"", @opts)
      assert {:error, _} = StructuralParserV2.parse("a: \"x\\", @opts)
    end

    test "v2 lone backslash at end unescape" do
      assert {:error, _} = StructuralParserV2.parse("a: \"ab\\", @opts)
    end

    test "v2 keys as atoms list-item nested key" do
      toon = "items[1]:\n  - args:\n      device_id: val"
      assert {:ok, {_, _}} = StructuralParserV2.parse(toon, %{@opts | keys: :atoms})
    end

    test "v2 inline array item in list" do
      toon = "items[2]:\n  - [2]: a,b\n  - [2]: c,d"
      assert {:ok, {_, _}} = StructuralParserV2.parse(toon, @opts)
    end

    test "v2 list array header only empty" do
      toon = "items[1]:\n  - [1]:"
      assert {:ok, {_, _}} = StructuralParserV2.parse(toon, @opts)
    end
  end
end
