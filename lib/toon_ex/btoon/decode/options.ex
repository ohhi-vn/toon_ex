defmodule ToonEx.Btoon.Decode.Options do
  @moduledoc """
  Validation and normalization of BTOON decoding options.

  ## Options

    * `:dictionary` - a `Btoon.Dictionary` session dictionary shared with the
      encoder. `StringRef` ids are resolved against the session entries first,
      then the per-message string table carried in the envelope.
    * `:schema` - a `Btoon.Schema` used to decode a tagless schema body when
      the envelope does not carry the schema flag (schema negotiated out of
      band). When the schema flag is set, the embedded schema always wins.
    * `:keys` - how object keys are returned: `:strings` (default),
      `:atoms` (uses `String.to_atom/1`) or `:atoms!` (uses
      `String.to_existing_atom/1`).
    * `:typed_arrays` - `:lists` (default) materializes `TypedArray` and
      `ObjectTable` payloads as lists; `:views` returns the wrapper structs
      holding zero-copy sub-binary slices.
    * `:max_depth` - maximum nesting depth for tagged values (default `100`).
    * `:max_string_size` - maximum inline string size in bytes (default `1_048_576`).
    * `:max_binary_size` - maximum binary size in bytes (default `16_777_216`).
    * `:max_container_count` - maximum array/object/table count (default `1_000_000`).
  """

  alias ToonEx.Btoon

  @defaults %{
    dictionary: nil,
    schema: nil,
    keys: :strings,
    typed_arrays: :lists,
    max_depth: 100,
    max_string_size: 1_048_576,
    max_binary_size: 16_777_216,
    max_container_count: 1_000_000
  }

  @known_keys MapSet.new([
                :dictionary,
                :schema,
                :keys,
                :typed_arrays,
                :max_depth,
                :max_string_size,
                :max_binary_size,
                :max_container_count
              ])

  @typedoc "Validated decoding options."
  @type validated :: %{
          dictionary: Btoon.Dictionary.t() | nil,
          schema: Btoon.Schema.t() | nil,
          keys: :strings | :atoms | :atoms!,
          typed_arrays: :lists | :views,
          max_depth: pos_integer(),
          max_string_size: pos_integer(),
          max_binary_size: pos_integer(),
          max_container_count: pos_integer()
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
    validate_opts(opts, @defaults)
  end

  def validate(_), do: {:error, "options must be a keyword list"}

  defp validate_opts([], acc), do: {:ok, acc}

  defp validate_opts([{key, value} | rest], acc) do
    cond do
      not MapSet.member?(@known_keys, key) ->
        {:error, "unknown decoding option: #{inspect(key)}"}

      value == nil and key in [:dictionary, :schema] ->
        validate_opts(rest, Map.put(acc, key, nil))

      true ->
        case validate_value(key, value) do
          :ok -> validate_opts(rest, Map.put(acc, key, value))
          {:error, message} -> {:error, message}
        end
    end
  end

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

  @doc """
  Decodes a BTOON binary using pre-validated options.

  This avoids re-validating options on each call, improving performance for
  repeated decoding with the same options.
  """
  @spec decode_validated(binary(), validated()) ::
          {:ok, term()} | {:error, Btoon.DecodeError.t()}
  def decode_validated(binary, validated_opts) do
    Btoon.Decode.decode_validated(binary, validated_opts)
  end

  @doc """
  Decodes a BTOON binary using pre-validated options, raising on error.

  This avoids re-validating options on each call, improving performance for
  repeated decoding with the same options.
  """
  @spec decode_validated!(binary(), validated()) :: term()
  def decode_validated!(binary, validated_opts) do
    Btoon.Decode.decode_validated!(binary, validated_opts)
  end

  defp validate_value(:dictionary, %Btoon.Dictionary{}), do: :ok

  defp validate_value(:dictionary, other),
    do: {:error, "dictionary must be a Btoon.Dictionary, got: #{inspect(other)}"}

  defp validate_value(:schema, %Btoon.Schema{}), do: :ok

  defp validate_value(:schema, other),
    do: {:error, "schema must be a Btoon.Schema, got: #{inspect(other)}"}

  defp validate_value(:keys, v) when v in [:strings, :atoms, :atoms!], do: :ok

  defp validate_value(:keys, v),
    do: {:error, "keys must be :strings, :atoms or :atoms!, got: #{inspect(v)}"}

  defp validate_value(:typed_arrays, v) when v in [:lists, :views], do: :ok

  defp validate_value(:typed_arrays, v),
    do: {:error, "typed_arrays must be :lists or :views, got: #{inspect(v)}"}

  defp validate_value(:max_depth, v) when is_integer(v) and v > 0, do: :ok

  defp validate_value(:max_depth, v),
    do: {:error, "max_depth must be a positive integer, got: #{inspect(v)}"}

  defp validate_value(key, v)
       when key in [:max_string_size, :max_binary_size, :max_container_count] and
              is_integer(v) and v > 0,
       do: :ok

  defp validate_value(key, v)
       when key in [:max_string_size, :max_binary_size, :max_container_count],
       do: {:error, "#{key} must be a positive integer, got: #{inspect(v)}"}

  @compile {:inline,
            validate: 1, validate!: 1, defaults: 0, decode_validated: 2, decode_validated!: 2}
end
