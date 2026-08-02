defmodule ToonEx.Btoon.OptionsTest do
  use ExUnit.Case, async: true

  describe "encode options" do
    test "unknown option rejected" do
      assert {:error, %ToonEx.Btoon.EncodeError{}} = ToonEx.Btoon.encode(1, bogus: true)
    end

    test "invalid dictionary rejected" do
      assert {:error, %ToonEx.Btoon.EncodeError{}} =
               ToonEx.Btoon.encode(1, dictionary: :not_a_dict)
    end

    test "invalid string_table rejected" do
      assert {:error, %ToonEx.Btoon.EncodeError{}} =
               ToonEx.Btoon.encode(1, string_table: :sometimes)
    end

    test "invalid typed_arrays rejected" do
      assert {:error, %ToonEx.Btoon.EncodeError{}} = ToonEx.Btoon.encode(1, typed_arrays: :maybe)
    end

    test "nil dictionary and schema accepted" do
      assert {:ok, _} = ToonEx.Btoon.encode(1, dictionary: nil, schema: nil)
    end
  end

  describe "decode options" do
    test "unknown option rejected" do
      assert {:error, %ToonEx.Btoon.DecodeError{}} =
               ToonEx.Btoon.decode(ToonEx.Btoon.encode!(1), bogus: 1)
    end

    test "invalid keys option rejected" do
      assert {:error, %ToonEx.Btoon.DecodeError{}} =
               ToonEx.Btoon.decode(ToonEx.Btoon.encode!(1), keys: :nope)
    end

    test "invalid typed_arrays option rejected" do
      assert {:error, %ToonEx.Btoon.DecodeError{}} =
               ToonEx.Btoon.decode(ToonEx.Btoon.encode!(1), typed_arrays: :nope)
    end

    test "invalid max_depth rejected" do
      assert {:error, %ToonEx.Btoon.DecodeError{}} =
               ToonEx.Btoon.decode(ToonEx.Btoon.encode!(1), max_depth: 0)
    end

    test "atoms! requires an existing atom" do
      bin = ToonEx.Btoon.encode!(%{"missing_key" => 1})
      assert_raise ToonEx.Btoon.DecodeError, fn -> ToonEx.Btoon.decode!(bin, keys: :atoms!) end
    end
  end

  describe "atoms option" do
    test "keys: :atoms returns atom keys" do
      value = %{"name" => "Alice", "age" => 30}

      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(value), keys: :atoms) == %{
               name: "Alice",
               age: 30
             }
    end
  end
end
