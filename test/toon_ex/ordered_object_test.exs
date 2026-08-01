defmodule ToonEx.OrderedObjectTest do
  use ExUnit.Case, async: true

  alias ToonEx.OrderedObject

  defp ordered(pairs), do: OrderedObject.new(pairs)

  describe "root object key order" do
    test "preserves declared key order" do
      obj = ordered([{"id", 123}, {"name", "Ada"}, {"active", true}])

      assert {:ok, "id: 123\nname: Ada\nactive: true"} = ToonEx.encode(obj)
    end

    test "reverses order when declared reversed" do
      obj = ordered([{"active", true}, {"name", "Ada"}, {"id", 123}])

      assert {:ok, "active: true\nname: Ada\nid: 123"} = ToonEx.encode(obj)
    end

    test "works through encode!/2" do
      assert "a: 1\nb: 2" = ToonEx.encode!(ordered([{"a", 1}, {"b", 2}]))
    end

    test "empty ordered object normalizes to empty object" do
      assert {:ok, ""} = ToonEx.encode(ordered([]))
    end
  end

  describe "nested ordered objects" do
    test "preserves nested key order" do
      obj = ordered([{"outer", ordered([{"z", 1}, {"a", 2}])}])

      assert {:ok, "outer:\n  z: 1\n  a: 2"} = ToonEx.encode(obj)
    end

    test "mixes plain maps and ordered objects" do
      obj = ordered([{"first", %{"b" => 1, "a" => 2}}, {"second", ordered([{"y", 3}])}])

      assert {:ok, "first:\n  a: 2\n  b: 1\nsecond:\n  y: 3"} = ToonEx.encode(obj)
    end
  end

  describe "tabular arrays" do
    test "header uses first item's declared key order" do
      rows = [ordered([{"name", "Ada"}, {"age", 30}]), ordered([{"name", "Bob"}, {"age", 25}])]

      assert {:ok, "users[2]{name,age}:\n  Ada,30\n  Bob,25"} = ToonEx.encode(%{"users" => rows})
    end

    test "root tabular array preserves declared key order" do
      rows = [ordered([{"name", "Ada"}, {"age", 30}]), ordered([{"name", "Bob"}, {"age", 25}])]

      assert {:ok, "[2]{name,age}:\n  Ada,30\n  Bob,25"} = ToonEx.encode(rows)
    end
  end

  describe "keyed tabular" do
    test "uses first entry value's declared key order" do
      obj =
        ordered([
          {"a", ordered([{"x", 1}, {"y", 2}])},
          {"b", ordered([{"y", 4}, {"x", 3}])}
        ])

      assert {:ok, "m[2:]{x,y}:\n  a: 1,2\n  b: 3,4"} = ToonEx.encode(%{"m" => obj})
    end
  end

  describe "key_order interplay" do
    test "key_order overrides declared order when it covers all keys" do
      obj = ordered([{"id", 1}, {"name", "Ada"}])

      assert {:ok, "name: Ada\nid: 1"} = ToonEx.encode(obj, key_order: ["name", "id"])
    end

    test "declared order wins when key_order does not cover all keys" do
      obj = ordered([{"id", 1}, {"name", "Ada"}, {"active", true}])

      assert {:ok, "id: 1\nname: Ada\nactive: true"} = ToonEx.encode(obj, key_order: ["name"])
    end
  end

  describe "list items" do
    test "empty ordered object list items render as bare hyphen" do
      items = ["first", "second", ordered([])]

      assert {:ok, "items[3]:\n  - first\n  - second\n  -"} = ToonEx.encode(%{"items" => items})
    end

    test "ordered object list items preserve declared order" do
      items = [ordered([{"b", 2}, {"a", 1}])]

      assert {:ok, "items[1]{b,a}:\n  2,1"} = ToonEx.encode(%{"items" => items})
    end
  end

  describe "normalization" do
    test "empty ordered object normalizes to empty map" do
      assert ToonEx.Utils.normalize(ordered([])) == %{}
    end

    test "non-empty ordered object is preserved through normalization" do
      normalized = ToonEx.Utils.normalize(ordered([{"a", 1}]))

      assert %ToonEx.OrderedObject{values: [{"a", 1}]} = normalized
    end

    test "ordered helpers" do
      obj = ordered([{"a", 1}, {"b", 2}])

      assert ToonEx.Utils.object_keys(obj) == ["a", "b"]
      assert ToonEx.Utils.object_size(obj) == 2
      assert ToonEx.Utils.object_get(obj, "b") == 2
      assert ToonEx.Utils.object_to_list(obj) == [{"a", 1}, {"b", 2}]
      assert ToonEx.Utils.object_has_key?(obj, "a")
      refute ToonEx.Utils.object_has_key?(obj, "z")
    end
  end
end
