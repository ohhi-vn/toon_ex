defmodule ToonEx.Btoon.RoundtripTest do
  use ExUnit.Case, async: true

  describe "primitives" do
    test "round trips every primitive type" do
      for value <- [
            nil,
            true,
            false,
            -32,
            -1,
            0,
            1,
            95,
            96,
            2_147_483_647,
            -2_147_483_648,
            2_147_483_648,
            9_223_372_036_854_775_807,
            -9_223_372_036_854_775_808,
            1.5,
            1.1,
            3.14159265358979,
            "",
            "hello world",
            "日本語のテキスト",
            ToonEx.Btoon.Binary.new(<<0, 1, 255, 254>>)
          ] do
        assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(value)) == value
      end
    end
  end

  describe "collections" do
    test "arrays" do
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!([])) == []
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!([1, 2, 3])) == [1, 2, 3]
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!([1, 300])) == [1, 300]
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!([1.5, 2.5])) == [1.5, 2.5]
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(["a", "b", "a"])) == ["a", "b", "a"]
    end

    test "mixed arrays use the general array tag" do
      value = [1, "two", 3.0, true, nil]
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(value)) == value
    end

    test "maps" do
      value = %{
        "name" => "Alice",
        "age" => 30,
        "scores" => [1, 2, 3],
        "meta" => %{"nested" => true},
        "blob" => ToonEx.Btoon.Binary.new(<<9, 8, 7>>)
      }

      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(value)) == value
    end

    test "deeply nested values" do
      value = %{
        "a" => [
          %{"b" => [%{"c" => %{"d" => [1, 2, %{"e" => nil}]}}]}
        ]
      }

      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(value)) == value
    end
  end

  describe "string table round trips" do
    test "StringRefs resolve back to their strings" do
      value = %{"player" => "hero", "npc" => "hero", "key" => "player"}
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(value)) == value
    end

    test "session dictionary refs resolve" do
      dict = ToonEx.Btoon.Dictionary.new(["player", "position", "velocity"])
      value = %{"player" => 1, "position" => [1.0, 2.0], "velocity" => [3.0, 4.0]}

      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(value, dictionary: dict), dictionary: dict) ==
               value
    end

    test "table entries layer on top of session dictionary ids" do
      dict = ToonEx.Btoon.Dictionary.new(["shared"])
      value = %{"shared" => %{"unique" => "string", "other" => "string"}}

      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(value, dictionary: dict), dictionary: dict) ==
               value
    end
  end

  describe "object keys" do
    test "keys option converts to atoms" do
      value = %{"name" => "Alice"}
      bin = ToonEx.Btoon.encode!(value)

      assert ToonEx.Btoon.decode!(bin, keys: :atoms) == %{name: "Alice"}
    end
  end
end
