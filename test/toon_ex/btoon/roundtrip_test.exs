defmodule ToonEx.Btoon.RoundtripTest do
  use ExUnit.Case, async: true

  alias ToonEx.Btoon

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
            Btoon.Binary.new(<<0, 1, 255, 254>>)
          ] do
        assert Btoon.decode!(Btoon.encode!(value)) == value
      end
    end
  end

  describe "collections" do
    test "arrays" do
      assert Btoon.decode!(Btoon.encode!([])) == []
      assert Btoon.decode!(Btoon.encode!([1, 2, 3])) == [1, 2, 3]
      assert Btoon.decode!(Btoon.encode!([1, 300])) == [1, 300]
      assert Btoon.decode!(Btoon.encode!([1.5, 2.5])) == [1.5, 2.5]
      assert Btoon.decode!(Btoon.encode!(["a", "b", "a"])) == ["a", "b", "a"]
    end

    test "mixed arrays use the general array tag" do
      value = [1, "two", 3.0, true, nil]
      assert Btoon.decode!(Btoon.encode!(value)) == value
    end

    test "maps" do
      value = %{
        "name" => "Alice",
        "age" => 30,
        "scores" => [1, 2, 3],
        "meta" => %{"nested" => true},
        "blob" => Btoon.Binary.new(<<9, 8, 7>>)
      }

      assert Btoon.decode!(Btoon.encode!(value)) == value
    end

    test "deeply nested values" do
      value = %{
        "a" => [
          %{"b" => [%{"c" => %{"d" => [1, 2, %{"e" => nil}]}}]}
        ]
      }

      assert Btoon.decode!(Btoon.encode!(value)) == value
    end
  end

  describe "string table round trips" do
    test "StringRefs resolve back to their strings" do
      value = %{"player" => "hero", "npc" => "hero", "key" => "player"}
      assert Btoon.decode!(Btoon.encode!(value)) == value
    end

    test "session dictionary refs resolve" do
      dict = Btoon.Dictionary.new(["player", "position", "velocity"])
      value = %{"player" => 1, "position" => [1.0, 2.0], "velocity" => [3.0, 4.0]}

      assert Btoon.decode!(Btoon.encode!(value, dictionary: dict), dictionary: dict) ==
               value
    end

    test "table entries layer on top of session dictionary ids" do
      dict = Btoon.Dictionary.new(["shared"])
      value = %{"shared" => %{"unique" => "string", "other" => "string"}}

      assert Btoon.decode!(Btoon.encode!(value, dictionary: dict), dictionary: dict) ==
               value
    end

    test "no_string_table uses inline strings and preserves dictionary refs" do
      dict = Btoon.Dictionary.new(["known"])
      value = %{"known" => "value", "other" => "inline"}
      bin = Btoon.encode!(value, dictionary: dict, no_string_table: true)

      assert :binary.at(bin, 5) == 0x18
      assert Btoon.decode!(bin, dictionary: dict) == value
    end
  end

  describe "object keys" do
    test "keys option converts to atoms" do
      value = %{"name" => "Alice"}
      bin = Btoon.encode!(value)

      assert Btoon.decode!(bin, keys: :atoms) == %{name: "Alice"}
    end

    test "decoder enforces configured string and container limits" do
      string_bin = Btoon.encode!("hello", string_table: :off)

      assert {:error, %Btoon.DecodeError{reason: :max_string_size}} =
               Btoon.decode(string_bin, max_string_size: 3)

      array_bin = Btoon.encode!([1, 2, 3], typed_arrays: false)

      assert {:error, %Btoon.DecodeError{reason: :max_container_count}} =
               Btoon.decode(array_bin, max_container_count: 2)
    end
  end
end
