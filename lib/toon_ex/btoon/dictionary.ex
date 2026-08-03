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

  ## Persistent Term Storage

  For sharing a session dictionary across many processes without deep-copying
  on each message send, use `:persistent_term`:

      iex> dict = Btoon.Dictionary.new(["player", "position", "velocity"])
      iex> Btoon.Dictionary.put_persistent(:session_dict, dict)
      iex> dict = Btoon.Dictionary.get_persistent(:session_dict)
      iex> Btoon.Dictionary.ref(dict, "velocity")
      2

  ## Examples

      iex> dict = ToonEx.Btoon.Dictionary.new(["player", "position", "velocity"])
      iex> ToonEx.Btoon.Dictionary.entries(dict)
      ["player", "position", "velocity"]
      iex> ToonEx.Btoon.Dictionary.ref(dict, "velocity")
      2
  """

  @enforce_keys [:entries, :index, :size, :entries_tuple]
  defstruct entries: [], index: %{}, size: 0, entries_tuple: {}

  @type t :: %__MODULE__{
          entries: [String.t()],
          index: map(),
          size: non_neg_integer(),
          entries_tuple: tuple()
        }

  @doc "Builds a dictionary from a list of strings."
  @spec new([String.t()]) :: t()
  def new(entries) when is_list(entries) do
    index =
      entries
      |> Enum.with_index()
      |> Map.new()

    %__MODULE__{
      entries: entries,
      index: index,
      size: length(entries),
      entries_tuple: List.to_tuple(entries)
    }
  end

  @doc "Returns the dictionary entries in ref-id order."
  @spec entries(t()) :: [String.t()]
  def entries(%__MODULE__{entries: entries}), do: entries

  @doc "Returns the dictionary entries as a tuple for fast indexed access."
  @spec entries_tuple(t()) :: tuple()
  def entries_tuple(%__MODULE__{entries_tuple: entries_tuple}), do: entries_tuple

  @doc """
  Returns the precomputed string → ref-id lookup map for the encoder's hot path.
  """
  @spec lookup(t()) :: %{optional(String.t()) => non_neg_integer()}
  def lookup(%__MODULE__{index: index}), do: index

  @doc """
  Returns the ref id for a string, or `nil` when absent.
  """
  @spec ref(t(), String.t()) :: non_neg_integer() | nil
  def ref(%__MODULE__{index: index}, string) when is_binary(string) do
    Map.get(index, string)
  end

  @doc "Returns `true` when the dictionary contains the string."
  @spec member?(t(), String.t()) :: boolean()
  def member?(%__MODULE__{index: index}, string), do: Map.has_key?(index, string)

  @doc "Number of entries in the dictionary."
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{size: size}), do: size

  @doc """
  Stores a dictionary in `:persistent_term` under the given key.

  Data in `:persistent_term` lives outside process heaps and is shared
  across all processes on the node without copying on read. Updates are
  expensive (global GC), so use only for write-once data like session
  dictionaries negotiated at connection time.

  ## Example

      iex> dict = Btoon.Dictionary.new(["player", "position"])
      iex> Btoon.Dictionary.put_persistent(:my_session_dict, dict)
      :ok
  """
  @spec put_persistent(term(), t()) :: :ok
  def put_persistent(key, dict) do
    :persistent_term.put(key, dict)
  end

  @doc """
  Retrieves a dictionary from `:persistent_term`.

  Returns `{:ok, dict}` or `:error` if the key doesn't exist.
  """
  @spec get_persistent(term()) :: {:ok, t()} | :error
  def get_persistent(key) do
    case :persistent_term.get(key) do
      %__MODULE__{} = dict -> {:ok, dict}
      _ -> :error
    end
  end

  @doc """
  Deletes a dictionary from `:persistent_term`.

  Warning: this triggers a full garbage collection sweep across all
  processes on the node. Use sparingly.
  """
  @spec delete_persistent(term()) :: :ok
  def delete_persistent(key) do
    :persistent_term.erase(key)
  end

  @compile {:inline,
            entries: 1,
            entries_tuple: 1,
            lookup: 1,
            ref: 2,
            member?: 2,
            size: 1,
            new: 1,
            put_persistent: 2,
            get_persistent: 1,
            delete_persistent: 1}
end

defmodule ToonEx.Btoon.Schema do
  @moduledoc """
  A named, typed record schema for schema-mode encoding.

  In schema mode the encoder omits keys and type tags entirely, emitting
  `SchemaID` followed by ordered, fixed-width values. The decoder reads the
  values strictly according to the schema, which is either embedded in the
  envelope (schema flag) or supplied through `Btoon.decode/2` options.

  Field types are `Btoon.ElementType` atoms: fixed-width numeric types
  (`:int8`..`:float64`), plus `:null`, `:bool`, `:string`, `:binary`, `:array`
  and `:object`.

  ## Persistent Term Storage

  For sharing a schema across many processes without deep-copying
  on each message send, use `:persistent_term`:

      iex> schema = Btoon.Schema.new(100, "Player", [%{name: "id", type: :int32}])
      iex> Btoon.Schema.put_persistent(:player_schema, schema)
      iex> schema = Btoon.Schema.get_persistent(:player_schema)
      iex> Btoon.Schema.fields(schema)
      [%{name: "id", type: :int32}]

  ## Examples

      iex> schema = Btoon.Schema.new(100, "Player", [
      ...>   %{name: "id", type: :int32},
      ...>   %{name: "x", type: :float32},
      ...>   %{name: "y", type: :float32},
      ...>   %{name: "hp", type: :uint16}
      ...> ])
      iex> Btoon.Schema.fields(schema)
      [%{name: "id", type: :int32}, %{name: "x", type: :float32}, %{name: "y", type: :float32}, %{name: "hp", type: :uint16}]
  """

  alias ToonEx.Btoon.ElementType

  defstruct [:id, :name, fields: [], envelope: [], envelope_size: 0]

  @type field :: %{name: String.t(), type: ToonEx.Btoon.Types.element_type()}
  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          fields: [field()],
          envelope: iodata(),
          envelope_size: non_neg_integer()
        }

  @doc "Builds a schema from an id, name and field list."
  @spec new(integer(), String.t(), [field()]) :: t()
  def new(id, name, fields) when is_integer(id) and is_binary(name) and is_list(fields) do
    schema = %__MODULE__{id: id, name: name, fields: fields}
    {envelope, size} = build_envelope(id, name, fields)
    %{schema | envelope: envelope, envelope_size: size}
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

  @doc false
  def envelope(%__MODULE__{envelope: envelope}), do: envelope

  @doc false
  def envelope_size(%__MODULE__{envelope_size: size}), do: size

  @doc false
  def envelope(%__MODULE__{id: id, name: name, fields: fields}, id_size) when id_size in [2, 4] do
    {envelope, _} = build_envelope(id, name, fields, id_size)
    envelope
  end

  @doc false
  def envelope_size(%__MODULE__{envelope_size: size}, id_size) when id_size in [2, 4] do
    size - 4 + id_size
  end

  defp build_envelope(id, name, fields, id_size \\ 4) do
    {fields_iodata, fields_size} =
      Enum.reduce(fields, {[], 0}, fn %{name: field_name, type: type}, {acc, size} ->
        case ElementType.type_byte(type) do
          nil ->
            raise ArgumentError, "invalid schema field type: #{inspect(type)}"

          byte ->
            {[[<<byte_size(field_name)::32-little>>, field_name, <<byte>>] | acc],
             size + 5 + byte_size(field_name)}
        end
      end)

    id_bytes =
      case id_size do
        2 -> <<id::16-little>>
        4 -> <<id::32-little>>
      end

    envelope = [
      id_bytes,
      <<byte_size(name)::32-little>>,
      name,
      <<length(fields)::32-little>>,
      :lists.reverse(fields_iodata)
    ]

    {envelope, id_size + 4 + byte_size(name) + 4 + fields_size}
  end

  @doc """
  Stores a schema in `:persistent_term` under the given key.

  Data in `:persistent_term` lives outside process heaps and is shared
  across all processes on the node without copying on read. Updates are
  expensive (global GC), so use only for write-once data like schemas
  defined at application startup.

  ## Example

      iex> schema = Btoon.Schema.new(100, "Player", [%{name: "id", type: :int32}])
      iex> Btoon.Schema.put_persistent(:player_schema, schema)
      :ok
  """
  @spec put_persistent(term(), t()) :: :ok
  def put_persistent(key, schema) do
    :persistent_term.put(key, schema)
  end

  @doc """
  Retrieves a schema from `:persistent_term`.

  Returns `{:ok, schema}` or `:error` if the key doesn't exist.
  """
  @spec get_persistent(term()) :: {:ok, t()} | :error
  def get_persistent(key) do
    case :persistent_term.get(key) do
      %__MODULE__{} = schema -> {:ok, schema}
      _ -> :error
    end
  end

  @doc """
  Deletes a schema from `:persistent_term`.

  Warning: this triggers a full garbage collection sweep across all
  processes on the node. Use sparingly.
  """
  @spec delete_persistent(term()) :: :ok
  def delete_persistent(key) do
    :persistent_term.erase(key)
  end

  @compile {:inline,
            fields: 1,
            id: 1,
            name: 1,
            field_count: 1,
            envelope: 1,
            envelope_size: 1,
            new: 3,
            put_persistent: 2,
            get_persistent: 1,
            delete_persistent: 1}
end
