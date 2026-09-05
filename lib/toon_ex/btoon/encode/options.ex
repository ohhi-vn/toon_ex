defmodule ToonEx.Btoon.Encode.Options do
  @moduledoc """
  Validation and normalization of BTOON encoding options.

  ## Options

    * `:dictionary` - a `Btoon.Dictionary` session dictionary, or `nil`.
      Strings present in the dictionary are encoded as `StringRef`.
    * `:string_table` - `:auto` (default) builds a per-message string table
      for strings absent from the session dictionary; `:off` writes full
      strings instead.
    * `:no_string_table` - `true` omits the per-message string table entirely.
      Requires `:dictionary` to be set. When enabled, all strings MUST be in
      the session dictionary or written inline. Overrides `:string_table`.
    * `:schema` - a `Btoon.Schema` to encode in schema mode, or `nil`.
    * `:schema_id_uint16` - `true` encodes the schema ID as UInt16 (2 bytes)
      instead of UInt32 (4 bytes). Requires `:schema` to be set.
    * `:typed_arrays` - `true` (default) encodes homogeneous numeric lists
      as `TypedArray` (tag `0x0C`).
    * `:object_tables` - `true` (default) encodes homogeneous object lists as
      columnar `ObjectTable` (tag `0x0D`).
  """

  @defaults %{
    dictionary: nil,
    string_table: :auto,
    no_string_table: false,
    schema: nil,
    schema_id_uint16: false,
    typed_arrays: true,
    object_tables: true
  }

  @known_keys MapSet.new([
                :dictionary,
                :string_table,
                :no_string_table,
                :schema,
                :schema_id_uint16,
                :typed_arrays,
                :object_tables
              ])

  @typedoc "Validated encoding options."
  @type validated :: %{
          dictionary: ToonEx.Btoon.Dictionary.t() | nil,
          string_table: :auto | :off,
          no_string_table: boolean(),
          schema: ToonEx.Btoon.Schema.t() | nil,
          schema_id_uint16: boolean(),
          typed_arrays: boolean(),
          object_tables: boolean()
        }

  @doc "Returns the default validated options."
  @spec defaults() :: validated()
  def defaults, do: @defaults

  @doc """
  Validates encoding options.

  Returns `{:ok, validated}` or `{:error, message}`.
  """
  @spec validate(keyword()) :: {:ok, validated()} | {:error, String.t()}
  def validate([]), do: {:ok, @defaults}

  def validate(opts) when is_list(opts) do
    case validate_opts(opts, @defaults) do
      {:ok, validated} -> cross_validate(validated)
      error -> error
    end
  end

  def validate(_), do: {:error, "options must be a keyword list"}

  defp validate_opts([], acc), do: {:ok, acc}

  defp validate_opts([{key, value} | rest], acc) do
    cond do
      not MapSet.member?(@known_keys, key) ->
        {:error, "unknown encoding option: #{inspect(key)}"}

      value == nil and key in [:dictionary, :schema] ->
        validate_opts(rest, Map.put(acc, key, nil))

      true ->
        case validate_value(key, value) do
          :ok -> validate_opts(rest, Map.put(acc, key, value))
          {:error, message} -> {:error, message}
        end
    end
  end

  defp cross_validate(validated) do
    cond do
      validated.no_string_table && !validated.dictionary ->
        {:error, "no_string_table requires a dictionary to be set"}

      validated.schema_id_uint16 && !validated.schema ->
        {:error, "schema_id_uint16 requires a schema to be set"}

      validated.schema_id_uint16 &&
          (validated.schema.id < 0 or validated.schema.id > 65_535) ->
        {:error, "schema_id_uint16 requires a schema id in 0..65535"}

      true ->
        {:ok, validated}
    end
  end

  @doc """
  Validates encoding options, raising `ArgumentError` on error.
  """
  @spec validate!(keyword()) :: validated()
  def validate!(opts) do
    case validate(opts) do
      {:ok, validated} -> validated
      {:error, message} -> raise ArgumentError, message
    end
  end

  defp validate_value(:dictionary, %ToonEx.Btoon.Dictionary{}), do: :ok

  defp validate_value(:dictionary, other),
    do: {:error, "dictionary must be a Btoon.Dictionary, got: #{inspect(other)}"}

  defp validate_value(:schema, %ToonEx.Btoon.Schema{}), do: :ok

  defp validate_value(:schema, other),
    do: {:error, "schema must be a Btoon.Schema, got: #{inspect(other)}"}

  defp validate_value(:string_table, v) when v in [:auto, :on, :off], do: :ok

  defp validate_value(:string_table, v),
    do: {:error, "string_table must be :auto, :on, or :off, got: #{inspect(v)}"}

  defp validate_value(:no_string_table, v) when is_boolean(v), do: :ok

  defp validate_value(:no_string_table, v),
    do: {:error, "no_string_table must be a boolean, got: #{inspect(v)}"}

  defp validate_value(:schema_id_uint16, v) when is_boolean(v), do: :ok

  defp validate_value(:schema_id_uint16, v),
    do: {:error, "schema_id_uint16 must be a boolean, got: #{inspect(v)}"}

  defp validate_value(:typed_arrays, v) when is_boolean(v), do: :ok

  defp validate_value(:typed_arrays, v),
    do: {:error, "typed_arrays must be a boolean, got: #{inspect(v)}"}

  defp validate_value(:object_tables, v) when is_boolean(v), do: :ok

  defp validate_value(:object_tables, v),
    do: {:error, "object_tables must be a boolean, got: #{inspect(v)}"}

  @compile {:inline, validate: 1, validate!: 1, defaults: 0}
end
