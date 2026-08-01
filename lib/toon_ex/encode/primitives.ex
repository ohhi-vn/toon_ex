defmodule ToonEx.Encode.Primitives do
  @moduledoc """
  Encoding of primitive TOON values (nil, boolean, number, string).
  """

  # Performance: Inline hot functions to reduce function call overhead
  @compile {:inline,
            encode: 2, format_float: 1, scientific?: 1, to_decimal: 1, trim_trailing_zeros: 1}

  alias ToonEx.Constants
  alias ToonEx.Encode.Strings

  # GPS-optimized decimal places lookup table.
  # For values in GPS range (±180, ±90) with 8-9 decimals, we avoid :math.log10() calls.
  # Ranges: {upper_bound_exclusive, decimals}
  @float_decimals [
    {1.0e-9, 18},
    {1.0e-8, 17},
    {1.0e-7, 16},
    {1.0e-6, 15},
    {1.0e-5, 14},
    {1.0e-4, 13},
    {1.0e-3, 12},
    {1.0e-2, 11},
    {1.0e-1, 10},
    {1.0, 9},
    {10.0, 8},
    {100.0, 7},
    {1000.0, 6},
    {10_000.0, 5},
    {100_000.0, 4},
    {1_000_000.0, 3},
    {1.0e7, 2},
    {1.0e8, 1}
  ]

  @doc """
  Encodes a primitive value to TOON format.

  ## Examples

      iex> ToonEx.Encode.Primitives.encode(nil, ",")
      "null"

      iex> ToonEx.Encode.Primitives.encode(true, ",")
      "true"

      iex> ToonEx.Encode.Primitives.encode(false, ",")
      "false"

      iex> ToonEx.Encode.Primitives.encode(42, ",")
      "42"

      iex> ToonEx.Encode.Primitives.encode(3.14, ",")
      "3.14"

      iex> ToonEx.Encode.Primitives.encode("hello", ",")
      "hello"

      iex> ToonEx.Encode.Primitives.encode("hello world", ",")
      ~s("hello world")
  """
  @spec encode(term(), String.t()) :: iodata()
  def encode(nil, _delimiter), do: Constants.null_literal()
  def encode(true, _delimiter), do: Constants.true_literal()
  def encode(false, _delimiter), do: Constants.false_literal()

  def encode(value, _delimiter) when is_integer(value) do
    Integer.to_string(value)
  end

  def encode(value, _delimiter) when is_float(value) do
    # Format float without scientific notation
    format_float(value)
  end

  def encode(value, delimiter) when is_binary(value) do
    Strings.encode_string(value, delimiter)
  end

  # Private helpers

  @doc false
  @spec format_float(float()) :: String.t()

  defp format_float(value) when is_float(value) do
    cond do
      # IEEE 754 NaN: the only float not equal to itself
      # credo:disable-for-lines:2
      value != value ->
        Constants.null_literal()

      value > 1.0e308 or value < -1.0e308 ->
        Constants.null_literal()

      # Whole-number float — encode without decimal point per TOON spec
      trunc(value) == value ->
        Integer.to_string(trunc(value))

      true ->
        str = Float.to_string(value)
        if scientific?(str), do: to_decimal(value), else: str
    end
  end

  # `:erlang.float_to_binary` uses exponential notation when abs < 0.1 or
  # abs >= 1.0e16; `Float.to_string` (Ryu) uses it outside a similar range.
  defp scientific?(str), do: String.contains?(str, "e") or String.contains?(str, "E")

  # Convert a float that Float.to_string/1 represented in scientific notation
  # to a plain decimal string, trimming trailing zeros.
  #
  # GPS-optimized: use range-based lookup table instead of :math.log10() calls.
  # Falls back to dynamic calculation for values outside the lookup range.
  defp to_decimal(value) do
    abs_val = abs(value)
    decimals = lookup_decimals(abs_val, @float_decimals)
    raw = :erlang.float_to_binary(value, [{:decimals, decimals}])
    trim_trailing_zeros(raw)
  end

  # Binary search lookup for decimal places - O(log n) instead of :math.log10()
  defp lookup_decimals(abs_val, [{bound, decimals} | _]) when abs_val < bound, do: decimals
  defp lookup_decimals(abs_val, [_ | rest]), do: lookup_decimals(abs_val, rest)
  defp lookup_decimals(abs_val, []), do: fallback_decimals(abs_val)

  # Fallback for values outside the lookup table (very large or very small)
  defp fallback_decimals(abs_val) do
    if abs_val < 1.0 do
      neg_exp = abs_val |> :math.log10() |> abs() |> Float.ceil() |> trunc()
      min(neg_exp + 17, 324)
    else
      exp = abs_val |> :math.log10() |> Float.floor() |> trunc()
      max(17 - exp, 1)
    end
  end

  # Splits on "." and strips trailing "0" from the fractional part.
  # If the fractional part becomes empty the decimal point is also dropped,
  # which correctly represents whole numbers (should never occur here since
  # whole-number floats are caught above, but defensive).
  # Performance: Return iolist [int, ".", stripped] instead of binary concatenation
  # (int <> "." <> stripped). The iolist avoids allocating a new binary and copying
  # both strings into it. The final IO.iodata_to_binary at the top-level encoder
  # flattens everything in one pass, so nested iolists are free.
  defp trim_trailing_zeros(str) do
    case String.split(str, ".", parts: 2) do
      [int, frac] ->
        stripped = String.trim_trailing(frac, "0")
        if stripped == "", do: int, else: [int, ".", stripped]

      [int] ->
        int
    end
  end
end
