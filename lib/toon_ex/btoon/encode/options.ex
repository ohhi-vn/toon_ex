defmodule ToonEx.Btoon.Encode.Options do
  @moduledoc """
  Validation and normalization of BTOON encoding options.

  ## Options

    * `:dictionary` - a `ToonEx.Btoon.Dictionary` session dictionary, or `nil`.
      Strings present in the dictionary are encoded as `StringRef`.
    * `:string_table` - `:auto` (default) builds a per-message string table
      for strings absent from the session dictionary; `:off` writes full
      strings instead.
    * `:schema` - a `ToonEx.Btoon.Schema` to encode in schema mode, or `nil`.
    * `:typed_arrays` - `true` (default) encodes homogeneous numeric lists
      as `TypedArray` (tag `0x0C`).
    * `:object_tables` - `true` (default) encodes homogeneous object lists as
      columnar `ObjectTable` (tag `0x0D`).
  """

  @defaults %{
    dictionary: nil,
    string_table: :auto,
    schema: nil,
    typed_arrays: true,
    object_tables: true
  }

  @known_keys MapSet.new([:dictionary, :string_table, :schema, :typed_arrays, :object_tables])

  @typedoc "Validated encoding options."
  @type validated :: %{
          dictionary: ToonEx.Btoon.Dictionary.t() | nil,
          string_table: :auto | :off,
          schema: ToonEx.Btoon.Schema.t() | nil,
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
    Enum.reduce_while(opts, {:ok, @defaults}, fn {key, value}, {:ok, acc} ->
      cond do
        not MapSet.member?(@known_keys, key) ->
          {:halt, {:error, "unknown encoding option: #{inspect(key)}"}}

        value == nil and key in [:dictionary, :schema] ->
          {:cont, {:ok, Map.put(acc, key, nil)}}

        true ->
          case validate_value(key, value) do
            :ok -> {:cont, {:ok, Map.put(acc, key, value)}}
            {:error, message} -> {:halt, {:error, message}}
          end
      end
    end)
  end

  def validate(_), do: {:error, "options must be a keyword list"}

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
    do: {:error, "dictionary must be a ToonEx.Btoon.Dictionary, got: #{inspect(other)}"}

  defp validate_value(:schema, %ToonEx.Btoon.Schema{}), do: :ok

  defp validate_value(:schema, other),
    do: {:error, "schema must be a ToonEx.Btoon.Schema, got: #{inspect(other)}"}

  defp validate_value(:string_table, v) when v in [:auto, :on, :off], do: :ok

  defp validate_value(:string_table, v),
    do: {:error, "string_table must be :auto, :on, or :off, got: #{inspect(v)}"}

  defp validate_value(:typed_arrays, v) when is_boolean(v), do: :ok

  defp validate_value(:typed_arrays, v),
    do: {:error, "typed_arrays must be a boolean, got: #{inspect(v)}"}

  defp validate_value(:object_tables, v) when is_boolean(v), do: :ok

  defp validate_value(:object_tables, v),
    do: {:error, "object_tables must be a boolean, got: #{inspect(v)}"}
end
