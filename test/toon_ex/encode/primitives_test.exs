defmodule ToonEx.Encode.PrimitivesTest do
  use ExUnit.Case, async: true

  alias ToonEx.Encode.Primitives

  defp to_binary(iodata), do: IO.iodata_to_binary(iodata)

  describe "encode/2 for primitives" do
    test "encodes nil as null" do
      assert to_binary(Primitives.encode(nil, ",")) == "null"
    end

    test "encodes true as true" do
      assert to_binary(Primitives.encode(true, ",")) == "true"
    end

    test "encodes false as false" do
      assert to_binary(Primitives.encode(false, ",")) == "false"
    end

    test "encodes positive integer" do
      assert to_binary(Primitives.encode(42, ",")) == "42"
    end

    test "encodes negative integer" do
      assert to_binary(Primitives.encode(-42, ",")) == "-42"
    end

    test "encodes zero" do
      assert to_binary(Primitives.encode(0, ",")) == "0"
    end

    test "encodes positive float" do
      assert to_binary(Primitives.encode(3.14, ",")) == "3.14"
    end

    test "encodes negative float" do
      assert to_binary(Primitives.encode(-3.14, ",")) == "-3.14"
    end

    test "encodes whole-number float as integer (no decimal point)" do
      assert to_binary(Primitives.encode(42.0, ",")) == "42"
    end

    test "encodes negative whole-number float as integer" do
      assert to_binary(Primitives.encode(-42.0, ",")) == "-42"
    end

    test "encodes string without special characters" do
      assert to_binary(Primitives.encode("hello", ",")) == "hello"
    end

    test "encodes string with space (not quoted - space not a delimiter)" do
      assert to_binary(Primitives.encode("hello world", ",")) == "hello world"
    end

    test "encodes string with delimiter (needs quoting)" do
      assert to_binary(Primitives.encode("a,b", ",")) == ~s("a,b")
    end

    test "encodes string with newline (needs quoting)" do
      result = Primitives.encode("line1\nline2", ",")
      # Newline is escaped as \n in the output string (two chars: backslash + n)
      assert to_binary(result) == "\"line1\\nline2\""
    end

    test "encodes empty string (needs quoting)" do
      assert to_binary(Primitives.encode("", ",")) == ~s("")
    end

    test "encodes float that uses scientific notation in Float.to_string" do
      # Very large float that Float.to_string would use scientific notation
      result = to_binary(Primitives.encode(1.0e308, ","))
      # Should be converted to decimal without scientific notation
      refute String.contains?(result, "e")
      refute String.contains?(result, "E")
    end

    test "encodes very small float that would use scientific notation" do
      result = to_binary(Primitives.encode(1.0e-10, ","))
      # Should be converted to decimal without scientific notation
      refute String.contains?(result, "e")
      refute String.contains?(result, "E")
    end

    test "encodes large float that uses scientific notation" do
      result = to_binary(Primitives.encode(1.23e20, ","))
      # Should be converted to decimal without scientific notation
      refute String.contains?(result, "e")
      refute String.contains?(result, "E")
    end

    test "encodes very small scientific float" do
      result = to_binary(Primitives.encode(1.23e-15, ","))
      # Should be converted to decimal
      refute String.contains?(result, "e")
      refute String.contains?(result, "E")
      assert String.contains?(result, ".")
    end

    test "encodes large scientific float" do
      result = to_binary(Primitives.encode(1.23e20, ","))
      refute String.contains?(result, "e")
      refute String.contains?(result, "E")
      # Large scientific floats get converted to integer form
      assert String.contains?(result, "123")
    end
  end

  describe "fallback_decimals coverage" do
    test "encodes very large float using fallback_decimals" do
      # This triggers the fallback_decimals path for values >= 1e8
      result = to_binary(Primitives.encode(1.23e100, ","))
      refute String.contains?(result, "e")
      refute String.contains?(result, "E")
      assert String.contains?(result, "123")
    end

    test "encodes very small float that underflows to zero" do
      # Values smaller than ~5e-324 underflow to 0.0
      result = to_binary(Primitives.encode(1.23e-324, ","))
      assert result == "0"
    end
  end

  # Note: The following code paths in format_float/1 are defensive and cannot be
  # triggered in Erlang/Elixir because the BEAM doesn't allow creating
  # infinity or NaN float values at runtime (they throw ArithmeticError):
  # - value > 1.0e308 or value < -1.0e308 -> null (overflow check)
  # - value != value -> null (NaN check)
  # These branches remain in the code for defensive completeness in case
  # values are passed from external sources (NIFs, etc.)
end
