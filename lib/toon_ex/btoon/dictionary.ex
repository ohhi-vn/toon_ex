defmodule ToonEx.Btoon.Dictionary do
  @moduledoc """
  A session string dictionary.

  A session dictionary is negotiated once per connection (see the BTOON
  handshake in the specification) and shared between encoder and decoder.
  Strings present in the dictionary are encoded as `StringRef` (tag `0x0B`)
  referencing their zero-based index, avoiding repeated UTF-8 transmission.

  The per-message string table carried in the envelope is layered on top of
  the session dictionary: entry `i` of the table gets ref id
  `length(dictionary) + i`.

  ## Examples

      iex> dict = ToonEx.Btoon.Dictionary.new(["player", "position", "velocity"])
      iex> ToonEx.Btoon.Dictionary.entries(dict)
      ["player", "position", "velocity"]
      iex> ToonEx.Btoon.Dictionary.ref(dict, "velocity")
      2
  """

  defstruct entries: []

  @type t :: %__MODULE__{entries: [String.t()]}

  @doc "Builds a dictionary from a list of strings."
  @spec new([String.t()]) :: t()
  def new(entries) when is_list(entries) do
    %__MODULE__{entries: entries}
  end

  @doc "Returns the dictionary entries in ref-id order."
  @spec entries(t()) :: [String.t()]
  def entries(%__MODULE__{entries: entries}), do: entries

  @doc """
  Returns the ref id for a string, or `nil` when absent.
  """
  @spec ref(t(), String.t()) :: non_neg_integer() | nil
  def ref(%__MODULE__{entries: entries}, string) when is_binary(string) do
    case Enum.find_index(entries, &(&1 == string)) do
      nil -> nil
      index -> index
    end
  end

  @doc "Returns `true` when the dictionary contains the string."
  @spec member?(t(), String.t()) :: boolean()
  def member?(%__MODULE__{entries: entries}, string), do: string in entries

  @doc "Number of entries in the dictionary."
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{entries: entries}), do: length(entries)
end

defmodule ToonEx.Btoon.Schema do
  @moduledoc """
  A named, typed record schema for schema-mode encoding.

  In schema mode the encoder omits keys and type tags entirely, emitting
  `SchemaID` followed by ordered, fixed-width values. The decoder reads the
  values strictly according to the schema, which is either embedded in the
  envelope (schema flag) or supplied through `ToonEx.Btoon.decode/2` options.

  Field types are `ToonEx.Btoon.ElementType` atoms: fixed-width numeric types
  (`:int8`..`:float64`), plus `:null`, `:bool`, `:string`, `:binary`,
  `:array` and `:object`.

  ## Examples

      iex> schema = ToonEx.Btoon.Schema.new(100, "Player", [
      ...>   %{name: "id", type: :int32},
      ...>   %{name: "x", type: :float32},
      ...>   %{name: "y", type: :float32},
      ...>   %{name: "hp", type: :uint16}
      ...> ])
      iex> ToonEx.Btoon.Schema.fields(schema)
      [%{name: "id", type: :int32}, %{name: "x", type: :float32}, %{name: "y", type: :float32}, %{name: "hp", type: :uint16}]
  """

  defstruct [:id, :name, fields: []]

  @type field :: %{name: String.t(), type: ToonEx.Btoon.Types.element_type()}
  @type t :: %__MODULE__{id: integer(), name: String.t(), fields: [field()]}

  @doc "Builds a schema from an id, name and field list."
  @spec new(integer(), String.t(), [field()]) :: t()
  def new(id, name, fields) when is_integer(id) and is_binary(name) and is_list(fields) do
    %__MODULE__{id: id, name: name, fields: fields}
  end

  @doc "Returns the field definitions."
  @spec fields(t()) :: [field()]
  def fields(%__MODULE__{fields: fields}), do: fields

  @doc "Returns the schema id."
  @spec id(t()) :: integer()
  def id(%__MODULE__{id: id}), do: id

  @doc "Returns the schema name."
  @spec name(t()) :: String.t()
  def name(%__MODULE__{name: name}), do: name

  @doc "Number of fields."
  @spec field_count(t()) :: non_neg_integer()
  def field_count(%__MODULE__{fields: fields}), do: length(fields)
end
