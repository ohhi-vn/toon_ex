defmodule ToonEx.MainTest do
  use ExUnit.Case, async: true

  describe "ToonEx main module public API" do
    test "encodes simple map" do
      assert {:ok, "name: Alice"} = ToonEx.encode(%{"name" => "Alice"})
    end

    test "encodes map with integer value" do
      assert {:ok, "age: 30"} = ToonEx.encode(%{"age" => 30})
    end

    test "encodes nested map" do
      assert {:ok, "user:\n  name: Bob"} = ToonEx.encode(%{"user" => %{"name" => "Bob"}})
    end

    test "encodes array with default options" do
      assert {:ok, "tags[2]: elixir,toon"} = ToonEx.encode(%{"tags" => ["elixir", "toon"]})
    end

    test "encodes with custom indent" do
      assert {:ok, "user:\n    name: Bob"} =
               ToonEx.encode(%{"user" => %{"name" => "Bob"}}, indent: 4)
    end

    test "encodes with tab delimiter" do
      assert {:ok, "tags[2\t]: elixir\ttoon"} =
               ToonEx.encode(%{"tags" => ["elixir", "toon"]}, delimiter: "\t")
    end

    test "encodes with pipe delimiter" do
      assert {:ok, "tags[2|]: elixir|toon"} =
               ToonEx.encode(%{"tags" => ["elixir", "toon"]}, delimiter: "|")
    end

    test "encodes with length marker" do
      assert {:ok, "tags[#2]: elixir,toon"} =
               ToonEx.encode(%{"tags" => ["elixir", "toon"]}, length_marker: "#")
    end

    test "encodes with key_folding safe" do
      assert {:ok, "user.name: Bob"} = ToonEx.encode(%{"user.name" => "Bob"}, key_folding: :safe)
    end

    test "encodes struct as map when no encoder" do
      struct = %{"__struct__" => MyApp.TestStruct, "value" => 42}
      assert {:ok, _} = ToonEx.encode(struct)
    end

    test "encodes simple map with encode!" do
      assert ToonEx.encode!(%{"name" => "Alice"}) == "name: Alice"
    end

    test "encodes array with encode!" do
      assert ToonEx.encode!(%{"tags" => ["a", "b"]}) == "tags[2]: a,b"
    end

    test "encodes nested object with encode!" do
      assert ToonEx.encode!(%{"user" => %{"name" => "Bob"}}) == "user:\n  name: Bob"
    end

    test "raises on struct without encoder when using encode_to_iodata!" do
      # encode_to_iodata! uses the Encoder protocol and fails for structs
      # without an implementation.
      struct = %ToonEx.Fixtures.StructWithoutEncoder{id: 1, value: "test"}
      assert_raise ToonEx.EncodeError, fn -> ToonEx.encode_to_iodata!(struct) end
    end

    test "returns iodata for simple map" do
      result = ToonEx.encode_to_iodata!(%{"name" => "Alice"})
      assert IO.iodata_to_binary(result) == "name: Alice"
    end

    test "returns iodata for array" do
      result = ToonEx.encode_to_iodata!(%{"tags" => ["a", "b"]})
      assert IO.iodata_to_binary(result) == "tags[2]: a,b"
    end

    test "decodes simple key-value" do
      assert {:ok, %{"name" => "Alice"}} = ToonEx.decode("name: Alice")
    end

    test "decodes array" do
      assert {:ok, %{"tags" => ["a", "b"]}} = ToonEx.decode("tags[2]: a,b")
    end

    test "decodes nested object" do
      assert {:ok, %{"user" => %{"name" => "Bob"}}} = ToonEx.decode("user:\n  name: Bob")
    end

    test "decodes with keys as atoms" do
      assert {:ok, %{name: "Alice"}} = ToonEx.decode("name: Alice", keys: :atoms)
    end

    test "decodes with keys as atoms!" do
      assert {:ok, %{name: "Alice"}} = ToonEx.decode("name: Alice", keys: :atoms!)
    end

    test "decodes with strict false" do
      assert {:ok, %{"name" => "Alice"}} = ToonEx.decode("name: Alice", strict: false)
    end

    test "decodes with custom indent size" do
      assert {:ok, %{"user" => %{"name" => "Bob"}}} =
               ToonEx.decode("user:\n    name: Bob", indent_size: 4)
    end

    test "decodes simple key-value with decode!" do
      assert ToonEx.decode!("name: Alice") == %{"name" => "Alice"}
    end

    test "decodes array with decode!" do
      assert ToonEx.decode!("tags[2]: a,b") == %{"tags" => ["a", "b"]}
    end

    test "decodes nested object with decode!" do
      assert ToonEx.decode!("user:\n  name: Bob") == %{"user" => %{"name" => "Bob"}}
    end
  end

  describe "ToonEx module exports" do
    test "encode function is exported" do
      functions = ToonEx.__info__(:functions)
      assert Enum.any?(functions, fn {name, _arity} -> name == :encode end)
    end

    test "encode! function is exported" do
      functions = ToonEx.__info__(:functions)
      assert Enum.any?(functions, fn {name, _arity} -> name == :encode! end)
    end

    test "decode function is exported" do
      functions = ToonEx.__info__(:functions)
      assert Enum.any?(functions, fn {name, _arity} -> name == :decode end)
    end

    test "decode! function is exported" do
      functions = ToonEx.__info__(:functions)
      assert Enum.any?(functions, fn {name, _arity} -> name == :decode! end)
    end

    test "encode_to_iodata! function is exported" do
      functions = ToonEx.__info__(:functions)
      assert Enum.any?(functions, fn {name, _arity} -> name == :encode_to_iodata! end)
    end
  end
end
