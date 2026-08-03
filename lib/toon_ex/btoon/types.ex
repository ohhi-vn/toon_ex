defmodule ToonEx.Btoon.Types do
  @moduledoc """
  Type definitions and wrapper types for the BTOON codec.

  The BTOON data model mirrors TOON: `nil`, booleans, integers, floats,
  UTF-8 strings, binary blobs, arrays and objects. Elixir strings are
  binaries, so two wrapper structs exist to disambiguate values that are
  otherwise indistinguishable:

    * `Btoon.Binary` – a binary value (tag `0x08`) as opposed to a string
      (tag `0x07`).
    * `Btoon.TypedArray` – a contiguous, homogeneous numeric buffer (tag
      `0x0C`).
    * `Btoon.ObjectTable` – a columnar table of homogeneous numeric columns
      (tag `0x0D`).

  ## Element types

  Element types are named atoms (`:int8`, `:uint8`, `:int16`, `:uint16`,
  `:int32`, `:uint32`, `:int64`, `:uint64`, `:float32`, `:float64`) and,
  for schema fields only, `:null`, `:bool`, `:string`, `:binary`, `:array`
  and `:object`. See `Btoon.ElementType`.
  """

  alias ToonEx.Btoon

  @typedoc "A BTOON primitive value."
  @type primitive :: nil | boolean() | integer() | float() | String.t() | Btoon.Binary.t()

  @typedoc """
  Any value that can be encoded by `Btoon`.
  """
  @type encodable ::
          nil
          | boolean()
          | integer()
          | float()
          | String.t()
          | Btoon.Binary.t()
          | Btoon.TypedArray.t()
          | Btoon.ObjectTable.t()
          | [encodable()]
          | %{optional(String.t()) => encodable()}

  @typedoc "An element type selector atom."
  @type element_type ::
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
          | :null
          | :bool
          | :string
          | :binary
          | :array
          | :object

  @typedoc "Options accepted by `Btoon.encode/2` and `Btoon.encode!/2`."
  @type encode_opts :: [encode_opt()]

  @typedoc "A single encoding option."
  @type encode_opt ::
          {:dictionary, Btoon.Dictionary.t() | nil}
          | {:string_table, :auto | :off}
          | {:schema, Btoon.Schema.t() | nil}
          | {:typed_arrays, boolean()}
          | {:object_tables, boolean()}

  @typedoc "Options accepted by `Btoon.decode/2` and `Btoon.decode!/2`."
  @type decode_opts :: [decode_opt()]

  @typedoc "A single decoding option."
  @type decode_opt ::
          {:dictionary, Btoon.Dictionary.t() | nil}
          | {:schema, Btoon.Schema.t() | nil}
          | {:keys, :strings | :atoms | :atoms!}
          | {:typed_arrays, :lists | :views}
          | {:max_depth, pos_integer()}
end

defmodule ToonEx.Btoon.Binary do
  @moduledoc """
  Wraps a raw binary value so the encoder emits tag `0x08` (Binary) instead
  of tag `0x07` (String). Plain Elixir binaries are always encoded as UTF-8
  strings.

  ## Examples

      iex> Btoon.encode!(%{"blob" => Btoon.Binary.new(<<1, 2, 3>>)})
      <<66, 84, 79, 78, 1, 0, 0, 0, 10, 1, 0, 0, 0, 8, 3, 0, 0, 0, 1, 2, 3>>
  """

  defstruct [:data]

  @type t :: %__MODULE__{data: binary()}

  @doc "Wraps a binary."
  @spec new(binary()) :: t()
  def new(data) when is_binary(data), do: %__MODULE__{data: data}

  @doc "Unwraps the wrapped binary."
  @spec data(t()) :: binary()
  def data(%__MODULE__{data: data}), do: data
end

