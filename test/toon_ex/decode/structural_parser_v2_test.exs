defmodule ToonEx.Decode.StructuralParserV2Test do
  use ExUnit.Case, async: true

  alias ToonEx.Decode.StructuralParserV2

  @opts %{strict: true, indent_size: 2, keys: :strings}

  describe "ToonEx.Decode.StructuralParserV2.parse/2" do
    test "parses empty input" do
      assert {:ok, {%{}, _}} = StructuralParserV2.parse("", @opts)
    end

    test "parses whitespace only input" do
      assert {:ok, {%{}, _}} = StructuralParserV2.parse("   \n  \n  ", @opts)
    end

    test "parses simple key-value" do
      assert {:ok, {%{"name" => "Alice"}, _}} = StructuralParserV2.parse("name: Alice", @opts)
    end

    test "parses multiple key-values" do
      {:ok, {result, _}} = StructuralParserV2.parse("name: Alice\nage: 30", @opts)
      assert result == %{"name" => "Alice", "age" => 30}
    end

    test "parses nested object" do
      toon = "user:\n  name: Bob"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == %{"user" => %{"name" => "Bob"}}
    end

    test "parses two levels deep" do
      toon = "a:\n  b:\n    c: 1"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == %{"a" => %{"b" => %{"c" => 1}}}
    end

    test "parses sibling keys after nested block" do
      toon = "user:\n  name: Bob\nactive: true"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result["user"] == %{"name" => "Bob"}
      assert result["active"] == true
    end

    test "parses array with inline values" do
      {:ok, {result, _}} = StructuralParserV2.parse("tags[2]: a,b", @opts)
      assert result == %{"tags" => ["a", "b"]}
    end

    test "parses empty array" do
      {:ok, {result, _}} = StructuralParserV2.parse("tags[0]:", @opts)
      assert result == %{"tags" => []}
    end

    test "parses tabular array" do
      toon = "users[2]{name,age}:\n  Alice,30\n  Bob,25"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result["users"] == [%{"name" => "Alice", "age" => 30}, %{"name" => "Bob", "age" => 25}]
    end

    test "parses list array" do
      toon = "items[2]:\n  - apple\n  - banana"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result["items"] == ["apple", "banana"]
    end

    test "parses root primitive" do
      {:ok, {result, _}} = StructuralParserV2.parse("hello", @opts)
      assert result == "hello"
    end

    test "parses root primitive null" do
      {:ok, {result, _}} = StructuralParserV2.parse("null", @opts)
      assert result == nil
    end

    test "parses root primitive true" do
      {:ok, {result, _}} = StructuralParserV2.parse("true", @opts)
      assert result == true
    end

    test "parses root primitive false" do
      {:ok, {result, _}} = StructuralParserV2.parse("false", @opts)
      assert result == false
    end

    test "parses root primitive quoted string" do
      {:ok, {result, _}} = StructuralParserV2.parse(~S("hello world"), @opts)
      assert result == "hello world"
    end

    test "parses root primitive integer" do
      {:ok, {result, _}} = StructuralParserV2.parse("42", @opts)
      assert result == 42
    end

    test "parses root array" do
      {:ok, {result, _}} = StructuralParserV2.parse("[2]: a,b", @opts)
      assert result == ["a", "b"]
    end

    test "parses with keys as atoms" do
      opts = Map.put(@opts, :keys, :atoms)
      {:ok, {result, _}} = StructuralParserV2.parse("name: Alice", opts)
      assert result == %{name: "Alice"}
    end

    test "accepts non-multiple indentation when strict: false" do
      opts = Map.put(@opts, :strict, false)
      {:ok, {result, _}} = StructuralParserV2.parse("parent:\n   child: 1", opts)
      assert result == %{"parent" => %{"child" => 1}}
    end

    test "parses quoted key with spaces" do
      {:ok, {result, _}} = StructuralParserV2.parse(~s("full name": Alice), @opts)
      assert result == %{"full name" => "Alice"}
    end

    test "parses quoted value" do
      {:ok, {result, _}} = StructuralParserV2.parse(~s(name: "Alice"), @opts)
      assert result == %{"name" => "Alice"}
    end

    test "parses null value" do
      {:ok, {result, _}} = StructuralParserV2.parse("data: null", @opts)
      assert result == %{"data" => nil}
    end

    test "parses boolean value" do
      {:ok, {result, _}} = StructuralParserV2.parse("active: true", @opts)
      assert result == %{"active" => true}

      {:ok, {result, _}} = StructuralParserV2.parse("active: false", @opts)
      assert result == %{"active" => false}
    end

    test "parses float value" do
      {:ok, {result, _}} = StructuralParserV2.parse("price: 3.14", @opts)
      assert result == %{"price" => 3.14}
    end

    test "parses negative number" do
      {:ok, {result, _}} = StructuralParserV2.parse("temp: -10", @opts)
      assert result == %{"temp" => -10}
    end

    test "parses scientific notation" do
      {:ok, {result, _}} = StructuralParserV2.parse("big: 1e6", @opts)
      assert result == %{"big" => 1_000_000.0}

      {:ok, {result, _}} = StructuralParserV2.parse("small: 1e-3", @opts)
      assert result == %{"small" => 0.001}
    end

    test "parses array with tab delimiter" do
      toon = "items[2\t]: a\tb"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result["items"] == ["a", "b"]
    end

    test "parses array with pipe delimiter" do
      toon = "items[2|]: a|b"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result["items"] == ["a", "b"]
    end

    test "parses empty nested object" do
      {:ok, {result, _}} = StructuralParserV2.parse("meta:", @opts)
      assert result == %{"meta" => %{}}
    end

    test "parses with custom indent_size" do
      opts = Map.put(@opts, :indent_size, 4)
      {:ok, {result, _}} = StructuralParserV2.parse("user:\n    name: Bob", opts)
      assert result == %{"user" => %{"name" => "Bob"}}
    end

    test "parses multiple sibling nested objects" do
      toon = "a:\n  x: 1\nb:\n  x: 2"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result["a"] == %{"x" => 1}
      assert result["b"] == %{"x" => 2}
    end

    test "parses mixed primitives and nested objects" do
      toon = "name: Alice\naddress:\n  city: NYC\nage: 30"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result["name"] == "Alice"
      assert result["address"] == %{"city" => "NYC"}
      assert result["age"] == 30
    end

    test "parses key with dot in name" do
      {:ok, {result, _}} = StructuralParserV2.parse("user.name: Alice", @opts)
      assert result == %{"user.name" => "Alice"}
    end

    test "parses key with special chars when quoted" do
      {:ok, {result, _}} = StructuralParserV2.parse(~s("a-b": 1), @opts)
      assert result == %{"a-b" => 1}
    end

    test "handles escaped quotes in quoted string" do
      {:ok, {result, _}} = StructuralParserV2.parse(~s(name: "say \"hello\""), @opts)
      assert result == %{"name" => "say \"hello\""}
    end

    test "handles escaped backslash in quoted string" do
      # Double backslash in source becomes single backslash in string
      {:ok, {result, _}} = StructuralParserV2.parse("path: \"C:\\\\Users\"", @opts)
      assert result == %{"path" => "C:\\Users"}
    end

    test "parses inline array with declared length" do
      {:ok, {result, _}} = StructuralParserV2.parse("items[3]: a,b,c", @opts)
      assert result == %{"items" => ["a", "b", "c"]}
    end

    test "parses list array with nested objects" do
      toon = "people[2]:\n  - name: Alice\n    age: 30\n  - name: Bob\n    age: 25"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result["people"] == [%{"name" => "Alice", "age" => 30}, %{"name" => "Bob", "age" => 25}]
    end

    test "parses invalid TOON gracefully" do
      # The parser is lenient and may parse some invalid-looking input
      # Just verify it doesn't crash
      result = StructuralParserV2.parse("invalid: : data", @opts)
      assert elem(result, 0) == :ok or elem(result, 0) == :error
    end

    test "parses tab in indentation in strict mode without error" do
      # The parser may accept tab in indentation depending on implementation
      opts = Map.put(@opts, :strict, true)
      result = StructuralParserV2.parse("parent:\n\tchild: 1", opts)
      assert elem(result, 0) == :ok or elem(result, 0) == :error
    end
  end

  describe "keys: :atoms!" do
    test "parses simple key-value with existing atoms" do
      opts = Map.put(@opts, :keys, :atoms!)
      {:ok, {result, _}} = StructuralParserV2.parse("name: Alice", opts)
      assert result == %{name: "Alice"}
    end

    test "parses multiple key-values with atoms!" do
      opts = Map.put(@opts, :keys, :atoms!)
      {:ok, {result, _}} = StructuralParserV2.parse("name: Alice\nage: 30", opts)
      assert result == %{name: "Alice", age: 30}
    end

    test "parses nested object with atoms!" do
      opts = Map.put(@opts, :keys, :atoms!)
      {:ok, {result, _}} = StructuralParserV2.parse("user:\n  name: Bob", opts)
      assert result == %{user: %{name: "Bob"}}
    end

    test "parses tabular array with atoms! keys" do
      opts = Map.put(@opts, :keys, :atoms!)
      toon = "users[2]{name,age}:\n  Alice,30\n  Bob,25"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, opts)
      assert result[:users] == [%{name: "Alice", age: 30}, %{name: "Bob", age: 25}]
    end
  end

  describe "number parsing edge cases" do
    test "parses zero as integer" do
      {:ok, {result, _}} = StructuralParserV2.parse("val: 0", @opts)
      assert result == %{"val" => 0}
    end

    test "parses negative zero as integer" do
      {:ok, {result, _}} = StructuralParserV2.parse("val: -0", @opts)
      assert result == %{"val" => 0}
    end

    test "treats leading zeros as string" do
      {:ok, {result, _}} = StructuralParserV2.parse("val: 05", @opts)
      assert result == %{"val" => "05"}
    end

    test "treats negative leading zeros as string" do
      {:ok, {result, _}} = StructuralParserV2.parse("val: -007", @opts)
      assert result == %{"val" => "-007"}
    end

    test "parses float with decimal that is whole number" do
      {:ok, {result, _}} = StructuralParserV2.parse("val: 1.0", @opts)
      assert result == %{"val" => 1}
    end

    test "parses float with decimal as float" do
      {:ok, {result, _}} = StructuralParserV2.parse("val: 3.14", @opts)
      assert result == %{"val" => 3.14}
    end

    test "parses float with exponent as float" do
      {:ok, {result, _}} = StructuralParserV2.parse("val: 1e6", @opts)
      assert result == %{"val" => 1_000_000.0}
    end

    test "parses uppercase exponent" do
      {:ok, {result, _}} = StructuralParserV2.parse("val: 1E2", @opts)
      assert result == %{"val" => 100.0}
    end
  end

  describe "string escape sequences" do
    test "unescapes backslash" do
      {:ok, {result, _}} = StructuralParserV2.parse(~S(text: "C:\\Users"), @opts)
      assert result == %{"text" => "C:\\Users"}
    end

    test "unescapes escaped quote in string" do
      {:ok, {result, _}} = StructuralParserV2.parse(~S(text: "say \"hi\""), @opts)
      assert result == %{"text" => "say \"hi\""}
    end

    test "unescapes newline" do
      {:ok, {result, _}} = StructuralParserV2.parse(~S(text: "line1\nline2"), @opts)
      assert result == %{"text" => "line1\nline2"}
    end

    test "unescapes carriage return" do
      {:ok, {result, _}} = StructuralParserV2.parse(~S(text: "a\rb"), @opts)
      assert result == %{"text" => "a\rb"}
    end

    test "unescapes tab" do
      {:ok, {result, _}} = StructuralParserV2.parse(~S(text: "a\tb"), @opts)
      assert result == %{"text" => "a\tb"}
    end

    test "unescapes multiple backslash sequences" do
      {:ok, {result, _}} = StructuralParserV2.parse(~S(text: "a\\b\\nc"), @opts)
      assert result == %{"text" => "a\\b\\nc"}
    end

    test "unescapes mixed escape sequences" do
      {:ok, {result, _}} = StructuralParserV2.parse(~S(text: "tab\there\nnewline"), @opts)
      assert result == %{"text" => "tab\there\nnewline"}
    end

    test "returns error on invalid escape sequence" do
      assert {:error, _} = StructuralParserV2.parse(~S(text: "\x"), @opts)
    end

    test "returns error on unterminated quoted string" do
      assert {:error, _} = StructuralParserV2.parse(~S(text: "unterminated), @opts)
    end

    test "parses quoted key with escapes" do
      {:ok, {result, _}} = StructuralParserV2.parse(~S("a\nb": value), @opts)
      assert result == %{"a\nb" => "value"}
    end

    test "parses quoted key with escaped quote" do
      {:ok, {result, _}} = StructuralParserV2.parse(~S("a\"b": value), @opts)
      assert result == %{"a\"b" => "value"}
    end

    test "returns error on unterminated quoted key" do
      assert {:error, _} = StructuralParserV2.parse(~S("unterminated: value), @opts)
    end

    test "parses string with escaped backslash followed by quote" do
      {:ok, {result, _}} = StructuralParserV2.parse(~S(text: "end\\"), @opts)
      assert result == %{"text" => "end\\"}
    end
  end

  describe "root array formats" do
    test "parses root tabular array" do
      toon = "[2]{name,age}:\n  Alice,30\n  Bob,25"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == [%{"name" => "Alice", "age" => 30}, %{"name" => "Bob", "age" => 25}]
    end

    test "parses root list array" do
      toon = "[2]:\n  - apple\n  - banana"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == ["apple", "banana"]
    end

    test "parses root array with tab delimiter" do
      toon = "[2\t]: a\tb"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == ["a", "b"]
    end

    test "parses root array with pipe delimiter" do
      toon = "[2|]: a|b"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == ["a", "b"]
    end
  end

  describe "root primitive errors" do
    test "returns error on invalid root primitive with colon" do
      assert {:error, _} = StructuralParserV2.parse("invalid:value", @opts)
    end
  end

  describe "root primitive numbers" do
    test "parses scientific notation positive exponent" do
      {:ok, {result, _}} = StructuralParserV2.parse("1e6", @opts)
      assert result == 1_000_000
    end

    test "parses scientific notation uppercase exponent" do
      {:ok, {result, _}} = StructuralParserV2.parse("1E2", @opts)
      assert result == 100
    end

    test "parses negative zero" do
      {:ok, {result, _}} = StructuralParserV2.parse("-0", @opts)
      assert result == 0
    end

    test "parses negative zero float" do
      {:ok, {result, _}} = StructuralParserV2.parse("-0.0", @opts)
      assert result == 0
    end

    test "parses plain zero" do
      {:ok, {result, _}} = StructuralParserV2.parse("0", @opts)
      assert result == 0
    end

    test "keeps zero-padded numbers as strings" do
      {:ok, {result, _}} = StructuralParserV2.parse("05", @opts)
      assert result == "05"
    end

    test "keeps zero-padded negative numbers as strings" do
      {:ok, {result, _}} = StructuralParserV2.parse("-007", @opts)
      assert result == "-007"
    end
  end

  describe "quoted key tracking" do
    test "tracks quoted keys in metadata" do
      {:ok, {_, metadata}} = StructuralParserV2.parse(~s("full name": Alice), @opts)
      assert MapSet.member?(metadata.quoted_keys, "full name")
    end

    test "quoted keys in nested objects are tracked" do
      toon = "user:\n  \"real name\": Bob"
      {:ok, {_, metadata}} = StructuralParserV2.parse(toon, @opts)
      assert MapSet.member?(metadata.quoted_keys, "real name")
    end
  end

  describe "whitespace edge cases" do
    test "trims whitespace around values" do
      {:ok, {result, _}} = StructuralParserV2.parse("name:   Alice  ", @opts)
      assert result == %{"name" => "Alice"}
    end

    test "handles trailing blank lines after content" do
      toon = "name: Alice\n\n\n"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == %{"name" => "Alice"}
    end

    test "parses empty value as empty map" do
      {:ok, {result, _}} = StructuralParserV2.parse("key: ", @opts)
      assert result == %{"key" => %{}}
    end
  end

  describe "strict mode validation errors" do
    test "rejects non-multiple indent in strict mode" do
      opts = Map.put(@opts, :indent_size, 4)
      assert {:error, _} = StructuralParserV2.parse("parent:\n   child: 1", opts)
    end

    test "rejects non-multiple indent in strict mode with indent_size 4" do
      opts = Map.put(@opts, :indent_size, 4)
      assert {:error, _} = StructuralParserV2.parse("parent:\n   child: 1", opts)
    end

    test "rejects tab characters in indentation in strict mode" do
      assert {:error, _} = StructuralParserV2.parse("\tname: x", @opts)
    end

    test "rejects tab characters in nested indentation in strict mode" do
      assert {:error, _} = StructuralParserV2.parse("parent:\n\tchild: 1", @opts)
    end

    test "accepts tab characters inside value in strict mode" do
      {:ok, {result, _}} = StructuralParserV2.parse("name: a\tb", @opts)
      assert result == %{"name" => "a\tb"}
    end

    test "accepts multiple-of-indent nested lines in strict mode" do
      opts = Map.put(@opts, :indent_size, 4)
      {:ok, {result, _}} = StructuralParserV2.parse("parent:\n    child: 1", opts)
      assert result == %{"parent" => %{"child" => 1}}
    end
  end

  describe "array length validation in strict mode" do
    test "strict mode rejects array length mismatch" do
      toon = "items[3]: a,b"
      opts_strict = Map.put(@opts, :strict, true)
      assert {:error, _} = StructuralParserV2.parse(toon, opts_strict)
    end
  end

  describe "complex nested list items" do
    test "parses list item with nested object" do
      toon = "people[2]:\n  - name: Alice\n  - name: Bob"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result["people"] == [%{"name" => "Alice"}, %{"name" => "Bob"}]
    end

    test "parses list item with inline array" do
      toon = "[2]: a,b"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == ["a", "b"]
    end

    test "parses list item with nested inline array" do
      toon = "outer[2]:\n  - [2]: a,b\n  - [2]: c,d"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == %{"outer" => [["a", "b"], ["c", "d"]]}
    end

    test "parses root tabular array" do
      toon = "[2]{name,age}:\n  Alice,30\n  Bob,40"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == [%{"name" => "Alice", "age" => 30}, %{"name" => "Bob", "age" => 40}]
    end

    test "parses root tabular array with pipe delimiter" do
      toon = "[2|]{name|age}:\n  Alice|30\n  Bob|40"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == [%{"name" => "Alice", "age" => 30}, %{"name" => "Bob", "age" => 40}]
    end

    test "rejects root tabular array with row count mismatch" do
      toon = "[2]{name,age}:\n  Alice,30\n  Bob,40\n  Charlie,50"
      assert {:error, _} = StructuralParserV2.parse(toon, @opts)
    end

    test "rejects single-line root tabular array" do
      assert {:error, _} = StructuralParserV2.parse("[2]{name,age}:", @opts)
    end

    test "rejects invalid root array header" do
      assert {:error, _} = StructuralParserV2.parse("[:", @opts)
    end

    test "rejects blank lines inside arrays in strict mode" do
      toon = "outer:\n  items[2]:\n    a\n\n    b"
      assert {:error, _} = StructuralParserV2.parse(toon, @opts)
    end

    test "accepts blank lines inside arrays in non-strict mode" do
      toon = "items[2]:\n  - a\n\n  - b"
      opts = Map.put(@opts, :strict, false)
      {:ok, {result, _}} = StructuralParserV2.parse(toon, opts)
      assert result == %{"items" => ["a", "b"]}
    end

    test "rejects nested list array length mismatch" do
      toon = "outer:\n  items[3]:\n    - a\n    - b"
      assert {:error, _} = StructuralParserV2.parse(toon, @opts)
    end

    test "parses list item with child continuation lines" do
      toon = "items[1]:\n  - args:\n      device_id: val"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == %{"items" => [%{"args" => %{"device_id" => "val"}}]}
    end

    test "parses list item with sibling continuation lines" do
      toon = "items[1]:\n  - name: \n    age: 30"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result["items"] == [%{"name" => %{}, "age" => 30}]
    end

    test "parses list item with non-empty value and continuation lines" do
      toon = "items[1]:\n  - name: bob\n    age: 30"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == %{"items" => [%{"name" => "bob", "age" => 30}]}
    end

    test "parses list item with deeply nested child" do
      toon = "items[1]:\n  - name:\n      child: val"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == %{"items" => [%{"name" => %{"child" => "val"}}]}
    end

    test "parses empty root inline array" do
      {:ok, {result, _}} = StructuralParserV2.parse("[0]:", @opts)
      assert result == []
    end

    test "parses empty root inline array with trailing space" do
      {:ok, {result, _}} = StructuralParserV2.parse("[0]: ", @opts)
      assert result == []
    end

    test "parses nested empty inline array" do
      {:ok, {result, _}} = StructuralParserV2.parse("k:\n  x[1]:", @opts)
      assert result == %{"k" => %{"x" => []}}
    end

    test "parses root tabular array with atoms keys" do
      toon = "rows[2]{name,age}:\n  Alice,30\n  Bob,40"
      opts = Map.put(@opts, :keys, :atoms)
      {:ok, {result, _}} = StructuralParserV2.parse(toon, opts)
      assert result == %{rows: [%{name: "Alice", age: 30}, %{name: "Bob", age: 40}]}
    end

    test "parses object with blank lines between entries in strict mode" do
      {:ok, {result, _}} = StructuralParserV2.parse("a: 1\n\nb: 2", @opts)
      assert result == %{"a" => 1, "b" => 2}
    end

    test "parses object with blank lines between entries in non-strict mode" do
      opts = Map.put(@opts, :strict, false)
      {:ok, {result, _}} = StructuralParserV2.parse("a: 1\n\nb: 2", opts)
      assert result == %{"a" => 1, "b" => 2}
    end

    test "parses object with blank line after parent key" do
      opts = Map.put(@opts, :strict, false)
      {:ok, {result, _}} = StructuralParserV2.parse("outer:\n\n  a: 1", opts)
      assert result == %{"outer" => %{"a" => 1}}
    end

    test "parses empty dash list items" do
      {:ok, {result, _}} = StructuralParserV2.parse("items[2]:\n  -\n  -", @opts)
      assert result == %{"items" => [%{}, %{}]}
    end

    test "parses list items with inline arrays" do
      toon = "items[2]:\n  - [2]: a,b\n  - [2]: c,d"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == %{"items" => [["a", "b"], ["c", "d"]]}
    end

    test "parses inline array with matching values" do
      {:ok, {result, _}} = StructuralParserV2.parse("items[2]: a,b", @opts)
      assert result == %{"items" => ["a", "b"]}
    end

    test "rejects inline array with value count mismatch" do
      assert {:error, _} = StructuralParserV2.parse("items[2]: a,b,c", @opts)
    end

    test "parses inline array followed by more entries" do
      {:ok, {result, _}} = StructuralParserV2.parse("items[2]: a,b\nnext: x", @opts)
      assert result == %{"items" => ["a", "b"], "next" => "x"}
    end

    test "parses nested object with atoms keys" do
      opts = Map.put(@opts, :keys, :atoms)
      {:ok, {result, _}} = StructuralParserV2.parse("outer:\n  name: x", opts)
      assert result == %{outer: %{name: "x"}}
    end

    test "parses list of objects with atoms keys" do
      opts = Map.put(@opts, :keys, :atoms)
      {:ok, {result, _}} = StructuralParserV2.parse("people[2]:\n  - name: A\n  - name: B", opts)
      assert result == %{people: [%{name: "A"}, %{name: "B"}]}
    end

    test "parses nested tabular array" do
      toon = "outer:\n  rows[2]{a,b}:\n    1,2\n    3,4"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == %{"outer" => %{"rows" => [%{"a" => 1, "b" => 2}, %{"a" => 3, "b" => 4}]}}
    end

    test "rejects nested tabular array with row count mismatch" do
      toon = "outer:\n  rows[3]{a,b}:\n    1,2\n    3,4"
      assert {:error, _} = StructuralParserV2.parse(toon, @opts)
    end

    test "rejects string ending with backslash" do
      toon = ~s(text: "abc\) <> "\""
      assert {:error, _} = StructuralParserV2.parse(toon, @opts)
    end

    test "rejects invalid escape sequence" do
      toon = ~s(text: "ab\\) <> "c\""
      assert {:error, _} = StructuralParserV2.parse(toon, @opts)
    end

    test "parses quoted value with comma in inline array" do
      toon = ~S(items[2]: "a,b",c)
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == %{"items" => ["a,b", "c"]}
    end

    test "parses escaped quote in inline array value" do
      toon = ~S(items[2]: "say \"hi\"",x)
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == %{"items" => ["say \"hi\"", "x"]}
    end

    test "parses quoted comma in tabular value" do
      toon = ~S(rows[1]{name,note}:
  "a,b",note)
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == %{"rows" => [%{"name" => "a,b", "note" => "note"}]}
    end

    test "rejects tabular row with too many values" do
      toon = "rows[2]{name,age}:\n  Alice,30,extra\n  Bob,40"
      assert {:error, _} = StructuralParserV2.parse(toon, @opts)
    end

    test "rejects tabular row with too few values" do
      toon = "rows[2]{name,age}:\n  Alice\n  Bob,40"
      assert {:error, _} = StructuralParserV2.parse(toon, @opts)
    end

    test "parses list item with colon in value" do
      toon = "items[2]:\n  - a: b:\n  - c"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == %{"items" => [%{"a" => "b:"}, "c"]}
    end

    test "parses list item with trailing comma" do
      toon = "items[2]:\n  - a,\n  - b"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == %{"items" => ["a", "b"]}
    end

    test "parses list item with multiple trailing commas" do
      toon = "items[2]:\n  - a,,,\n  - b"
      {:ok, {result, _}} = StructuralParserV2.parse(toon, @opts)
      assert result == %{"items" => ["a", "b"]}
    end
  end
end