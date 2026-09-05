defmodule ToonEx.Btoon.SchemaEncodingTest do
  use ExUnit.Case, async: true

  alias ToonEx.Btoon
  alias ToonEx.Btoon.{Binary, Schema}

  defp roundtrip_with(schema, value, opts \\ []) do
    bin = Btoon.encode!(value, Keyword.put(opts, :schema, schema))
    Btoon.decode!(bin)
  end

  describe "schema body encoding via Btoon.encode!/2" do
    test "fixed-width integers at their range boundaries" do
      schema =
        Schema.new(1, "I", [
          %{name: "i8", type: :int8},
          %{name: "u8", type: :uint8},
          %{name: "i16", type: :int16},
          %{name: "u16", type: :uint16},
          %{name: "i32", type: :int32},
          %{name: "u32", type: :uint32},
          %{name: "i64", type: :int64},
          %{name: "u64", type: :uint64}
        ])

      value = %{
        "i8" => -128,
        "u8" => 255,
        "i16" => -32_768,
        "u16" => 65_535,
        "i32" => -2_147_483_648,
        "u32" => 4_294_967_295,
        "i64" => -9_223_372_036_854_775_808,
        "u64" => 18_446_744_073_709_551_615
      }

      assert roundtrip_with(schema, value) == value
    end

    test "float32 and float64 values" do
      schema =
        Schema.new(2, "F", [%{name: "f32", type: :float32}, %{name: "f64", type: :float64}])

      value = %{"f32" => 1.5, "f64" => -2.25}
      assert roundtrip_with(schema, value) == value
    end

    test "boolean and null fields" do
      schema =
        Schema.new(3, "BN", [
          %{name: "yes", type: :bool},
          %{name: "no", type: :bool},
          %{name: "nothing", type: :null}
        ])

      value = %{"yes" => true, "no" => false, "nothing" => nil}
      assert roundtrip_with(schema, value) == value
    end

    test "string fields deduplicate through the dictionary" do
      schema =
        Schema.new(4, "S", [
          %{name: "first", type: :string},
          %{name: "second", type: :string}
        ])

      value = %{"first" => "same", "second" => "same"}
      assert roundtrip_with(schema, value) == value
    end

    test "binary fields accept raw binaries and Binary structs" do
      schema =
        Schema.new(5, "B", [
          %{name: "raw", type: :binary},
          %{name: "wrapped", type: :binary}
        ])

      value = %{"raw" => <<1, 2, 3>>, "wrapped" => Binary.new(<<9, 8>>)}
      decoded = roundtrip_with(schema, value)

      assert %Binary{data: <<1, 2, 3>>} = decoded["raw"]
      assert %Binary{data: <<9, 8>>} = decoded["wrapped"]
    end

    test "array fields fall back to general encoding" do
      schema = Schema.new(6, "A", [%{name: "items", type: :array}])

      value = %{"items" => [1, "two", %{"k" => true}]}
      assert roundtrip_with(schema, value) == value
    end

    test "object fields encode nested maps with sorted keys" do
      schema = Schema.new(8, "O", [%{name: "meta", type: :object}])

      value = %{"meta" => %{"b" => 2, "a" => 1, "c" => [1, 2]}}
      assert roundtrip_with(schema, value) == value
    end

    test "typed arrays are used when enabled" do
      schema = Schema.new(9, "TA", [%{name: "nums", type: :array}])
      value = %{"nums" => [1, 2, 3, 4]}

      bin = Btoon.encode!(value, schema: schema, typed_arrays: true)

      assert Btoon.decode!(bin) == value
    end

    test "nested typed array buffers stay element-aligned" do
      # The float64 buffer must land on an 8-byte boundary within the
      # message regardless of the fields encoded before it (§16).
      schema =
        Schema.new(13, "Aligned", [
          %{name: "id", type: :int32},
          %{name: "label", type: :string},
          %{name: "nums", type: :array}
        ])

      value = %{"id" => 7, "label" => "abc", "nums" => [0.1, 0.2]}

      bin = Btoon.encode!(value, schema: schema)

      assert {:ok, %{"nums" => [0.1, 0.2]}} = Btoon.decode(bin)

      <<
        "BTON",
        1,
        0x06,
        0,
        0,
        1,
        0,
        0,
        0,
        3,
        0,
        0,
        0,
        "abc",
        _pad1::binary-size(5),
        _schema::binary-size(48),
        13,
        0,
        0,
        0,
        7,
        0,
        0,
        0,
        0x0B,
        0x40,
        0x0C,
        0x08,
        2,
        0,
        0,
        0,
        7,
        _pad::binary-size(7),
        rest::binary
      >> = bin

      assert rest == <<0.1::64-little-float, 0.2::64-little-float>>
    end

    test "object tables are used when enabled for uniform numeric rows" do
      schema = Schema.new(10, "OT", [%{name: "rows", type: :array}])

      rows = [
        %{"x" => 1.0, "y" => 2.0},
        %{"x" => 3.0, "y" => 4.0}
      ]

      value = %{"rows" => rows}

      bin =
        Btoon.encode!(value,
          schema: schema,
          object_tables: true
        )

      decoded = Btoon.decode!(bin)
      assert decoded["rows"] == rows
    end

    test "schema id uses the compact uint16 envelope when requested" do
      schema = Schema.new(42, "P", [%{name: "x", type: :int32}])

      bin = Btoon.encode!(%{"x" => 7}, schema: schema, schema_id_uint16: true)

      assert Btoon.decode!(bin) == %{"x" => 7}
    end

    test "atoms encode as strings in generic positions" do
      schema = Schema.new(11, "AT", [%{name: "v", type: :array}])
      value = %{"v" => [:ok, "raw"]}

      assert roundtrip_with(schema, value) == %{"v" => ["ok", "raw"]}
    end
  end

  describe "schema field errors" do
    defp encode_error_for(type, bad_value) do
      schema = Schema.new(99, "E", [%{name: "v", type: type}])

      assert_raise Btoon.EncodeError, fn ->
        Btoon.encode!(%{"v" => bad_value}, schema: schema)
      end
    end

    test "integer overflow beyond declared width raises" do
      encode_error_for(:int8, 128)
      encode_error_for(:int8, -129)
      encode_error_for(:uint8, 256)
      encode_error_for(:uint8, -1)
      encode_error_for(:int16, 32_768)
      encode_error_for(:uint16, 65_536)
      encode_error_for(:int32, 2_147_483_648)
      encode_error_for(:uint32, 4_294_967_296)
    end

    test "non-integer into a fixed int field raises" do
      encode_error_for(:int32, "text")
      encode_error_for(:int32, 1.5)
      encode_error_for(:int32, true)
    end

    test "float fields require floats" do
      encode_error_for(:float32, 1)
      encode_error_for(:float64, "x")
    end

    test "bool field requires a boolean" do
      encode_error_for(:bool, 1)
      encode_error_for(:bool, "true")
    end

    test "null field tolerates only nil" do
      schema = Schema.new(12, "N", [%{name: "v", type: :null}])

      assert_raise Btoon.EncodeError, fn ->
        Btoon.encode!(%{"v" => false}, schema: schema)
      end
    end

    test "string field requires a binary" do
      encode_error_for(:string, 42)
      encode_error_for(:string, nil)
    end

    test "missing field value raises" do
      schema =
        Schema.new(20, "M", [%{name: "present", type: :int32}, %{name: "absent", type: :int32}])

      assert_raise Btoon.EncodeError, fn ->
        Btoon.encode!(%{"present" => 1}, schema: schema)
      end
    end
  end

  describe "determinism between encode/2 and encode!/2 in schema mode" do
    test "both entry points produce identical bytes" do
      schema =
        Schema.new(77, "Eq", [
          %{name: "id", type: :int32},
          %{name: "label", type: :string},
          %{name: "score", type: :float64},
          %{name: "tags", type: :array}
        ])

      value = %{"id" => 3, "label" => "eq", "score" => 9.75, "tags" => ["a", "b"]}

      bang = Btoon.encode!(value, schema: schema)
      {:ok, ok} = Btoon.encode(value, schema: schema)

      assert bang == ok
      assert Btoon.decode!(bang) == value
    end
  end
end
