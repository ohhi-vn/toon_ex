defmodule ToonEx.Btoon.TypesDictionaryConstantsTest do
  use ExUnit.Case, async: true

  alias ToonEx.Btoon

  alias ToonEx.Btoon.{
    Binary,
    Constants,
    Dictionary,
    ElementType,
    Encode,
    ObjectTable,
    Schema,
    TypedArray
  }

  describe "Binary" do
    test "new/1 and data/1" do
      b = Binary.new(<<1, 2, 3>>)
      assert %Binary{} = b
      assert Binary.data(b) == <<1, 2, 3>>
    end
  end

  describe "TypedArray" do
    test "new/2 stores type and buffer, exposes accessors" do
      data = <<1::32-little, 2::32-little>>
      ta = TypedArray.new(:int32, data)

      assert TypedArray.type(ta) == :int32
      assert TypedArray.data(ta) == data
      assert TypedArray.to_list(ta) == [1, 2]
      assert TypedArray.length(ta) == 2
    end

    test "from_list/1 builds a typed array from values" do
      ta = TypedArray.from_list([1.5, 2.5])
      assert TypedArray.length(ta) == 2
    end
  end

  describe "ObjectTable" do
    test "Column struct holds name/type/data" do
      col = %ObjectTable.Column{name: "x", type: :int32, data: <<1::32-little>>}

      assert col.name == "x"
      assert col.type == :int32
    end

    test "from_rows/1 and rows/1 round-trip numeric columns" do
      table =
        ObjectTable.from_rows([
          %{"x" => 1, "y" => 2},
          %{"x" => 3, "y" => 4}
        ])

      assert table.row_count == 2

      rows = ObjectTable.rows(table)
      assert rows == [%{"x" => 1, "y" => 2}, %{"x" => 3, "y" => 4}]
    end
  end

  describe "Dictionary" do
    test "new/1 builds lookup index; ref/2 resolves entries by id" do
      dict = Dictionary.new(["player", "position"])

      assert Dictionary.size(dict) == 2
      assert Dictionary.member?(dict, "player")
      refute Dictionary.member?(dict, "unknown")

      id = Dictionary.ref(dict, "player")
      assert is_integer(id)
      assert is_integer(Dictionary.ref(dict, "position"))

      assert Dictionary.entries(dict) == ["player", "position"]
      assert is_tuple(Dictionary.entries_tuple(dict))
    end

    test "ref/2 returns nil for unknown strings" do
      dict = Dictionary.new(["a"])
      assert Dictionary.ref(dict, "missing") == nil
    end

    test "persistent_term storage round-trip" do
      key = {:test_session_dict, make_ref()}
      dict = Dictionary.new(["k1", "k2"])

      assert Dictionary.put_persistent(key, dict) == :ok
      assert Dictionary.get_persistent(key) == {:ok, dict}

      assert Dictionary.delete_persistent(key)
      assert_raise ArgumentError, fn -> Dictionary.get_persistent(key) end
    end
  end

  describe "Constants accessors" do
    test "magic and header layout" do
      assert Constants.magic() == "BTON"
      assert is_integer(Constants.version())
      assert Constants.header_size() >= 6
      assert Constants.reserved() == 0
    end

    test "flags are unique bits" do
      flags = [
        Constants.flag_schema(),
        Constants.flag_string_table(),
        Constants.flag_session_dictionary(),
        Constants.flag_no_string_table(),
        Constants.flag_schema_id_uint16()
      ]

      assert Enum.uniq(flags) == flags
      assert Enum.all?(flags, fn f -> is_integer(f) and f > 0 end)
    end

    test "tags are unique bytes" do
      tags = [
        Constants.tag_null(),
        Constants.tag_false(),
        Constants.tag_true(),
        Constants.tag_int32(),
        Constants.tag_int64(),
        Constants.tag_float32(),
        Constants.tag_float64(),
        Constants.tag_string(),
        Constants.tag_binary(),
        Constants.tag_array(),
        Constants.tag_object(),
        Constants.tag_string_ref(),
        Constants.tag_typed_array(),
        Constants.tag_object_table()
      ]

      assert length(tags) == Enum.uniq(tags) |> length()
    end

    test "smallint encoding window constants are coherent" do
      assert Constants.smallint_min() == -32
      assert Constants.smallint_max() == 95
      assert Constants.smallint_bias() == 64
      # value + bias must land inside [first, last]
      assert Constants.smallint_min() + Constants.smallint_bias() ==
               Constants.smallint_first()

      assert Constants.smallint_max() + Constants.smallint_bias() ==
               Constants.smallint_last()
    end

    test "element type bytes are unique" do
      bytes = [
        Constants.element_int8(),
        Constants.element_uint8(),
        Constants.element_int16(),
        Constants.element_uint16(),
        Constants.element_int32(),
        Constants.element_uint32(),
        Constants.element_int64(),
        Constants.element_uint64(),
        Constants.element_float32(),
        Constants.element_float64()
      ]

      assert length(bytes) == Enum.uniq(bytes) |> length()
    end
  end

  describe "encode options validation" do
    test "rejects non-keyword lists" do
      assert Encode.Options.validate(%{"not" => "keyword"}) ==
               {:error, "options must be a keyword list"}
    end

    test "rejects unknown keys" do
      assert {:error, msg} = Encode.Options.validate(compiled_schema: %{})
      assert msg =~ "unknown encoding option"
    end

    test "rejects invalid values" do
      assert {:error, _} = Encode.Options.validate(string_table: :banana)
      assert {:error, _} = Encode.Options.validate(typed_arrays: "yes")
      assert {:error, _} = Encode.Options.validate(no_string_table: "yes")
      assert {:error, _} = Encode.Options.validate(schema_id_uint16: "yes")
      assert {:error, _} = Encode.Options.validate(object_tables: "yes")
      assert {:error, _} = Encode.Options.validate(dictionary: %{not: :dict})
      assert {:error, _} = Encode.Options.validate(schema: %{not: :schema})
    end

    test "validate!/1 raises on errors" do
      assert_raise ArgumentError, fn ->
        Encode.Options.validate!(banana: true)
      end
    end

    test "schema_id_uint16 requires a schema" do
      assert_raise ArgumentError, ~r/requires a schema/i, fn ->
        Encode.Options.validate!(schema_id_uint16: true)
      end
    end

    test "schema_id_uint16 rejects ids above 65535" do
      schema = Schema.new(65_536, "Big", [])

      assert_raise ArgumentError, ~r/0\.\.65535/, fn ->
        Encode.Options.validate!(schema: schema, schema_id_uint16: true)
      end
    end

    test "defaults are returned for empty options" do
      assert Encode.Options.validate([]) == {:ok, Encode.Options.defaults()}
      assert Btoon.Decode.Options.defaults() == Btoon.Decode.Options.defaults()
    end
  end

  describe "decode options validation" do
    test "non-keyword opts produce a decode error" do
      assert {:error, %ToonEx.Btoon.DecodeError{}} = Btoon.decode(<<1>>, %{bad: :opts})
    end

    test "defaults expose a map of validated values" do
      assert is_map(Btoon.Decode.Options.defaults())
    end
  end
end
