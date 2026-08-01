defmodule ToonEx.Decode.ArraysTest do
  use ExUnit.Case, async: true

  # ── inline arrays (key[N]: v1,v2) ───────────────────────────────────────────

  describe "inline arrays — comma delimiter" do
    test "empty inline array" do
      assert {:ok, %{"x" => []}} = ToonEx.decode("x[0]:")
    end

    test "single-element array" do
      assert {:ok, %{"x" => ["a"]}} = ToonEx.decode("x[1]: a")
    end

    test "multi-element primitive array" do
      assert {:ok, %{"tags" => ["a", "b", "c"]}} = ToonEx.decode("tags[3]: a,b,c")
    end

    test "integer array" do
      assert {:ok, %{"ns" => [1, 2, 3]}} = ToonEx.decode("ns[3]: 1,2,3")
    end

    test "simple array" do
      assert {:ok,
              %{
                "game_owners" => [
                  "019d3369-162f-7fa3-bf17-a13d09d5ca8b"
                ]
              }} = ToonEx.decode("game_owners[1]: 019d3369-162f-7fa3-bf17-a13d09d5ca8b")
    end

    test "mixed-type array" do
      assert {:ok, %{"x" => [1, "hello", true, nil]}} =
               ToonEx.decode("x[4]: 1,hello,true,null")
    end

    test "array with empty tokens" do
      assert {:ok, %{"x" => ["a", "", "c"]}} = ToonEx.decode("x[3]: a,,c")
    end

    test "spaces around comma are trimmed" do
      assert {:ok, %{"x" => ["a", "b"]}} = ToonEx.decode("x[2]: a , b")
    end

    test "length mismatch raises" do
      assert_raise ToonEx.DecodeError, fn -> ToonEx.decode!("x[3]: a,b") end
    end

    test "leading zeros in array elements are strings" do
      assert {:ok, %{"codes" => ["007", "042"]}} = ToonEx.decode("codes[2]: 007,042")
    end

    test "quoted strings in inline array" do
      assert {:ok, %{"x" => ["hello world", "b"]}} =
               ToonEx.decode(~s(x[2]: "hello world",b))
    end
  end

  describe "inline arrays — tab delimiter" do
    test "tab-delimited array" do
      assert {:ok, %{"x" => [1, 2, 3]}} = ToonEx.decode("x[3\t]: 1\t2\t3")
    end

    test "tab delimiter in header marker" do
      {:ok, result} = ToonEx.decode("x[2\t]: a\tb")
      assert result == %{"x" => ["a", "b"]}
    end
  end

  describe "inline arrays — pipe delimiter" do
    test "pipe-delimited array" do
      assert {:ok, %{"x" => ["a", "b", "c"]}} = ToonEx.decode("x[3|]: a|b|c")
    end
  end

  # ── tabular arrays (key[N]{fields}: rows) ───────────────────────────────────

  describe "tabular arrays" do
    test "basic tabular array" do
      toon = "users[2]{name,age}:\n  Alice,30\n  Bob,25"
      {:ok, result} = ToonEx.decode(toon)

      assert result["users"] == [
               %{"name" => "Alice", "age" => 30},
               %{"name" => "Bob", "age" => 25}
             ]
    end

    test "single-row tabular array" do
      toon = "users[1]{name,age}:\n  Alice,30"
      {:ok, result} = ToonEx.decode(toon)
      assert result["users"] == [%{"name" => "Alice", "age" => 30}]
    end

    test "tabular with null and boolean values" do
      toon = "rows[1]{a,b,c}:\n  null,true,false"
      {:ok, result} = ToonEx.decode(toon)
      assert hd(result["rows"]) == %{"a" => nil, "b" => true, "c" => false}
    end

    test "tabular row count mismatch raises" do
      toon = "users[3]{name,age}:\n  Alice,30\n  Bob,25"
      assert_raise ToonEx.DecodeError, fn -> ToonEx.decode!(toon) end
    end

    test "tabular column count mismatch raises" do
      toon = "users[1]{name,age}:\n  Alice,30,extra"
      assert_raise ToonEx.DecodeError, fn -> ToonEx.decode!(toon) end
    end

    test "tabular with tab delimiter" do
      # Fields in {a\tb} use the active delimiter (tab) per TOON spec Section 6.
      toon = "rows[1\t]{a\tb}:\n  1\t2"
      {:ok, result} = ToonEx.decode(toon)
      assert result["rows"] == [%{"a" => 1, "b" => 2}]
    end

    test "tabular with pipe delimiter" do
      # Fields in {a|b} use the active delimiter (pipe) per TOON spec Section 6.
      toon = "rows[1|]{a|b}:\n  x|y"
      {:ok, result} = ToonEx.decode(toon)
      assert result["rows"] == [%{"a" => "x", "b" => "y"}]
    end

    test "tabular with quoted field names" do
      toon = ~s(rows[1]{"full name",age}:\n  Alice Liddell,10)
      {:ok, result} = ToonEx.decode(toon)
      assert [row] = result["rows"]
      assert row["full name"] == "Alice Liddell"
    end

    test "keys: :atoms in tabular array" do
      toon = "rows[1]{name,age}:\n  Alice,30"
      {:ok, result} = ToonEx.decode(toon, keys: :atoms)
      assert hd(result[:rows]) == %{name: "Alice", age: 30}
    end

    test "blank line inside tabular raises in strict mode" do
      toon = "rows[2]{a,b}:\n  1,2\n\n  3,4"
      assert_raise ToonEx.DecodeError, fn -> ToonEx.decode!(toon, strict: true) end
    end
  end

  # ── list arrays (key[N]: with indented items) ───────────────────────────────

  describe "list arrays" do
    test "list of primitives" do
      toon = "items[3]:\n  - 1\n  - 2\n  - 3"
      assert {:ok, %{"items" => [1, 2, 3]}} = ToonEx.decode(toon)
    end

    test "list of strings" do
      toon = "tags[2]:\n  - elixir\n  - toon"
      assert {:ok, %{"tags" => ["elixir", "toon"]}} = ToonEx.decode(toon)
    end

    test "list of objects (non-uniform)" do
      toon = "items[2]:\n  - title: Book\n    price: 9\n  - title: Movie\n    duration: 120"
      {:ok, result} = ToonEx.decode(toon)
      assert length(result["items"]) == 2
      assert hd(result["items"])["title"] == "Book"
      assert hd(result["items"])["price"] == 9
    end

    test "list of uniform objects" do
      toon = "users[2]:\n  - name: Alice\n    age: 30\n  - name: Bob\n    age: 25"
      {:ok, result} = ToonEx.decode(toon)

      assert result["users"] == [
               %{"name" => "Alice", "age" => 30},
               %{"name" => "Bob", "age" => 25}
             ]
    end

    test "list with empty object item" do
      toon = "items[1]:\n  -"
      {:ok, result} = ToonEx.decode(toon)
      assert result["items"] == [%{}]
    end

    test "list length mismatch raises" do
      toon = "items[3]:\n  - a\n  - b"
      assert_raise ToonEx.DecodeError, fn -> ToonEx.decode!(toon) end
    end

    test "nested list inside list item" do
      toon = "outer[1]:\n  - tags[2]: a,b"
      {:ok, result} = ToonEx.decode(toon)
      assert result["outer"] == [%{"tags" => ["a", "b"]}]
    end

    test "list item with nested object" do
      toon = "items[1]:\n  - name: X\n    meta:\n      k: v"
      {:ok, result} = ToonEx.decode(toon)
      assert hd(result["items"]) == %{"name" => "X", "meta" => %{"k" => "v"}}
    end

    test "blank line inside list array raises in strict mode" do
      toon = "items[2]:\n  - a\n\n  - b"
      assert_raise ToonEx.DecodeError, fn -> ToonEx.decode!(toon, strict: true) end
    end
  end

  # ── root-level arrays ────────────────────────────────────────────────────────

  describe "root-level arrays" do
    test "root empty array" do
      assert {:ok, []} = ToonEx.decode("[0]:")
    end

    test "root inline array of primitives" do
      assert {:ok, [1, 2, 3]} = ToonEx.decode("[3]: 1,2,3")
    end

    test "root tabular array" do
      toon = "[2]{name,age}:\n  Alice,30\n  Bob,25"
      {:ok, result} = ToonEx.decode(toon)

      assert result == [
               %{"name" => "Alice", "age" => 30},
               %{"name" => "Bob", "age" => 25}
             ]
    end

    test "root list array of primitives" do
      toon = "[3]:\n  - a\n  - b\n  - c"
      assert {:ok, ["a", "b", "c"]} = ToonEx.decode(toon)
    end

    test "root list array of objects" do
      toon = "[2]:\n  - x: 1\n  - x: 2"
      {:ok, result} = ToonEx.decode(toon)
      assert result == [%{"x" => 1}, %{"x" => 2}]
    end

    test "root tab-delimited array" do
      assert {:ok, ["a", "b"]} = ToonEx.decode("[2\t]: a\tb")
    end

    test "root pipe-delimited array" do
      assert {:ok, ["a", "b"]} = ToonEx.decode("[2|]: a|b")
    end
  end

  # ── nested arrays ────────────────────────────────────────────────────────────

  describe "nested arrays" do
    test "array of arrays (inline)" do
      toon = "[2]:\n  - [2]: 1,2\n  - [2]: 3,4"
      assert {:ok, [[1, 2], [3, 4]]} = ToonEx.decode(toon)
    end

    test "empty nested array" do
      toon = "[1]:\n  - [0]:"
      assert {:ok, [[]]} = ToonEx.decode(toon)
    end

    test "deeply nested arrays" do
      toon = "[1]:\n  - [1]:\n    - [1]:\n      - deep"
      assert {:ok, [[["deep"]]]} = ToonEx.decode(toon)
    end

    test "sibling after nested array" do
      toon = "[2]:\n  - [1]:\n    - inner\n  - outer"
      assert {:ok, [["inner"], "outer"]} = ToonEx.decode(toon)
    end

    test "mixed empty and non-empty nested arrays" do
      toon = "[3]:\n  - [0]:\n  - [1]:\n    - 42\n  - [0]:"
      assert {:ok, [[], [42], []]} = ToonEx.decode(toon)
    end
  end

  describe "Phoenix serializer" do
    test "Channels serializer mesage" do
      toon =
        """
        [5]:
          - "1"
          - null
          - "test:019d3c0e-0833-72c4-b53e-04d6b79f4563"
          - get_friends_in_activity
          - "019d3c0e-0841-775e-baa6-db837e318ed4": 8e127d9d-beaf-45cd-b6db-04d6b79f4563
        """

      expected =
        [
          "1",
          nil,
          "test:019d3c0e-0833-72c4-b53e-04d6b79f4563",
          "get_friends_in_activity",
          %{
            "019d3c0e-0841-775e-baa6-db837e318ed4" => "8e127d9d-beaf-45cd-b6db-04d6b79f4563"
          }
        ]

      assert {:ok, ^expected} = ToonEx.decode(toon)
    end

    test "Channels serializer mesage 2" do
      toon =
        """
        [5]:
          - "1"
          - null
          - "test:019d3c0e-0833-72c4-b53e-04d6b79f4563"
          - get_friends_in_activity
          - "019d3c0e-0841-775e-baa6-db837e318ed4": "8e127d9d-beaf-45cd-b6db-04d6b79f4563"
        """

      expected =
        [
          "1",
          nil,
          "test:019d3c0e-0833-72c4-b53e-04d6b79f4563",
          "get_friends_in_activity",
          %{
            "019d3c0e-0841-775e-baa6-db837e318ed4" => "8e127d9d-beaf-45cd-b6db-04d6b79f4563"
          }
        ]

      assert {:ok, ^expected} = ToonEx.decode(toon)
    end

    test "Channels serializer mesage 3" do
      toon =
        """
        [5]:
          - "1"
          - null
          - "test:019d3c0e-0833-72c4-b53e-04d6b79f4563"
          - get_friends_in_activity
          - 019d3c0e-0841-775e-baa6-db837e318ed4: 8e127d9d-beaf-45cd-b6db-04d6b79f4563
        """

      expected =
        [
          "1",
          nil,
          "test:019d3c0e-0833-72c4-b53e-04d6b79f4563",
          "get_friends_in_activity",
          %{
            "019d3c0e-0841-775e-baa6-db837e318ed4" => "8e127d9d-beaf-45cd-b6db-04d6b79f4563"
          }
        ]

      assert {:ok, ^expected} = ToonEx.decode(toon)
    end
  end

  # ── edge cases for coverage ───────────────────────────────────────────────────

  describe "array edge cases for coverage" do
    test "root array with nested objects" do
      toon = """
      [2]:
        - a: 1
          b: 2
        - c: 3
          d: 4
      """

      assert {:ok, [%{"a" => 1, "b" => 2}, %{"c" => 3, "d" => 4}]} = ToonEx.decode(toon)
    end

    test "root array with mixed primitives and objects" do
      toon = """
      [3]:
        - "hello"
        - id: 42
        - true
      """

      assert {:ok, ["hello", %{"id" => 42}, true]} = ToonEx.decode(toon)
    end

    test "root array with empty objects" do
      toon = """
      [2]:
        -
        -
      """

      assert {:ok, [%{}, %{}]} = ToonEx.decode(toon)
    end

    test "root array with nested array" do
      toon = """
      [2]:
        - [2]: 1,2
        - [2]: 3,4
      """

      assert {:ok, [[1, 2], [3, 4]]} = ToonEx.decode(toon)
    end

    test "root array with nested keyed array" do
      toon = """
      [1]:
        - items[2]: a,b
      """

      assert {:ok, [%{"items" => ["a", "b"]}]} = ToonEx.decode(toon)
    end

    test "root array with nested tabular array" do
      toon = """
      [1]:
        - data[2]{x,y}:
            1,2
            3,4
      """

      assert {:ok, [%{"data" => [%{"x" => 1, "y" => 2}, %{"x" => 3, "y" => 4}]}]} =
               ToonEx.decode(toon)
    end

    test "root array with deeply nested structure" do
      toon = """
      [1]:
        - outer:
            inner:
              deep: value
      """

      assert {:ok, [%{"outer" => %{"inner" => %{"deep" => "value"}}}]} =
               ToonEx.decode(toon)
    end

    test "root array with sibling fields on list items" do
      toon = """
      [1]:
        - matrix[2]:
            - [2]: 1,2
            - [2]: 3,4
          name: grid
      """

      assert {:ok, [%{"matrix" => [[1, 2], [3, 4]], "name" => "grid"}]} =
               ToonEx.decode(toon)
    end

    test "root array with blank lines between items (non-strict)" do
      toon = """
      [2]:
        - a: 1

        - b: 2
      """

      assert {:ok, [%{"a" => 1}, %{"b" => 2}]} = ToonEx.decode(toon, strict: false)
    end

    test "root array with blank lines between fields (non-strict)" do
      toon = """
      [1]:
        - a: 1

          b: 2
      """

      assert {:ok, [%{"a" => 1, "b" => 2}]} = ToonEx.decode(toon, strict: false)
    end
  end
end
