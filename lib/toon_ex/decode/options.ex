defmodule ToonEx.Decode.Options do
  @moduledoc """
  Validation and normalization of decoding options.
  """

  alias ToonEx.Options.Validator

  @options_schema [
    keys: [
      type: {:in, [:strings, :atoms, :atoms!]},
      default: :strings,
      doc: "How to decode map keys: :strings | :atoms | :atoms!"
    ],
    strict: [
      type: :boolean,
      default: true,
      doc: "Enable strict mode validation (indentation, blank lines, etc.)"
    ],
    indent_size: [
      type: :pos_integer,
      default: 2,
      doc: "Expected indentation size in spaces (for strict mode validation)"
    ],
    expand_paths: [
      type: {:in, [:off, :safe]},
      default: :off,
      doc: "Path expansion: 'off' | 'safe' (expand unquoted dotted keys)"
    ]
  ]

  @schema_keys MapSet.new(Keyword.keys(@options_schema))

  @default_validated %{
    keys: :strings,
    strict: true,
    indent_size: 2,
    expand_paths: :off
  }

  @doc """
  Returns the options schema.
  """
  @spec schema() :: keyword()
  def schema, do: @options_schema

  @doc """
  Validates and normalizes decoding options.

  ## Examples

      iex> ToonEx.Decode.Options.validate([])
      {:ok, %{keys: :strings, strict: true, indent_size: 2}}

      iex> ToonEx.Decode.Options.validate(keys: :atoms)
      {:ok, %{keys: :atoms, strict: true, indent_size: 2}}

      iex> match?({:error, _}, ToonEx.Decode.Options.validate(keys: :invalid))
      true
  """
  @spec validate(keyword()) :: {:ok, map()} | {:error, Validator.t()}
  def validate([]), do: {:ok, @default_validated}

  def validate(opts) when is_list(opts) do
    case Validator.validate(opts, @options_schema, @schema_keys) do
      {:ok, validated} -> {:ok, Map.new(validated)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Validates and normalizes decoding options, raising on error.
  """
  @spec validate!(keyword()) :: map()
  def validate!([]), do: @default_validated

  def validate!(opts) when is_list(opts) do
    case validate(opts) do
      {:ok, validated} -> validated
      {:error, error} -> raise ArgumentError, Exception.message(error)
    end
  end
end
