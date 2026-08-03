defmodule ToonEx.Btoon.ElementType do
  @moduledoc """
  Element type selectors and raw numeric encoding helpers.

  Element types cover the fixed-width numeric types shared by TypedArray
  payloads and Schema fields (`:int8`, `:uint8`, `:int16`, `:uint16`,
  `:int32`, `:uint32`, `:int64`, `:uint64`, `:float32`, `:float64`) plus
  the composite types used only by Schema fields (`:null`, `:bool`,
  `:string`, `:binary`, `:array`, `:object`).

  All multi-byte values are little-endian (see `ToonEx.Btoon` design notes).

  ## Deterministic type selection

  `detect_type/1` maps a homogeneous numeric list to the narrowest signed
  integer type that represents every value losslessly, or `:float32` when
  every float survives the float32 round-trip and `:float64` otherwise.
  Every list therefore has exactly one encoding.
  """

  alias ToonEx.Btoon.Constants

  @typedoc "Numeric element types (typed arrays and raw buffers)."
  @type numeric ::
          :int8
          | :uint8
          | :int16
          | :uint16
          | :int32
          | :uint32
          | :int64
          | :uint64
          | :float32
          | :float64

  @int64_min -9_223_372_036_854_775_808
  @int64_max 9_223_372_036_854_775_807

  @int16_min -32_768
  @int16_max 32_767

  @int8_min -128
  @int8_max 127

  @uint8_max 255
  @uint16_max 65_535
  @uint32_max 4_294_967_295
  @uint64_max 18_446_744_073_709_551_615

  @numeric_types [
    :int8,
    :uint8,
    :int16,
    :uint16,
    :int32,
    :uint32,
    :int64,
    :uint64,
    :float32,
    :float64
  ]

  @typed_array_types [:int8, :uint8, :int16, :uint16, :int32, :uint32, :int64, :float32, :float64]

  @compile {:inline,
            size: 1,
            numeric?: 1,
            typed_array_type?: 1,
            type_byte: 1,
            f32_exact?: 1,
            encode_raw: 2,
            encode_numeric: 2,
            element_size: 1,
            list_to_buffer: 2,
            do_list_to_buffer: 3}

  @doc "Element size in bytes (0 for variable-length composite types)."
  @spec size(ToonEx.Btoon.Types.element_type()) :: non_neg_integer()
  def size(type) when type in [:int8, :uint8, :bool], do: 1
  def size(type) when type in [:int16, :uint16], do: 2
  def size(type) when type in [:int32, :uint32, :float32], do: 4
  def size(type) when type in [:int64, :uint64, :float64], do: 8
  def size(:null), do: 0
  def size(type) when type in [:string, :binary, :array, :object], do: 0

  @doc "Alias of `size/1` for numeric types (raises for composite types)."
  @spec element_size(ToonEx.Btoon.Types.element_type()) :: pos_integer()
  def element_size(type) do
    if numeric?(type) do
      size(type)
    else
      raise ArgumentError, "#{inspect(type)} is not a fixed-width numeric element type"
    end
  end

  @doc "Whether the type is a fixed-width numeric type."
  @spec numeric?(ToonEx.Btoon.Types.element_type()) :: boolean()
  def numeric?(type), do: type in @numeric_types

  @doc "Whether the type may appear as a TypedArray element type."
  @spec typed_array_type?(ToonEx.Btoon.Types.element_type()) :: boolean()
  def typed_array_type?(type), do: type in @typed_array_types

  @doc """
  Maps a numeric type atom to its wire selector byte.

  Returns `nil` for unknown or composite types.
  """
  @spec type_byte(ToonEx.Btoon.Types.element_type()) :: byte() | nil
  def type_byte(:int8), do: Constants.element_int8()
  def type_byte(:uint8), do: Constants.element_uint8()
  def type_byte(:int16), do: Constants.element_int16()
  def type_byte(:uint16), do: Constants.element_uint16()
  def type_byte(:int32), do: Constants.element_int32()
  def type_byte(:uint32), do: Constants.element_uint32()
  def type_byte(:int64), do: Constants.element_int64()
  def type_byte(:float32), do: Constants.element_float32()
  def type_byte(:float64), do: Constants.element_float64()
  def type_byte(:null), do: Constants.element_null()
  def type_byte(:bool), do: Constants.element_bool()
  def type_byte(:string), do: Constants.element_string()
  def type_byte(:binary), do: Constants.element_binary()
  def type_byte(:array), do: Constants.element_array()
  def type_byte(:object), do: Constants.element_object()
  def type_byte(:uint64), do: Constants.element_uint64()
  def type_byte(_), do: nil

  @doc """
  Maps a wire selector byte to a type atom. Raises `ArgumentError` for
  unknown selectors.
  """
  @spec type_atom(byte()) :: ToonEx.Btoon.Types.element_type()
  def type_atom(byte) do
    case type_atom_or_nil(byte) do
      nil -> raise ArgumentError, "unknown element type selector 0x#{Integer.to_string(byte, 16)}"
      type -> type
    end
  end

  @doc "Maps a wire selector byte to a type atom or `nil`."
  @spec type_atom_or_nil(byte()) :: ToonEx.Btoon.Types.element_type() | nil
  def type_atom_or_nil(byte) when byte in 0x00..0x0F do
    elem(
      {:int8, :uint8, :int16, :uint16, :int32, :uint32, :int64, :float32, :float64, :null, :bool,
       :string, :binary, :array, :object, :uint64},
      byte
    )
  end

  def type_atom_or_nil(_), do: nil

  @doc "Whether a double survives the IEEE-754 float32 round-trip exactly."
  @spec f32_exact?(float()) :: boolean()
  def f32_exact?(value) when is_float(value) do
    if abs(value) > 3.402_823_466_385_288_6e38 do
      false
    else
      <<truncated::32-little-float>> = <<value::32-little-float>>
      truncated == value
    end
  end

  @doc """
  Detects the narrowest element type for a homogeneous numeric list.

  Returns `{:ok, type}` or `:error` when the list is empty, mixed, or
  contains integers outside the int64 range.
  """
  @spec detect_type([number()]) :: {:ok, ToonEx.Btoon.Types.element_type()} | :error
  def detect_type([]), do: :error

  def detect_type(values) when is_list(values) do
    # Single pass: check type and collect min/max for integers, or check float32 exactness
    case Enum.reduce_while(values, {:unknown, nil, nil}, fn
           v, {:unknown, _, _} when is_integer(v) ->
             {:cont, {:int, v, v}}

           v, {:unknown, _, _} when is_float(v) ->
             {:cont, {:float, if(f32_exact?(v), do: :float32, else: :float64)}}

           _, {:unknown, _, _} ->
             {:halt, :error}

           v, {:int, min, max} when is_integer(v) ->
             {:cont, {:int, Kernel.min(min, v), Kernel.max(max, v)}}

           _, {:int, _, _} ->
             {:halt, :error}

           v, {:float, :float32} when is_float(v) ->
             if f32_exact?(v), do: {:cont, {:float, :float32}}, else: {:cont, {:float, :float64}}

           v, {:float, :float64} when is_float(v) ->
             {:cont, {:float, :float64}}

           _, {:float, _} ->
             {:halt, :error}
         end) do
      {:int, min, max} -> int_type_from_bounds(min, max)
      {:float, :float32} -> {:ok, :float32}
      {:float, :float64} -> {:ok, :float64}
      :error -> :error
    end
  end

  defp int_type_from_bounds(min, max) do
    cond do
      min < @int64_min or max > @int64_max ->
        :error

      min >= @int8_min and max <= @int8_max ->
        {:ok, :int8}

      min >= @int16_min and max <= @int16_max ->
        {:ok, :int16}

      min >= Constants.int32_min() and max <= Constants.int32_max() ->
        {:ok, :int32}

      true ->
        {:ok, :int64}
    end
  end

  @doc """
  Detects whether a list of maps is a valid columnar object table.

  All maps must share the same (sorted) key set and each column must be a
  homogeneous numeric column. Returns `{:ok, names, types, columns}` or `:error`.
  """
  @spec detect_object_table([%{optional(String.t()) => term()}]) ::
          {:ok, [String.t()], [ToonEx.Btoon.Types.element_type()], [[number()]]} | :error
  def detect_object_table([]), do: :error

  def detect_object_table([first | _] = rows) when is_map(first) and map_size(first) > 0 do
    names = first |> Map.keys() |> Enum.sort()
    expected_size = length(names)

    same_keys? =
      Enum.all?(rows, fn row ->
        is_map(row) and map_size(row) == expected_size and
          Enum.all?(names, &Map.has_key?(row, &1))
      end)

    case same_keys? do
      false ->
        :error

      true ->
        case detect_columns(names, rows) do
          {:ok, types, columns} -> {:ok, names, types, columns}
          :error -> :error
        end
    end
  end

  def detect_object_table(_), do: :error

  @doc """
  Encodes a single number to its raw little-endian representation.
  """
  @spec encode_raw(ToonEx.Btoon.Types.element_type(), number()) :: binary()
  def encode_raw(type, value) when type in @numeric_types do
    encode_numeric(type, value)
  end

  @doc """
  Encodes a list of numbers into a contiguous raw buffer.
  """
  @spec list_to_buffer(ToonEx.Btoon.Types.element_type(), [number()]) :: binary()
  def list_to_buffer(type, values) when is_atom(type) and is_list(values) do
    values
    |> do_list_to_buffer(type, [])
    |> :lists.reverse()
    |> IO.iodata_to_binary()
  end

  @doc """
  Decodes a raw buffer into a list of numbers.
  """
  @spec buffer_to_list(ToonEx.Btoon.Types.element_type(), binary()) :: [number()]
  def buffer_to_list(type, data) when is_binary(data) do
    do_buffer_to_list(type, data, [])
  end

  @doc "Decodes the first element of a buffer, returning `{value, rest}`."
  @spec decode_raw(ToonEx.Btoon.Types.element_type(), binary()) :: {number(), binary()}
  def decode_raw(:int8, <<v::8-signed, rest::binary>>), do: {v, rest}
  def decode_raw(:uint8, <<v::8, rest::binary>>), do: {v, rest}
  def decode_raw(:int16, <<v::16-little-signed, rest::binary>>), do: {v, rest}
  def decode_raw(:uint16, <<v::16-little, rest::binary>>), do: {v, rest}
  def decode_raw(:int32, <<v::32-little-signed, rest::binary>>), do: {v, rest}
  def decode_raw(:uint32, <<v::32-little, rest::binary>>), do: {v, rest}
  def decode_raw(:int64, <<v::64-little-signed, rest::binary>>), do: {v, rest}
  def decode_raw(:uint64, <<v::64-little, rest::binary>>), do: {v, rest}
  def decode_raw(:float32, <<v::32-little-float, rest::binary>>), do: {v, rest}
  def decode_raw(:float64, <<v::64-little-float, rest::binary>>), do: {v, rest}

  def decode_raw(type, _),
    do: raise(ArgumentError, "not a numeric element type: #{inspect(type)}")

  @doc """
  Integer range for a numeric type: `{min, max}` for integer types,
  `nil` for float types.
  """
  @spec int_range(ToonEx.Btoon.Types.element_type()) :: {integer(), integer()} | nil
  def int_range(:int8), do: {@int8_min, @int8_max}
  def int_range(:uint8), do: {0, @uint8_max}
  def int_range(:int16), do: {@int16_min, @int16_max}
  def int_range(:uint16), do: {0, @uint16_max}
  def int_range(:int32), do: {Constants.int32_min(), Constants.int32_max()}
  def int_range(:uint32), do: {0, @uint32_max}
  def int_range(:int64), do: {@int64_min, @int64_max}
  def int_range(:uint64), do: {0, @uint64_max}
  def int_range(_), do: nil

  # ── private ─────────────────────────────────────────────────────────────────

  defp detect_columns([], _rows), do: {:ok, [], []}

  defp detect_columns([name | rest], rows) do
    column = Enum.map(rows, fn row -> Map.fetch!(row, name) end)

    case detect_type(column) do
      :error ->
        :error

      {:ok, type} ->
        case detect_columns(rest, rows) do
          {:ok, types, columns} -> {:ok, [type | types], [column | columns]}
          :error -> :error
        end
    end
  end

  defp do_list_to_buffer([], _type, acc), do: acc

  defp do_list_to_buffer([v | rest], type, acc) do
    do_list_to_buffer(rest, type, [encode_numeric(type, v) | acc])
  end

  defp encode_numeric(:int8, v), do: <<v::8-signed>>
  defp encode_numeric(:uint8, v), do: <<v::8>>
  defp encode_numeric(:int16, v), do: <<v::16-little-signed>>
  defp encode_numeric(:uint16, v), do: <<v::16-little>>
  defp encode_numeric(:int32, v), do: <<v::32-little-signed>>
  defp encode_numeric(:uint32, v), do: <<v::32-little>>
  defp encode_numeric(:int64, v), do: <<v::64-little-signed>>
  defp encode_numeric(:uint64, v), do: <<v::64-little>>
  defp encode_numeric(:float32, v), do: <<v::32-little-float>>
  defp encode_numeric(:float64, v), do: <<v::64-little-float>>

  defp do_buffer_to_list(_type, <<>>, acc), do: :lists.reverse(acc)

  defp do_buffer_to_list(type, data, acc) do
    {value, rest} = decode_raw(type, data)
    do_buffer_to_list(type, rest, [value | acc])
  end
end
