defmodule ToonEx.EncodeTest do
  use ExUnit.Case, async: true

  # ── primitives ───────────────────────────────────────────────────────────────

  describe "primitive encoding" do
    test "nil encodes as null" do
      assert {:ok, "null"} = ToonEx.encode(nil)
    end

    test "true encodes as true" do
      assert {:ok, "true"} = ToonEx.encode(true)
    end

    test "false encodes as false" do
      assert {:ok, "false"} = ToonEx.encode(false)
    end

    test "integer" do
      assert {:ok, "42"} = ToonEx.encode(42)
    end

    test "negative integer" do
      assert {:ok, "-17"} = ToonEx.encode(-17)
    end

    test "zero" do
      assert {:ok, "0"} = ToonEx.encode(0)
    end

    test "float" do
      assert {:ok, "3.14"} = ToonEx.encode(3.14)
    end

    test "whole-number float omits decimal point" do
      assert {:ok, "1"} = ToonEx.encode(1.0)
    end

    test "negative zero normalises to integer 0" do
      assert {:ok, "0"} = ToonEx.encode(-0.0)
    end

    # Infinity cannot be constructed via arithmetic on all BEAM versions
    # (overflowing float raises badarith). The boundary guard is tested via
    # ToonEx.Utils.NormalizeTest instead.

    test "max representable float encodes without null" do
      {:ok, result} = ToonEx.encode(1.0e308)
      refute result == "null"
    end

    test "small float no scientific notation" do
      {:ok, result} = ToonEx.encode(1.0e-10)
      refute String.contains?(result, "e")
      refute String.contains?(result, "E")
    end

    test "simple string" do
      assert {:ok, "hello"} = ToonEx.encode("hello")
    end

    test "empty string is quoted" do
      assert {:ok, ~s("")} = ToonEx.encode("")
    end

    test "string with spaces is not quoted" do
      assert {:ok, "hello world"} = ToonEx.encode("hello world")
    end

    test "string starting with # is quoted" do
      assert {:ok, "\"#comment\""} = ToonEx.encode("#comment")
    end

    test "string starting with - is quoted" do
      assert {:ok, "\"-value\""} = ToonEx.encode("-value")
    end

    test "string with colon is quoted" do
      assert {:ok, "\"a:b\""} = ToonEx.encode("a:b")
    end

    test "string with comma is quoted" do
      assert {:ok, "\"a,b\""} = ToonEx.encode("a,b")
    end

    test "string with newline is quoted" do
      assert {:ok, "\"line1\\nline2\""} = ToonEx.encode("line1\nline2")
    end

    test "string with tab is quoted" do
      assert {:ok, "\"col1\\tcol2\""} = ToonEx.encode("col1\tcol2")
    end

    test "string with backslash is quoted and escaped" do
      assert {:ok, "\"back\\\\slash\""} = ToonEx.encode("back\\slash")
    end

    test "string with double quote is quoted and escaped" do
      assert {:ok, "\"say \\\"hi\\\"\""} = ToonEx.encode(~s(say "hi"))
    end

    test "string with leading space is quoted" do
      assert {:ok, "\" leading\""} = ToonEx.encode(" leading")
    end

    test "string with trailing space is quoted" do
      assert {:ok, "\"trailing \""} = ToonEx.encode("trailing ")
    end

    test "string that looks like null is quoted" do
      assert {:ok, "\"null\""} = ToonEx.encode("null")
    end

    test "string that looks like true is quoted" do
      assert {:ok, "\"true\""} = ToonEx.encode("true")
    end

    test "string that looks like false is quoted" do
      assert {:ok, "\"false\""} = ToonEx.encode("false")
    end

    test "string that looks like integer is quoted" do
      assert {:ok, "\"42\""} = ToonEx.encode("42")
    end

    test "string that looks like float is quoted" do
      assert {:ok, "\"3.14\""} = ToonEx.encode("3.14")
    end
  end

  # ── map encoding ─────────────────────────────────────────────────────────────

  describe "map encoding" do
    test "empty map encodes to empty string" do
      assert {:ok, ""} = ToonEx.encode(%{})
    end

    test "single key-value" do
      assert {:ok, "name: Alice"} = ToonEx.encode(%{"name" => "Alice"})
    end

    test "multiple keys are sorted alphabetically" do
      {:ok, result} = ToonEx.encode(%{"z" => 1, "a" => 2})
      assert result == "a: 2\nz: 1"
    end

    test "atom keys are converted to strings" do
      {:ok, result} = ToonEx.encode(%{name: "Alice"})
      assert result == "name: Alice"
    end

    test "nested map" do
      {:ok, result} = ToonEx.encode(%{"user" => %{"name" => "Bob"}})
      assert result == "user:\n  name: Bob"
    end

    test "deeply nested map" do
      {:ok, result} = ToonEx.encode(%{"a" => %{"b" => %{"c" => 1}}})
      assert result == "a:\n  b:\n    c: 1"
    end

    test "empty nested map" do
      {:ok, result} = ToonEx.encode(%{"meta" => %{}})
      assert result == "meta:"
    end

    test "null value" do
      {:ok, result} = ToonEx.encode(%{"x" => nil})
      assert result == "x: null"
    end

    test "key requiring quotes is quoted" do
      {:ok, result} = ToonEx.encode(%{"full name" => "Alice"})
      assert result == ~s("full name": Alice)
    end

    test "key starting with digit is quoted" do
      {:ok, result} = ToonEx.encode(%{"123" => "val"})
      assert result == ~s("123": val)
    end

    test "indent: 4 option" do
      {:ok, result} = ToonEx.encode(%{"a" => %{"b" => 1}}, indent: 4)
      assert result == "a:\n    b: 1"
    end
  end

  # ── string value quoting ─────────────────────────────────────────────────────

  describe "string quoting rules" do
    test "string with colon is quoted" do
      {:ok, result} = ToonEx.encode(%{"x" => "a:b"})
      assert result == ~s(x: "a:b")
    end

    test "string that looks like true is quoted" do
      {:ok, result} = ToonEx.encode(%{"x" => "true"})
      assert result == ~s(x: "true")
    end

    test "string that looks like null is quoted" do
      {:ok, result} = ToonEx.encode(%{"x" => "null"})
      assert result == ~s(x: "null")
    end

    test "string that looks like a number is quoted" do
      {:ok, result} = ToonEx.encode(%{"x" => "42"})
      assert result == ~s(x: "42")
    end

    test "string with leading space is quoted" do
      {:ok, result} = ToonEx.encode(%{"x" => " leading"})
      assert result == ~s(x: " leading")
    end

    test "string starting with hyphen is quoted" do
      {:ok, result} = ToonEx.encode(%{"x" => "-not-a-marker"})
      assert result == ~s(x: "-not-a-marker")
    end

    test "string with newline escapes it" do
      {:ok, result} = ToonEx.encode(%{"x" => "line1\nline2"})
      assert result == ~s(x: "line1\\nline2")
    end

    test "string with backslash escapes it" do
      {:ok, result} = ToonEx.encode(%{"x" => "a\\b"})
      assert result == ~s(x: "a\\\\b")
    end

    test "string with tab escapes it" do
      {:ok, result} = ToonEx.encode(%{"x" => "a\tb"})
      assert result == ~s(x: "a\\tb")
    end

    test "string with pipe NOT quoted when delimiter is comma" do
      {:ok, result} = ToonEx.encode(%{"x" => "a|b"}, delimiter: ",")
      assert result == "x: a|b"
    end

    test "string with pipe quoted when delimiter is pipe" do
      {:ok, result} = ToonEx.encode(%{"x" => "a|b"}, delimiter: "|")
      assert result == ~s(x: "a|b")
    end
  end

  # ── array encoding ───────────────────────────────────────────────────────────

  describe "inline array encoding" do
    test "empty array" do
      {:ok, result} = ToonEx.encode(%{"items" => []})
      assert result == "items[0]:"
    end

    test "primitive array" do
      {:ok, result} = ToonEx.encode(%{"tags" => ["a", "b", "c"]})
      assert result == "tags[3]: a,b,c"
    end

    test "integer array" do
      {:ok, result} = ToonEx.encode(%{"ns" => [1, 2, 3]})
      assert result == "ns[3]: 1,2,3"
    end

    test "mixed-type array" do
      {:ok, result} = ToonEx.encode(%{"x" => [1, "hello", true, nil]})
      assert result == "x[4]: 1,hello,true,null"
    end

    test "tab delimiter for inline array" do
      {:ok, result} = ToonEx.encode(%{"x" => [1, 2, 3]}, delimiter: "\t")
      assert result == "x[3\t]: 1\t2\t3"
    end

    test "pipe delimiter for inline array" do
      {:ok, result} = ToonEx.encode(%{"x" => ["a", "b"]}, delimiter: "|")
      assert result == "x[2|]: a|b"
    end

    test "length_marker prefix" do
      {:ok, result} = ToonEx.encode(%{"x" => [1, 2]}, length_marker: "#")
      assert result == "x[#2]: 1,2"
    end
  end

  describe "tabular array encoding" do
    test "uniform object array uses tabular format" do
      data = [%{"name" => "Alice", "age" => 30}, %{"name" => "Bob", "age" => 25}]
      {:ok, result} = ToonEx.encode(%{"users" => data})
      assert String.contains?(result, "]{")
      {:ok, decoded} = ToonEx.decode(result)
      assert decoded["users"] == data
    end

    test "tabular header sorts fields alphabetically by default" do
      data = [%{"z" => 1, "a" => 2}]
      {:ok, result} = ToonEx.encode(%{"rows" => data})
      assert result =~ "{a,z}:"
    end

    test "tabular with null values" do
      data = [%{"x" => nil, "y" => 1}]
      {:ok, result} = ToonEx.encode(%{"rows" => data})
      assert String.contains?(result, "null")
    end

    test "non-uniform object array uses list format" do
      data = [%{"a" => 1}, %{"b" => 2}]
      {:ok, result} = ToonEx.encode(%{"items" => data})
      refute String.contains?(result, "]{")
      assert String.contains?(result, "- ")
    end

    test "encodes mixed objects" do
      data =
        [
          %{
            data: [
              %{
                "index" => 0,
                "timestamp" => 259
              },
              %{
                "id" => "abc",
                "timestamp" => 1257
              }
            ]
          }
        ]

      expected_toon = """
      [1]:
        - data[2]:
            - index: 0
              timestamp: 259
            - id: abc
              timestamp: 1257
      """

      # TOON spec Section 12: no trailing newline at end of document
      assert String.trim_trailing(expected_toon) == ToonEx.encode!(data)
    end

    test "encodes mixed object 2" do
      data = [
        "info",
        %{
          "id" => "908d993a-5c16-4bdf-b94d-76e559809eb5",
          "name" => "Test",
          "list" => [
            "019d3c0e-0833-72c4-b53e-04d6b79f3ff3"
          ],
          "status" => %{
            "time" => "2026-04-01T13:33:14.956244Z"
          }
        }
      ]

      expected_toon = """
      [2]:
        - info
        - id: 908d993a-5c16-4bdf-b94d-76e559809eb5
          name: Test
          list[1]: 019d3c0e-0833-72c4-b53e-04d6b79f3ff3
          status:
            time: "2026-04-01T13:33:14.956244Z"
      """

      # TOON spec Section 12: no trailing newline at end of document
      assert String.trim_trailing(expected_toon) == ToonEx.encode!(data)
    end

    test "encodes mixed object 3" do
      data = [
        "test",
        %{
          "async" => false,
          success: true,
          result: [
            %{
              "name" => "Layla Gibson",
              "user_id" => "019d3c0e-0997-7e80-9bd3-024865090b15",
              "username" => "user_89"
            },
            %{
              "name" => "Annabelle Jaskolski",
              "user_id" => "019d3c0e-096e-70ac-bcab-39f6ccc7f77c",
              "username" => "user_68"
            },
            %{
              "name" => "Mrs. Saige Cassin V",
              "user_id" => "019d3c0e-092e-794b-b233-10c9557bf2a9",
              "username" => "user_44"
            }
          ]
        }
      ]

      expected_toon = """
      [2]:
        - test
        - async: false
          success: true
          result[3]{name,user_id,username}:
            Layla Gibson,019d3c0e-0997-7e80-9bd3-024865090b15,user_89
            Annabelle Jaskolski,019d3c0e-096e-70ac-bcab-39f6ccc7f77c,user_68
            Mrs. Saige Cassin V,019d3c0e-092e-794b-b233-10c9557bf2a9,user_44
      """

      # TOON spec Section 12: no trailing newline at end of document
      assert String.trim_trailing(expected_toon) == ToonEx.encode!(data)
    end

    test "object array with nested values uses list format" do
      data = [%{"id" => 1, "meta" => %{"x" => 1}}, %{"id" => 2, "meta" => %{"x" => 2}}]
      {:ok, result} = ToonEx.encode(%{"items" => data})
      assert String.contains?(result, "- ")
    end
  end

  describe "list array encoding" do
    test "list of mixed types uses list format" do
      data = [1, "hello", %{"x" => 1}]
      {:ok, result} = ToonEx.encode(%{"items" => data})
      assert String.contains?(result, "- ")
    end

    test "list of objects with same keys but nested values" do
      data = [%{"a" => [1, 2]}, %{"a" => [3, 4]}]
      {:ok, result} = ToonEx.encode(%{"items" => data})
      assert String.contains?(result, "- ")
    end
  end

  # ── root-level array encoding ─────────────────────────────────────────────

  describe "root-level array encoding" do
    test "root empty array" do
      {:ok, result} = ToonEx.encode([])
      assert result == "[0]:"
    end

    test "root inline primitive array" do
      {:ok, result} = ToonEx.encode([1, 2, 3])
      assert result == "[3]: 1,2,3"
    end

    test "root tabular array" do
      data = [%{"name" => "Alice", "age" => 30}]
      {:ok, result} = ToonEx.encode(data)
      assert result =~ "[1]{"
    end

    test "root list array of objects" do
      data = [%{"a" => 1}, %{"b" => 2}]
      {:ok, result} = ToonEx.encode(data)
      assert result =~ "- "
    end
  end

  # ── options validation ───────────────────────────────────────────────────────

  describe "options validation" do
    test "invalid indent raises" do
      assert {:error, _} = ToonEx.encode(%{}, indent: 0)
    end

    test "invalid delimiter raises" do
      assert {:error, _} = ToonEx.encode(%{}, delimiter: ";")
    end

    test "empty delimiter raises" do
      assert {:error, _} = ToonEx.encode(%{}, delimiter: "")
    end

    test "multi-char delimiter raises" do
      assert {:error, _} = ToonEx.encode(%{}, delimiter: ",,")
    end

    test "unknown option raises" do
      assert {:error, _} = ToonEx.encode(%{}, unknown_opt: true)
    end
  end

  # ── fragment encoding ─────────────────────────────────────────────────────────

  describe "fragment encoding" do
    test "fragment with primitive value" do
      fragment = ToonEx.Fragment.new("hello")
      assert {:ok, "hello"} = ToonEx.encode(fragment)
    end

    test "fragment with map value" do
      fragment = ToonEx.Fragment.new("a: 1")
      assert {:ok, "a: 1"} = ToonEx.encode(fragment)
    end

    test "fragment with lazy encoding function" do
      fragment = ToonEx.Fragment.new(fn _opts -> "name: Alice" end)
      assert {:ok, "name: Alice"} = ToonEx.encode(fragment)
    end
  end

  # ── complex nested encoding ───────────────────────────────────────────────────

  describe "complex nested encoding" do
    test "deeply nested map" do
      data = %{"a" => %{"b" => %{"c" => %{"d" => "deep"}}}}
      {:ok, result} = ToonEx.encode(data)
      assert result =~ "a:"
      assert result =~ "b:"
      assert result =~ "c:"
      assert result =~ "d: deep"
    end

    test "array of mixed types" do
      data = [1, "two", true, nil, 3.14]
      {:ok, result} = ToonEx.encode(data)
      assert result =~ "[5]:"
    end

    test "map with special characters in values" do
      data = %{"key" => "value with: colon and, comma"}
      {:ok, result} = ToonEx.encode(data)
      assert result =~ "key:"
    end

    test "nested arrays" do
      data = [[1, 2], [3, 4]]
      {:ok, result} = ToonEx.encode(data)
      assert result =~ "["
    end

    test "empty map value" do
      data = %{"empty" => %{}}
      {:ok, result} = ToonEx.encode(data)
      assert result =~ "empty:"
    end

    test "map with float values" do
      data = %{"a" => 1.5, "b" => 2.0, "c" => -3.14}
      {:ok, result} = ToonEx.encode(data)
      assert result =~ "a: 1.5"
      assert result =~ "b: 2"
      assert result =~ "c: -3.14"
    end

    test "map with boolean values" do
      data = %{"active" => true, "deleted" => false}
      {:ok, result} = ToonEx.encode(data)
      assert result =~ "active: true"
      assert result =~ "deleted: false"
    end

    test "map with nil value" do
      data = %{"missing" => nil}
      {:ok, result} = ToonEx.encode(data)
      assert result =~ "missing: null"
    end

    test "list of primitives" do
      data = ["a", "b", "c"]
      {:ok, result} = ToonEx.encode(data)
      assert result =~ "[3]:"
    end

    test "list of objects with same keys" do
      data = [%{"id" => 1, "name" => "Alice"}, %{"id" => 2, "name" => "Bob"}]
      {:ok, result} = ToonEx.encode(data)
      assert result =~ "["
    end
  end

  # ── error handling ─────────────────────────────────────────────────────────────

  describe "error handling" do
    test "encode with invalid options returns error" do
      assert {:error, _} = ToonEx.encode(%{}, indent: -1)
    end
  end

  # ── encode_to_iodata! ────────────────────────────────────────────────────────

  describe "encode_to_iodata!" do
    test "encodes map to iodata" do
      result = ToonEx.encode_to_iodata!(%{"a" => 1})
      assert IO.iodata_to_binary(result) == "a: 1"
    end

    test "encodes list to iodata" do
      result = ToonEx.encode_to_iodata!([1, 2, 3])
      assert IO.iodata_to_binary(result) == "[3]: 1,2,3"
    end

    test "encodes primitive to iodata" do
      assert IO.iodata_to_binary(ToonEx.encode_to_iodata!("hello")) == "hello"
    end

    test "encodes fragment to iodata" do
      fragment = ToonEx.Fragment.new("name: Alice")
      assert IO.iodata_to_binary(ToonEx.encode_to_iodata!(fragment)) == "name: Alice"
    end

    test "raises on invalid options" do
      assert_raise ToonEx.EncodeError, fn ->
        ToonEx.encode_to_iodata!(%{}, indent: -1)
      end
    end
  end

  # ── tuple list encoding ──────────────────────────────────────────────────────

  describe "tuple list encoding" do
    test "encodes empty list as empty array" do
      {:ok, result} = ToonEx.encode([])
      assert result == "[0]:"
    end
  end

  # ── fragment at top level ────────────────────────────────────────────────────

  describe "fragment at top level" do
    test "encodes fragment with valid options" do
      fragment = ToonEx.Fragment.new("key: value")
      assert {:ok, "key: value"} = ToonEx.encode(fragment)
    end

    test "encodes fragment with custom options" do
      fragment = ToonEx.Fragment.new("key: value")
      assert {:ok, "key: value"} = ToonEx.encode(fragment, indent: 4)
    end

    test "fragment with encoding error returns error" do
      fragment = %ToonEx.Fragment{encode: fn _opts -> raise "encoding failed" end}
      assert {:error, _} = ToonEx.encode(fragment)
    end
  end
end
