defmodule ToonEx.Decode.StructuralParserTest do
  use ExUnit.Case, async: true

  alias ToonEx.Decode.StructuralParser

  @opts %{strict: true, indent_size: 2, keys: :strings}

  describe "ToonEx.Decode.StructuralParser.parse/2" do
    test "parses empty input" do
      assert {:ok, {%{}, _}} = StructuralParser.parse("", @opts)
    end

    test "parses whitespace only input" do
      assert {:ok, {%{}, _}} = StructuralParser.parse("   \n  \n  ", @opts)
    end

    test "parses simple key-value" do
      assert {:ok, {%{"name" => "Alice"}, _}} = StructuralParser.parse("name: Alice", @opts)
    end

    test "parses multiple key-values" do
      {:ok, {result, _}} = StructuralParser.parse("name: Alice\nage: 30", @opts)
      assert result == %{"name" => "Alice", "age" => 30}
    end

    test "parses nested object" do
      toon = "user:\n  name: Bob"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == %{"user" => %{"name" => "Bob"}}
    end

    test "parses two levels deep" do
      toon = "a:\n  b:\n    c: 1"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == %{"a" => %{"b" => %{"c" => 1}}}
    end

    test "parses sibling keys after nested block" do
      toon = "user:\n  name: Bob\nactive: true"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result["user"] == %{"name" => "Bob"}
      assert result["active"] == true
    end

    test "parses array with inline values" do
      {:ok, {result, _}} = StructuralParser.parse("tags[2]: a,b", @opts)
      assert result == %{"tags" => ["a", "b"]}
    end

    test "parses empty array" do
      {:ok, {result, _}} = StructuralParser.parse("tags[0]:", @opts)
      assert result == %{"tags" => []}
    end

    test "parses tabular array" do
      toon = "users[2]{name,age}:\n  Alice,30\n  Bob,25"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result["users"] == [%{"name" => "Alice", "age" => 30}, %{"name" => "Bob", "age" => 25}]
    end

    test "parses list array" do
      toon = "items[2]:\n  - apple\n  - banana"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result["items"] == ["apple", "banana"]
    end

    test "parses root primitive" do
      {:ok, {result, _}} = StructuralParser.parse("hello", @opts)
      assert result == "hello"
    end

    test "parses root primitive null" do
      {:ok, {result, _}} = StructuralParser.parse("null", @opts)
      assert result == nil
    end

    test "parses root primitive true" do
      {:ok, {result, _}} = StructuralParser.parse("true", @opts)
      assert result == true
    end

    test "parses root primitive false" do
      {:ok, {result, _}} = StructuralParser.parse("false", @opts)
      assert result == false
    end

    test "parses root primitive quoted string" do
      {:ok, {result, _}} = StructuralParser.parse(~S("hello world"), @opts)
      assert result == "hello world"
    end

    test "parses root array" do
      {:ok, {result, _}} = StructuralParser.parse("[2]: a,b", @opts)
      assert result == ["a", "b"]
    end

    test "parses with keys as atoms" do
      opts = Map.put(@opts, :keys, :atoms)
      {:ok, {result, _}} = StructuralParser.parse("name: Alice", opts)
      assert result == %{name: "Alice"}
    end

    test "accepts non-multiple indentation when strict: false" do
      opts = Map.put(@opts, :strict, false)
      {:ok, {result, _}} = StructuralParser.parse("parent:\n   child: 1", opts)
      assert result == %{"parent" => %{"child" => 1}}
    end

    test "rejects tab in indentation in strict mode" do
      opts = Map.put(@opts, :strict, true)
      # StructuralParser.parse returns {:error, _} in strict mode for tab indentation
      assert {:error, _} = StructuralParser.parse("parent:\n\tchild: 1", opts)
    end

    test "parses quoted key with spaces" do
      {:ok, {result, _}} = StructuralParser.parse(~s("full name": Alice), @opts)
      assert result == %{"full name" => "Alice"}
    end

    test "parses quoted value" do
      {:ok, {result, _}} = StructuralParser.parse(~s(name: "Alice"), @opts)
      assert result == %{"name" => "Alice"}
    end

    test "parses null value" do
      {:ok, {result, _}} = StructuralParser.parse("data: null", @opts)
      assert result == %{"data" => nil}
    end

    test "parses boolean value" do
      {:ok, {result, _}} = StructuralParser.parse("active: true", @opts)
      assert result == %{"active" => true}

      {:ok, {result, _}} = StructuralParser.parse("active: false", @opts)
      assert result == %{"active" => false}
    end

    test "parses float value" do
      {:ok, {result, _}} = StructuralParser.parse("price: 3.14", @opts)
      assert result == %{"price" => 3.14}
    end

    test "parses negative number" do
      {:ok, {result, _}} = StructuralParser.parse("temp: -10", @opts)
      assert result == %{"temp" => -10}
    end

    test "parses scientific notation" do
      {:ok, {result, _}} = StructuralParser.parse("big: 1e6", @opts)
      assert result == %{"big" => 1_000_000.0}

      {:ok, {result, _}} = StructuralParser.parse("small: 1e-3", @opts)
      assert result == %{"small" => 0.001}
    end

    test "parses array with tab delimiter" do
      # Tab delimiter is indicated in array marker: [2\t]:
      toon = "items[2\t]: a\tb"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result["items"] == ["a", "b"]
    end

    test "parses array with pipe delimiter" do
      # Pipe delimiter is indicated in array marker: [2|]:
      toon = "items[2|]: a|b"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result["items"] == ["a", "b"]
    end

    test "parses empty nested object" do
      {:ok, {result, _}} = StructuralParser.parse("meta:", @opts)
      assert result == %{"meta" => %{}}
    end

    test "parses with custom indent_size" do
      opts = Map.put(@opts, :indent_size, 4)
      {:ok, {result, _}} = StructuralParser.parse("user:\n    name: Bob", opts)
      assert result == %{"user" => %{"name" => "Bob"}}
    end

    test "parses multiple sibling nested objects" do
      toon = "a:\n  x: 1\nb:\n  x: 2"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result["a"] == %{"x" => 1}
      assert result["b"] == %{"x" => 2}
    end

    test "parses mixed primitives and nested objects" do
      toon = "name: Alice\naddress:\n  city: NYC\nage: 30"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result["name"] == "Alice"
      assert result["address"] == %{"city" => "NYC"}
      assert result["age"] == 30
    end

    test "parses key with dot in name" do
      {:ok, {result, _}} = StructuralParser.parse("user.name: Alice", @opts)
      assert result == %{"user.name" => "Alice"}
    end

    test "parses key with special chars when quoted" do
      {:ok, {result, _}} = StructuralParser.parse(~s("a-b": 1), @opts)
      assert result == %{"a-b" => 1}
    end
  end

  describe "keys: :atoms!" do
    test "parses simple key-value with existing atoms" do
      opts = Map.put(@opts, :keys, :atoms!)
      {:ok, {result, _}} = StructuralParser.parse("name: Alice", opts)
      assert result == %{name: "Alice"}
    end

    test "parses multiple key-values with atoms!" do
      opts = Map.put(@opts, :keys, :atoms!)
      {:ok, {result, _}} = StructuralParser.parse("name: Alice\nage: 30", opts)
      assert result == %{name: "Alice", age: 30}
    end

    test "parses nested object with atoms!" do
      opts = Map.put(@opts, :keys, :atoms!)
      {:ok, {result, _}} = StructuralParser.parse("user:\n  name: Bob", opts)
      assert result == %{user: %{name: "Bob"}}
    end

    test "parses tabular array with atoms! keys" do
      opts = Map.put(@opts, :keys, :atoms!)
      toon = "users[2]{name,age}:\n  Alice,30\n  Bob,25"
      {:ok, {result, _}} = StructuralParser.parse(toon, opts)
      assert result[:users] == [%{name: "Alice", age: 30}, %{name: "Bob", age: 25}]
    end

    test "parses inline array with atoms! keys" do
      opts = Map.put(@opts, :keys, :atoms!)
      {:ok, {result, _}} = StructuralParser.parse("tags[2]: a,b", opts)
      assert result == %{tags: ["a", "b"]}
    end

    test "parses list array with atoms!" do
      opts = Map.put(@opts, :keys, :atoms!)
      toon = "items[2]:\n  - apple\n  - banana"
      {:ok, {result, _}} = StructuralParser.parse(toon, opts)
      assert result == %{items: ["apple", "banana"]}
    end
  end

  describe "number parsing edge cases" do
    test "parses zero as integer" do
      {:ok, {result, _}} = StructuralParser.parse("val: 0", @opts)
      assert result == %{"val" => 0}
    end

    test "parses negative zero as integer" do
      {:ok, {result, _}} = StructuralParser.parse("val: -0", @opts)
      assert result == %{"val" => 0}
    end

    test "treats leading zeros as string" do
      {:ok, {result, _}} = StructuralParser.parse("val: 05", @opts)
      assert result == %{"val" => "05"}
    end

    test "treats negative leading zeros as string" do
      {:ok, {result, _}} = StructuralParser.parse("val: -007", @opts)
      assert result == %{"val" => "-007"}
    end

    test "parses float with decimal as float" do
      {:ok, {result, _}} = StructuralParser.parse("val: 3.14", @opts)
      assert result == %{"val" => 3.14}
    end

    test "parses float with exponent as float" do
      {:ok, {result, _}} = StructuralParser.parse("val: 1e6", @opts)
      assert result == %{"val" => 1_000_000.0}
    end

    test "parses float that looks like integer with exponent" do
      {:ok, {result, _}} = StructuralParser.parse("val: 1e2", @opts)
      assert result == %{"val" => 100.0}
    end
  end

  describe "string escape sequences" do
    test "unescapes newline" do
      {:ok, {result, _}} = StructuralParser.parse(~S(text: "line1\nline2"), @opts)
      assert result == %{"text" => "line1\nline2"}
    end

    test "unescapes carriage return" do
      {:ok, {result, _}} = StructuralParser.parse(~S(text: "line1\rline2"), @opts)
      assert result == %{"text" => "line1\rline2"}
    end

    test "unescapes tab" do
      {:ok, {result, _}} = StructuralParser.parse(~S(text: "col1\tcol2"), @opts)
      assert result == %{"text" => "col1\tcol2"}
    end

    test "unescapes backslash" do
      {:ok, {result, _}} = StructuralParser.parse(~S(text: "C:\\Users"), @opts)
      assert result == %{"text" => "C:\\Users"}
    end

    test "unescapes escaped quote in string" do
      {:ok, {result, _}} = StructuralParser.parse(~S(text: "say \"hi\""), @opts)
      assert result == %{"text" => "say \"hi\""}
    end

    test "returns error on invalid escape sequence" do
      assert {:error, _} = StructuralParser.parse(~S(text: "\x"), @opts)
    end

    test "returns error on unterminated quoted string" do
      assert {:error, _} = StructuralParser.parse(~S(text: "unterminated), @opts)
    end

    test "parses quoted key with escapes" do
      {:ok, {result, _}} = StructuralParser.parse(~S("a\nb": value), @opts)
      assert result == %{"a\nb" => "value"}
    end
  end

  describe "root array formats" do
    test "parses root tabular array" do
      toon = "[2]{name,age}:\n  Alice,30\n  Bob,25"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == [%{"name" => "Alice", "age" => 30}, %{"name" => "Bob", "age" => 25}]
    end

    test "parses root list array" do
      toon = "[2]:\n  - apple\n  - banana"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == ["apple", "banana"]
    end

    test "parses root array with invalid header as array" do
      {:ok, {result, _}} = StructuralParser.parse("[invalid]:\n  - item", @opts)
      assert result == ["item"]
    end

    test "returns error on root inline array with missing values" do
      assert {:error, _} = StructuralParser.parse("[2]:", @opts)
    end

    test "parses root array with tab delimiter" do
      toon = "[2\t]: a\tb"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == ["a", "b"]
    end

    test "parses root array with pipe delimiter" do
      toon = "[2|]: a|b"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == ["a", "b"]
    end
  end

  describe "root primitive errors" do
    test "returns error on invalid root primitive with colon" do
      assert {:error, %{message: _}} = StructuralParser.parse("invalid:value", @opts)
    end
  end

  describe "root primitive numbers" do
    test "parses scientific notation positive exponent" do
      {:ok, {result, _}} = StructuralParser.parse("1e6", @opts)
      assert result == 1_000_000
    end

    test "parses scientific notation uppercase exponent" do
      {:ok, {result, _}} = StructuralParser.parse("1E2", @opts)
      assert result == 100
    end

    test "parses negative zero" do
      {:ok, {result, _}} = StructuralParser.parse("-0", @opts)
      assert result == 0
    end

    test "parses negative zero float" do
      {:ok, {result, _}} = StructuralParser.parse("-0.0", @opts)
      assert result == 0
    end

    test "parses plain zero" do
      {:ok, {result, _}} = StructuralParser.parse("0", @opts)
      assert result == 0
    end

    test "keeps zero-padded numbers as strings" do
      {:ok, {result, _}} = StructuralParser.parse("05", @opts)
      assert result == "05"
    end

    test "keeps zero-padded negative numbers as strings" do
      {:ok, {result, _}} = StructuralParser.parse("-007", @opts)
      assert result == "-007"
    end
  end

  describe "quoted key tracking" do
    test "tracks quoted keys in metadata" do
      {:ok, {_, metadata}} = StructuralParser.parse(~s("full name": Alice), @opts)
      assert MapSet.member?(metadata.quoted_keys, "full name")
    end

    test "quoted keys in nested objects are tracked" do
      toon = "user:\n  \"real name\": Bob"
      {:ok, {_, metadata}} = StructuralParser.parse(toon, @opts)
      assert MapSet.member?(metadata.quoted_keys, "real name")
    end
  end

  describe "whitespace handling" do
    test "trims whitespace around values" do
      {:ok, {result, _}} = StructuralParser.parse("name:   Alice  ", @opts)
      assert result == %{"name" => "Alice"}
    end

    test "handles trailing blank lines after content" do
      toon = "name: Alice\n\n\n"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == %{"name" => "Alice"}
    end

    test "parses empty value as empty map" do
      {:ok, {result, _}} = StructuralParser.parse("key: ", @opts)
      assert result == %{"key" => %{}}
    end
  end

  describe "strict mode validation errors" do
    test "rejects non-multiple indent in strict mode with indent_size 4" do
      opts = Map.put(@opts, :indent_size, 4)
      assert {:error, _} = StructuralParser.parse("parent:\n   child: 1", opts)
    end

    test "rejects over-indented line in strict mode" do
      opts = Map.put(@opts, :strict, true)
      assert {:error, _} = StructuralParser.parse("key: value\n    extra: data", opts)
    end

    test "rejects tab characters in indentation in strict mode" do
      assert {:error, _} = StructuralParser.parse("\tname: x", @opts)
    end

    test "rejects tab characters in nested indentation in strict mode" do
      assert {:error, _} = StructuralParser.parse("parent:\n\tchild: 1", @opts)
    end

    test "accepts tab characters inside value in strict mode" do
      {:ok, {result, _}} = StructuralParser.parse("name: a\tb", @opts)
      assert result == %{"name" => "a\tb"}
    end

    test "accepts multiple-of-indent nested lines in strict mode" do
      opts = Map.put(@opts, :indent_size, 4)
      {:ok, {result, _}} = StructuralParser.parse("parent:\n    child: 1", opts)
      assert result == %{"parent" => %{"child" => 1}}
    end
  end

  describe "array length validation in strict mode" do
    test "strict mode rejects array length mismatch" do
      toon = "items[3]: a,b"
      opts_strict = Map.put(@opts, :strict, true)
      assert {:error, _} = StructuralParser.parse(toon, opts_strict)
    end
  end

  describe "complex list item scenarios" do
    test "parses list item with nested object in list" do
      toon = "people[2]:\n  - name: Alice\n  - name: Bob"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result["people"] == [%{"name" => "Alice"}, %{"name" => "Bob"}]
    end

    test "parses root tabular array" do
      toon = "[2]{name,age}:\n  Alice,30\n  Bob,40"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == [%{"name" => "Alice", "age" => 30}, %{"name" => "Bob", "age" => 40}]
    end

    test "parses root tabular array with pipe delimiter" do
      toon = "[2|]{name|age}:\n  Alice|30\n  Bob|40"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == [%{"name" => "Alice", "age" => 30}, %{"name" => "Bob", "age" => 40}]
    end

    test "rejects root tabular array with row count mismatch" do
      toon = "[2]{name,age}:\n  Alice,30\n  Bob,40\n  Charlie,50"
      assert {:error, _} = StructuralParser.parse(toon, @opts)
    end

    test "rejects single-line root tabular array" do
      assert {:error, _} = StructuralParser.parse("[2]{name,age}:", @opts)
    end

    test "rejects blank lines inside arrays in strict mode" do
      toon = "outer:\n  items[2]:\n    - a\n\n    - b"
      assert {:error, _} = StructuralParser.parse(toon, @opts)
    end

    test "accepts blank lines inside arrays in non-strict mode" do
      toon = "items[2]:\n  - a\n\n  - b"
      opts = Map.put(@opts, :strict, false)
      {:ok, {result, _}} = StructuralParser.parse(toon, opts)
      assert result == %{"items" => ["a", "b"]}
    end

    test "rejects nested list array length mismatch" do
      toon = "outer:\n  items[3]:\n    - a\n    - b"
      assert {:error, _} = StructuralParser.parse(toon, @opts)
    end

    test "parses list item with child continuation lines" do
      toon = "items[1]:\n  - args:\n      device_id: val"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == %{"items" => [%{"args" => %{"device_id" => "val"}}]}
    end

    test "parses list item with sibling continuation lines" do
      toon = "items[1]:\n  - name: \n    age: 30"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result["items"] == [%{"name" => %{}, "age" => 30}]
    end

    test "parses list item with non-empty value and continuation lines" do
      toon = "items[1]:\n  - name: bob\n    age: 30"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == %{"items" => [%{"name" => "bob", "age" => 30}]}
    end

    test "parses list item with deeply nested child" do
      toon = "items[1]:\n  - name:\n      child: val"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == %{"items" => [%{"name" => %{"child" => "val"}}]}
    end

    test "returns error on empty root inline array" do
      assert {:error, _} = StructuralParser.parse("[0]:", @opts)
    end

    test "returns error on empty root inline array with trailing space" do
      assert {:error, _} = StructuralParser.parse("[0]: ", @opts)
    end

    test "parses nested empty inline array" do
      {:ok, {result, _}} = StructuralParser.parse("k:\n  x[1]:", @opts)
      assert result == %{"k" => %{"x" => []}}
    end

    test "parses root tabular array with atoms keys" do
      toon = "rows[2]{name,age}:\n  Alice,30\n  Bob,40"
      opts = Map.put(@opts, :keys, :atoms)
      {:ok, {result, _}} = StructuralParser.parse(toon, opts)
      assert result == %{rows: [%{name: "Alice", age: 30}, %{name: "Bob", age: 40}]}
    end

    test "parses object with blank lines between entries in strict mode" do
      {:ok, {result, _}} = StructuralParser.parse("a: 1\n\nb: 2", @opts)
      assert result == %{"a" => 1, "b" => 2}
    end

    test "parses object with blank lines between entries in non-strict mode" do
      opts = Map.put(@opts, :strict, false)
      {:ok, {result, _}} = StructuralParser.parse("a: 1\n\nb: 2", opts)
      assert result == %{"a" => 1, "b" => 2}
    end

    test "parses object with blank line after parent key" do
      opts = Map.put(@opts, :strict, false)
      {:ok, {result, _}} = StructuralParser.parse("outer:\n\n  a: 1", opts)
      assert result == %{"outer" => %{"a" => 1}}
    end

    test "parses empty dash list items" do
      {:ok, {result, _}} = StructuralParser.parse("items[2]:\n  -\n  -", @opts)
      assert result == %{"items" => [%{}, %{}]}
    end

    test "parses list items with inline arrays" do
      toon = "items[2]:\n  - [2]: a,b\n  - [2]: c,d"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == %{"items" => [["a", "b"], ["c", "d"]]}
    end

    test "parses nested object with atoms keys" do
      opts = Map.put(@opts, :keys, :atoms)
      {:ok, {result, _}} = StructuralParser.parse("outer:\n  name: x", opts)
      assert result == %{outer: %{name: "x"}}
    end

    test "parses list of objects with atoms keys" do
      opts = Map.put(@opts, :keys, :atoms)
      {:ok, {result, _}} = StructuralParser.parse("people[2]:\n  - name: A\n  - name: B", opts)
      assert result == %{people: [%{name: "A"}, %{name: "B"}]}
    end

    test "parses nested tabular array" do
      toon = "outer:\n  rows[2]{a,b}:\n    1,2\n    3,4"
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == %{"outer" => %{"rows" => [%{"a" => 1, "b" => 2}, %{"a" => 3, "b" => 4}]}}
    end

    test "rejects nested tabular array with row count mismatch" do
      toon = "outer:\n  rows[3]{a,b}:\n    1,2\n    3,4"
      assert {:error, _} = StructuralParser.parse(toon, @opts)
    end

    test "rejects string ending with backslash" do
      toon = ~s(text: "abc\) <> "\""
      assert {:error, _} = StructuralParser.parse(toon, @opts)
    end

    test "rejects invalid escape sequence" do
      toon = ~s(text: "ab\\) <> "c\""
      assert {:error, _} = StructuralParser.parse(toon, @opts)
    end

    test "parses quoted value with comma in inline array" do
      toon = ~S(items[2]: "a,b",c)
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == %{"items" => ["a,b", "c"]}
    end

    test "parses escaped quote in inline array value" do
      toon = ~S(items[2]: "say \"hi\"",x)
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == %{"items" => ["say \"hi\"", "x"]}
    end

    test "parses quoted comma in tabular value" do
      toon = ~S(rows[1]{name,note}:
  "a,b",note)
      {:ok, {result, _}} = StructuralParser.parse(toon, @opts)
      assert result == %{"rows" => [%{"name" => "a,b", "note" => "note"}]}
    end

    test "rejects tabular row with too many values" do
      toon = "rows[2]{name,age}:\n  Alice,30,extra\n  Bob,40"
      assert {:error, _} = StructuralParser.parse(toon, @opts)
    end

    test "rejects tabular row with too few values" do
      toon = "rows[2]{name,age}:\n  Alice\n  Bob,40"
      assert {:error, _} = StructuralParser.parse(toon, @opts)
    end
  end
end