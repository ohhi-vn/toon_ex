defmodule ToonEx.Btoon.SchemaTest do
  use ExUnit.Case, async: true

  alias ToonEx.Btoon.Schema

  defp player_schema do
    Schema.new(100, "Player", [
      %{name: "id", type: :int32},
      %{name: "x", type: :float32},
      %{name: "y", type: :float32},
      %{name: "hp", type: :uint16},
      %{name: "alive", type: :bool},
      %{name: "name", type: :string},
      %{name: "note", type: :null},
      %{name: "inventory", type: :array},
      %{name: "meta", type: :object}
    ])
  end

  describe "schema mode round trip" do
    test "all field types" do
      value = %{
        "id" => 7,
        "x" => 1.5,
        "y" => -2.25,
        "hp" => 300,
        "alive" => true,
        "name" => "hero",
        "note" => nil,
        "inventory" => [1, 2, 3],
        "meta" => %{"level" => 99}
      }

      bin = ToonEx.Btoon.encode!(value, schema: player_schema())
      assert <<66, 84, 79, 78, 1, 6, 0, 0, _::binary>> = bin
      assert ToonEx.Btoon.decode!(bin) == value
    end

    test "string fields use StringRefs" do
      schema =
        Schema.new(1, "Named", [%{name: "name", type: :string}, %{name: "id", type: :int32}])

      value = %{"name" => "hero", "id" => 1}
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(value, schema: schema)) == value
    end

    test "negative and boundary integers" do
      schema =
        Schema.new(1, "Nums", [
          %{name: "a", type: :int8},
          %{name: "b", type: :uint8},
          %{name: "c", type: :int64},
          %{name: "d", type: :uint64},
          %{name: "e", type: :float64}
        ])

      value = %{
        "a" => -128,
        "b" => 255,
        "c" => -9_223_372_036_854_775_808,
        "d" => 18_446_744_073_709_551_615,
        "e" => 1.1
      }

      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(value, schema: schema)) == value
    end
  end

  describe "schema errors" do
    test "missing field raises" do
      assert_raise ToonEx.Btoon.EncodeError, fn ->
        ToonEx.Btoon.encode!(%{"id" => 1}, schema: player_schema())
      end
    end

    test "type mismatch raises" do
      assert_raise ToonEx.Btoon.EncodeError, fn ->
        ToonEx.Btoon.encode!(%{"name" => 42}, schema: player_schema())
      end
    end

    test "integer overflow raises" do
      schema = Schema.new(2, "T", [%{name: "v", type: :int8}])

      assert_raise ToonEx.Btoon.EncodeError, fn ->
        ToonEx.Btoon.encode!(%{"v" => 128}, schema: schema)
      end
    end

    test "schema mode requires a map" do
      assert_raise ToonEx.Btoon.EncodeError, fn ->
        ToonEx.Btoon.encode!([1], schema: player_schema())
      end
    end

    test "invalid schema field type raises" do
      schema = Schema.new(3, "Bad", [%{name: "v", type: :unknown}])

      assert_raise ToonEx.Btoon.EncodeError, fn ->
        ToonEx.Btoon.encode!(%{"v" => 1}, schema: schema)
      end
    end
  end

  describe "schema decode with out-of-band schema" do
    test "schema flag not set falls back to opts.schema" do
      schema = Schema.new(10, "P", [%{name: "a", type: :int32}, %{name: "b", type: :float32}])

      # Hand-crafted envelope: schema flag clear, body is a tagless schema body.
      bin =
        <<66, 84, 79, 78, 1, 0, 0, 0, 10, 0, 0, 0, 1, 0, 0, 0, 0, 0, 32, 64>>

      assert ToonEx.Btoon.decode!(bin, schema: schema) == %{"a" => 1, "b" => 2.5}
    end
  end

  describe "Schema struct" do
    test "accessors" do
      schema = player_schema()
      assert Schema.id(schema) == 100
      assert Schema.name(schema) == "Player"
      assert Schema.field_count(schema) == 9
      assert length(Schema.fields(schema)) == 9
    end
  end
end
