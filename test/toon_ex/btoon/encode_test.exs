defmodule ToonEx.Btoon.EncodeTest do
  use ExUnit.Case, async: true

  describe "envelope header" do
    test "magic, version, zero flags and reserved bytes for bare values" do
      assert <<66, 84, 79, 78, 1, 0, 0, 0, _::binary>> = ToonEx.Btoon.encode!(42)
      assert byte_size(ToonEx.Btoon.encode!(42)) == 9
    end

    test "string table flag is set when a table is emitted" do
      assert <<66, 84, 79, 78, 1, 4, 0, 0, _::binary>> = ToonEx.Btoon.encode!("hello")

      assert <<66, 84, 79, 78, 1, 0, 0, 0, _::binary>> =
               ToonEx.Btoon.encode!("hello", string_table: :off)
    end
  end

  describe "SmallInt" do
    test "bare bytes for the -32..95 range" do
      assert ToonEx.Btoon.encode!(-32) == <<66, 84, 79, 78, 1, 0, 0, 0, 0x20>>
      assert ToonEx.Btoon.encode!(0) == <<66, 84, 79, 78, 1, 0, 0, 0, 0x40>>
      assert ToonEx.Btoon.encode!(42) == <<66, 84, 79, 78, 1, 0, 0, 0, 0x6A>>
      assert ToonEx.Btoon.encode!(95) == <<66, 84, 79, 78, 1, 0, 0, 0, 0x9F>>
    end

    test "overflow falls back to Int32" do
      assert ToonEx.Btoon.encode!(96) == <<66, 84, 79, 78, 1, 0, 0, 0, 3, 96, 0, 0, 0>>
      assert ToonEx.Btoon.encode!(-33) == <<66, 84, 79, 78, 1, 0, 0, 0, 3, 223, 255, 255, 255>>
    end

    test "Int32 boundaries" do
      assert <<_::binary-size(8), 3, _::32-little>> = ToonEx.Btoon.encode!(2_147_483_647)
      assert <<_::binary-size(8), 3, _::32-little>> = ToonEx.Btoon.encode!(-2_147_483_648)
    end

    test "out of int32 range falls back to Int64" do
      assert ToonEx.Btoon.encode!(2_147_483_648) ==
               <<66, 84, 79, 78, 1, 0, 0, 0, 4, 0, 0, 0, 128, 0, 0, 0, 0>>

      assert ToonEx.Btoon.encode!(-2_147_483_649) ==
               <<66, 84, 79, 78, 1, 0, 0, 0, 4, 255, 255, 255, 127, 255, 255, 255, 255>>
    end
  end

  describe "floats" do
    test "float32 when lossless" do
      assert ToonEx.Btoon.encode!(1.5) == <<66, 84, 79, 78, 1, 0, 0, 0, 5, 0, 0, 192, 63>>
    end

    test "float64 otherwise" do
      assert ToonEx.Btoon.encode!(1.1) ==
               <<66, 84, 79, 78, 1, 0, 0, 0, 6, 154, 153, 153, 153, 153, 153, 241, 63>>
    end
  end

  describe "primitives" do
    test "null, booleans" do
      assert ToonEx.Btoon.encode!(nil) == <<66, 84, 79, 78, 1, 0, 0, 0, 0>>
      assert ToonEx.Btoon.encode!(true) == <<66, 84, 79, 78, 1, 0, 0, 0, 2>>
      assert ToonEx.Btoon.encode!(false) == <<66, 84, 79, 78, 1, 0, 0, 0, 1>>
    end

    test "binary tag" do
      assert ToonEx.Btoon.encode!(ToonEx.Btoon.Binary.new(<<1, 2, 3>>)) ==
               <<66, 84, 79, 78, 1, 0, 0, 0, 8, 3, 0, 0, 0, 1, 2, 3>>
    end
  end

  describe "strings and the per-message table" do
    test "first-encounter strings land in the table and become StringRef" do
      assert ToonEx.Btoon.encode!("hello") ==
               <<66, 84, 79, 78, 1, 4, 0, 0, 1, 0, 0, 0, 5, 0, 0, 0, "hello", 0, 0, 0, 11, 0x40>>
    end

    test "duplicate strings share a single table entry" do
      bin = ToonEx.Btoon.encode!(["hello", "hello"])
      assert byte_size(bin) < 2 * byte_size(ToonEx.Btoon.encode!("hello", string_table: :off))
    end

    test "string_table: :off writes full strings" do
      assert ToonEx.Btoon.encode!("hello", string_table: :off) ==
               <<66, 84, 79, 78, 1, 0, 0, 0, 7, 5, 0, 0, 0, "hello">>
    end
  end

  describe "typed arrays" do
    test "homogeneous numeric lists encode as TypedArray" do
      assert ToonEx.Btoon.encode!([1, 2, 3]) ==
               <<66, 84, 79, 78, 1, 0, 0, 0, 12, 0, 3, 0, 0, 0, 0, 1, 2, 3>>
    end

    test "narrowest lossless type is chosen" do
      assert <<_::binary-size(8), 12, 0, _::binary>> = ToonEx.Btoon.encode!([1, 2, 3])
      assert <<_::binary-size(8), 12, 2, _::binary>> = ToonEx.Btoon.encode!([1, 300])
      assert <<_::binary-size(8), 12, 7, _::binary>> = ToonEx.Btoon.encode!([1.5, 2.5])
    end

    test "typed_arrays: false uses the general array tag" do
      assert <<_::binary-size(8), 9, 3, 0, 0, 0, _::binary>> =
               ToonEx.Btoon.encode!([1, 2, 3], typed_arrays: false)
    end
  end

  describe "determinism" do
    test "identical inputs produce identical bytes" do
      input = %{"z" => [3, 1, 2], "a" => %{"nested" => "value", "flag" => true}, "m" => nil}
      assert ToonEx.Btoon.encode!(input) == ToonEx.Btoon.encode!(input)
      assert ToonEx.Btoon.encode!([1.5, 2.5]) == ToonEx.Btoon.encode!([1.5, 2.5])
    end

    test "map keys are sorted" do
      assert ToonEx.Btoon.encode!(%{"b" => 1, "a" => 2}) ==
               ToonEx.Btoon.encode!(%{"a" => 2, "b" => 1})
    end
  end

  describe "public API" do
    test "encode returns {:ok, binary}" do
      assert {:ok, _bin} = ToonEx.Btoon.encode(%{"a" => 1})
    end

    test "encode returns {:error, EncodeError} for unencodable input" do
      assert {:error, %ToonEx.Btoon.EncodeError{}} = ToonEx.Btoon.encode(%{__struct__: Foo, x: 1})
    end

    test "encode! raises EncodeError" do
      assert_raise ToonEx.Btoon.EncodeError, fn -> ToonEx.Btoon.encode!(DateTime.utc_now()) end
    end

    test "encode_to_iodata! produces flat iodata" do
      iodata = ToonEx.Btoon.Encode.encode_to_iodata!(%{"a" => [1, 2]})
      assert IO.iodata_to_binary(iodata) == ToonEx.Btoon.encode!(%{"a" => [1, 2]})
    end
  end
end
