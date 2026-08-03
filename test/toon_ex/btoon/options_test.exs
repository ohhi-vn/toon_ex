defmodule ToonEx.Btoon.OptionsTest do
  use ExUnit.Case, async: true

  alias ToonEx.Btoon

  describe "encode options" do
    test "unknown option rejected" do
      assert {:error, %Btoon.EncodeError{}} = Btoon.encode(1, bogus: true)
    end

    test "invalid dictionary rejected" do
      assert {:error, %Btoon.EncodeError{}} =
               Btoon.encode(1, dictionary: :not_a_dict)
    end

    test "invalid string_table rejected" do
      assert {:error, %Btoon.EncodeError{}} =
               Btoon.encode(1, string_table: :sometimes)
    end

    test "invalid typed_arrays rejected" do
      assert {:error, %Btoon.EncodeError{}} = Btoon.encode(1, typed_arrays: :maybe)
    end

    test "nil dictionary and schema accepted" do
      assert {:ok, _} = Btoon.encode(1, dictionary: nil, schema: nil)
    end
  end

  describe "decode options" do
    test "unknown option rejected" do
      assert {:error, %Btoon.DecodeError{}} =
               Btoon.decode(Btoon.encode!(1), bogus: 1)
    end

    test "invalid keys option rejected" do
      assert {:error, %Btoon.DecodeError{}} =
               Btoon.decode(Btoon.encode!(1), keys: :nope)
    end

    test "invalid typed_arrays option rejected" do
      assert {:error, %Btoon.DecodeError{}} =
               Btoon.decode(Btoon.encode!(1), typed_arrays: :nope)
    end

    test "invalid max_depth rejected" do
      assert {:error, %Btoon.DecodeError{}} =
               Btoon.decode(Btoon.encode!(1), max_depth: 0)
    end

    test "atoms! requires an existing atom" do
      bin = Btoon.encode!(%{"missing_key" => 1})
      assert_raise Btoon.DecodeError, fn -> Btoon.decode!(bin, keys: :atoms!) end
    end
  end

  describe "atoms option" do
    test "keys: :atoms returns atom keys" do
      value = %{"name" => "Alice", "age" => 30}

      assert Btoon.decode!(Btoon.encode!(value), keys: :atoms) == %{
               name: "Alice",
               age: 30
             }
    end
  end
end