defmodule ToonEx.Btoon.TypedArray do
  @moduledoc """
  A homogeneous numeric array stored as a contiguous binary buffer.

  Encoding emits tag `0x0C` (TypedArray): element type, element count,
  alignment padding and the raw little-endian buffer. Decoding with
  `typed_arrays: :views` returns this struct so callers can read the raw
  bytes without per-element copies.

  ## Examples

      iex> ta = Btoon.TypedArray.new(:float64, <<1.5::64-little-float, 2.5::64-little-float>>)
      iex> Btoon.TypedArray.type(ta)
      :float64
      iex> Btoon.TypedArray.to_list(ta)
      [1.5, 2.5]
  """

  alias ToonEx.Btoon

  defstruct [:type, :data]

  @type t :: %__MODULE__{type: Btoon.Types.element_type(), data: binary()}

  @doc """
  Builds a typed array from a raw buffer.

  The buffer length must be a multiple of the element size of `type`.
  """
  @spec new(Btoon.Types.element_type(), binary()) :: t()
  def new(type, data) when is_atom(type) and is_binary(data) do
    size = Btoon.ElementType.size(type)

    if size > 0 and rem(byte_size(data), size) != 0 do
      raise ArgumentError,
            "buffer size #{byte_size(data)} is not a multiple of #{size} for #{inspect(type)}"
    end

    %__MODULE__{type: type, data: data}
  end

  @doc "Returns the element type atom."
  @spec type(t()) :: Btoon.Types.element_type()
  def type(%__MODULE__{type: type}), do: type

  @doc "Returns the raw buffer."
  @spec data(t()) :: binary()
  def data(%__MODULE__{data: data}), do: data

  @doc """
  Converts the raw buffer into a list of numbers.
  """
  @spec to_list(t()) :: [number()]
  def to_list(%__MODULE__{type: type, data: data}),
    do: Btoon.ElementType.buffer_to_list(type, data)

  @doc "Number of elements in the typed array."
  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{type: type, data: data}),
    do: div(byte_size(data), Btoon.ElementType.size(type))

  @doc """
  Builds a typed array from a list of numbers, picking the narrowest type
  that represents every value losslessly (`:int8`..`:int64` for integers,
  `:float32`/`:float64` for floats).
  """
  @spec from_list([number()]) :: t()
  def from_list(values) when is_list(values) do
    case Btoon.ElementType.detect_type(values) do
      {:ok, type} ->
        %__MODULE__{type: type, data: Btoon.ElementType.list_to_buffer(type, values)}

      :error ->
        raise ArgumentError, "cannot detect an element type for #{inspect(values)}"
    end
  end
end

defmodule ToonEx.Btoon.ObjectTable do
  @moduledoc """
  A columnar table of homogeneous numeric columns (tag `0x0D`).

  An object table is the binary equivalent of the TOON tabular array form:
  each column holds the raw buffer for one field, decoded in bulk. Decoding
  with `typed_arrays: :views` returns this struct; otherwise rows are
  materialised as a list of maps.

  ## Examples

      iex> table = Btoon.ObjectTable.from_rows([%{"x" => 1, "y" => 2.5}, %{"x" => 3, "y" => 4.5}])
      iex> Btoon.ObjectTable.rows(table)
      [%{"x" => 1, "y" => 2.5}, %{"x" => 3, "y" => 4.5}]
  """

  alias ToonEx.Btoon

  defmodule Column do
    @moduledoc "A single column definition of an `Btoon.ObjectTable`."
    defstruct [:name, :type, :data]

    @type t :: %__MODULE__{
            name: String.t(),
            type: Btoon.Types.element_type(),
            data: binary()
          }
  end

  defstruct [:row_count, columns: []]

  @type t :: %__MODULE__{
          row_count: non_neg_integer(),
          columns: [Column.t()]
        }

  @doc """
  Builds an object table from a list of maps. All maps must share the same
  keys and every column must be homogeneous numeric (`Btoon.Types.encodable`).
  """
  @spec from_rows([%{optional(String.t()) => term()}]) :: t()
  def from_rows(rows) when is_list(rows) do
    case ToonEx.Btoon.ElementType.detect_object_table(rows) do
      {:ok, names, types, columns_data} ->
        columns =
          Enum.zip([names, types, columns_data])
          |> Enum.map(fn {name, type, values} ->
            data = ToonEx.Btoon.ElementType.list_to_buffer(type, values)

            %Column{name: name, type: type, data: data}
          end)

        %__MODULE__{row_count: length(rows), columns: columns}

      :error ->
        raise ArgumentError,
              "object table requires identical keys and homogeneous numeric columns"
    end
  end

  @doc """
  Materialises the table as a list of maps.
  """
  @spec rows(t()) :: [%{optional(String.t()) => term()}]
  def rows(%__MODULE__{row_count: row_count, columns: columns}) do
    col_names = Enum.map(columns, & &1.name)

    values =
      Enum.map(columns, fn %Column{type: type, data: data} ->
        Btoon.ElementType.buffer_to_list(type, data)
      end)

    for i <- 0..(row_count - 1) do
      Enum.zip(col_names, Enum.map(values, &Enum.at(&1, i)))
      |> Map.new()
    end
  end

  @doc "Returns the column definitions."
  @spec columns(t()) :: [Column.t()]
  def columns(%__MODULE__{columns: columns}), do: columns

  @doc "Row count of the table."
  @spec row_count(t()) :: non_neg_integer()
  def row_count(%__MODULE__{row_count: row_count}), do: row_count
end
