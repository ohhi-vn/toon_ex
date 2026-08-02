defmodule ToonEx.Btoon.Decode.Options do
  @moduledoc """
  Validation and normalization of BTOON decoding options.

  ## Options

    * `:dictionary` - a `ToonEx.Btoon.Dictionary` session dictionary shared with the
      encoder. `StringRef` ids are resolved against the session entries first,
      then the per-message string table carried in the envelope.
    * `:schema` - a `ToonEx.Btoon.Schema` used to decode a tagless schema body when
      the envelope does not carry the schema flag (schema negotiated out of
      band). When the schema flag is set, the embedded schema always wins.
    * `:keys` - how object keys are returned: `:strings` (default),
      `:atoms` (uses `String.to_atom/1`) or `:atoms!` (uses
      `String.to_existing_atom/1`).
    * `:typed_arrays` - `:lists` (default) materializes `TypedArray` and
      `ObjectTable` payloads as lists; `:views` returns the wrapper structs
      holding zero-copy sub-binary slices.
    * `:max_depth` - maximum nesting depth for tagged values (default `100`).
  """

  @defaults %{
    dictionary: nil,
    schema: nil,
    keys: :strings,
    typed_arrays: :lists,
    max_depth: 100
  }

  @known_keys MapSet.new([:dictionary, :schema, :keys, :typed_arrays, :max_depth])

  @typedoc "Validated decoding options."
  @type validated :: %{
          dictionary: ToonEx.Btoon.Dictionary.t() | nil,
          schema: ToonEx.Btoon.Schema.t() | nil,
          keys: :strings | :atoms | :atoms!,
          typed_arrays: :lists | :views,
          max_depth: pos_integer()
        }

  @doc "Returns the default validated options."
  @spec defaults() :: validated()
  def defaults, do: @defaults

  @doc """
  Validates decoding options.

  Returns `{:ok, validated}` or `{:error, message}`.
  """
  @spec validate(keyword()) :: {:ok, validated()} | {:error, String.t()}
  def validate([]), do: {:ok, @defaults}

  def validate(opts) when is_list(opts) do
    Enum.reduce_while(opts, {:ok, @defaults}, fn {key, value}, {:ok, acc} ->
      cond do
        not MapSet.member?(@known_keys, key) ->
          {:halt, {:error, "unknown decoding option: #{inspect(key)}"}}

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
  Validates decoding options, raising `ArgumentError` on error.
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

  defp validate_value(:keys, v) when v in [:strings, :atoms, :atoms!], do: :ok

  defp validate_value(:keys, v),
    do: {:error, "keys must be :strings, :atoms or :atoms!, got: #{inspect(v)}"}

  defp validate_value(:typed_arrays, v) when v in [:lists, :views], do: :ok

  defp validate_value(:typed_arrays, v),
    do: {:error, "typed_arrays must be :lists or :views, got: #{inspect(v)}"}

  defp validate_value(:max_depth, v) when is_integer(v) and v > 0, do: :ok

  defp validate_value(:max_depth, v),
    do: {:error, "max_depth must be a positive integer, got: #{inspect(v)}"}
end
