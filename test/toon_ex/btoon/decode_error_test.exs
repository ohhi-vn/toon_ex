defmodule ToonEx.Btoon.DecodeErrorTest do
  use ExUnit.Case, async: true

  describe "envelope errors" do
    test "rejects bad magic" do
      assert {:error, %ToonEx.Btoon.DecodeError{reason: {:bad_magic, _}}} =
               ToonEx.Btoon.decode(<<1, 2, 3, 4, 1, 0, 0, 0>>)
    end

    test "rejects unsupported version" do
      assert {:error, %ToonEx.Btoon.DecodeError{reason: {:bad_version, 2}}} =
               ToonEx.Btoon.decode("BTON" <> <<2, 0, 0, 0>>)
    end

    test "rejects truncated header" do
      assert {:error, %ToonEx.Btoon.DecodeError{}} = ToonEx.Btoon.decode(<<"BTON", 1>>)
    end
  end

  describe "truncation" do
    test "truncated body raises" do
      full = ToonEx.Btoon.encode!(%{"a" => [1, 2, 3]})
      truncated = binary_part(full, 0, byte_size(full) - 2)
      assert {:error, %ToonEx.Btoon.DecodeError{}} = ToonEx.Btoon.decode(truncated)
    end

    test "truncated string data raises" do
      # Tagged string claiming 10 bytes with no payload.
      assert {:error, %ToonEx.Btoon.DecodeError{}} =
               ToonEx.Btoon.decode("BTON" <> <<1, 0, 0, 0, 7, 10, 0, 0, 0, "ab">>)
    end
  end

  describe "invalid content" do
    test "unknown value tag raises" do
      assert {:error, %ToonEx.Btoon.DecodeError{reason: {:invalid_tag, 0x1F}}} =
               ToonEx.Btoon.decode("BTON" <> <<1, 0, 0, 0, 0x1F>>)
    end

    test "string ref out of range raises" do
      assert {:error, %ToonEx.Btoon.DecodeError{reason: {:invalid_string_ref, 3}}} =
               ToonEx.Btoon.decode("BTON" <> <<1, 0, 0, 0, 11, 0x43>>)
    end

    test "object key must be a string or ref" do
      # Object with a SmallInt key (invalid: keys cannot be bare ints).
      assert {:error, %ToonEx.Btoon.DecodeError{}} =
               ToonEx.Btoon.decode("BTON" <> <<1, 0, 0, 0, 10, 1, 0, 0, 0, 0x40>>)
    end

    test "invalid typed array element type raises" do
      # TypedArray with element selector 0x09 (null) — not a valid numeric type.
      assert {:error, %ToonEx.Btoon.DecodeError{}} =
               ToonEx.Btoon.decode("BTON" <> <<1, 0, 0, 0, 12, 9, 1, 0, 0, 0, 0>>)
    end
  end

  describe "depth limit" do
    test "max_depth option limits nesting" do
      assert {:error, %ToonEx.Btoon.DecodeError{reason: :depth_exceeded}} =
               ToonEx.Btoon.decode(ToonEx.Btoon.encode!(%{"a" => [%{"b" => [%{"c" => 1}]}]}),
                 max_depth: 2
               )

      assert {:ok, _} = ToonEx.Btoon.decode(ToonEx.Btoon.encode!(%{"a" => [1]}), max_depth: 2)
    end
  end

  describe "public API" do
    test "decode! raises DecodeError" do
      assert_raise ToonEx.Btoon.DecodeError, fn ->
        ToonEx.Btoon.decode!("BTON" <> <<1, 0, 0, 0, 0x1F>>)
      end
    end

    test "decode accepts a non-binary with error" do
      assert {:error, %ToonEx.Btoon.DecodeError{}} = ToonEx.Btoon.decode(123)
    end
  end
end
