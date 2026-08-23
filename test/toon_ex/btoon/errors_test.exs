defmodule ToonEx.Btoon.ErrorsTest do
  use ExUnit.Case, async: true

  alias ToonEx.Btoon.{DecodeError, EncodeError}

  describe "EncodeError.exception/1" do
    test "keyword form with all fields" do
      error = EncodeError.exception(message: "boom", value: :x, reason: :bad)

      assert error.message == "boom"
      assert error.value == :x
      assert error.reason == :bad
    end

    test "keyword form defaults" do
      error = EncodeError.exception([])
      assert error.message == "encode error"
      refute error.value
      refute error.reason
    end

    test "binary shorthand" do
      error = EncodeError.exception("plain")
      assert error.message == "plain"
      refute error.value
    end

    test "message/1 omits nil values and appends inspected values" do
      assert Exception.message(EncodeError.exception("a")) == "a"

      assert Exception.message(EncodeError.exception(message: "b", value: %{k: 1})) =~
               ~s(b: %{k: 1})
    end

    test "is_raisable via raise" do
      assert_raise EncodeError, "direct", fn -> raise EncodeError, "direct" end
    end
  end

  describe "DecodeError.exception/1" do
    test "keyword form with offset appends position to message" do
      error = DecodeError.exception(message: "bad tag", input: <<1, 2>>, offset: 7, reason: :tag)

      assert Exception.message(error) == "bad tag (at offset 7)"
      assert error.input == <<1, 2>>
    end

    test "nil offset keeps bare message" do
      error = DecodeError.exception(message: "truncated")
      assert Exception.message(error) == "truncated"
    end

    test "binary shorthand" do
      error = DecodeError.exception("nope")
      assert error.message == "nope"
      refute error.input
      refute error.offset
    end

    test "keyword defaults" do
      error = DecodeError.exception([])
      assert error.message == "decode error"
    end
  end
end
