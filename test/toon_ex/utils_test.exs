defmodule ToonEx.UtilsTest do
  use ExUnit.Case, async: true

  alias ToonEx.Utils

  describe "list?/1" do
    test "returns true for empty list" do
      assert Utils.list?([]) == true
    end

    test "returns true for non-empty list" do
      assert Utils.list?([1, 2, 3]) == true
    end

    test "returns false for non-list values" do
      assert Utils.list?(nil) == false
      assert Utils.list?("string") == false
      assert Utils.list?(42) == false
      assert Utils.list?(%{}) == false
      assert Utils.list?({1, 2}) == false
    end
  end

  describe "all_primitives?/1" do
    test "returns true for list of primitives" do
      assert Utils.all_primitives?([1, "a", true, nil, 3.14]) == true
    end

    test "returns false when list contains maps" do
      assert Utils.all_primitives?([1, %{}]) == false
    end

    test "returns false when list contains lists" do
      assert Utils.all_primitives?([1, []]) == false
    end

    test "returns true for empty list" do
      assert Utils.all_primitives?([]) == true
    end
  end

  test "negative zero normalizes to integer 0" do
    result = ToonEx.Utils.normalize(-0.0)
    assert result === 0
    refute is_float(result)
  end
end
