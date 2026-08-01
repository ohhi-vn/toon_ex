defmodule ToonEx.Encode.Options do
  @moduledoc """
  Validation and normalization of encoding options.
  """

  alias ToonEx.Constants
  alias ToonEx.Options.Validator

  @typedoc "Validated encoding options"
  @type validated :: %{
          indent: pos_integer(),
          delimiter: String.t(),
          length_marker: String.t() | nil,
          key_order: term(),
          indent_string: String.t()
        }

  @options_schema [
    indent: [
      type: :pos_integer,
      default: 2,
      doc: "Number of spaces for indentation"
    ],
    indent_size: [
      type: :non_neg_integer,
      default: 2,
      doc: "Indentation size in spaces (used by decoder)"
    ],
    delimiter: [
      type: :string,
      default: ",",
      doc: "Delimiter for array values (comma, tab, or pipe)"
    ],
    length_marker: [
      type: {:or, [:string, nil]},
      default: nil,
      doc: "Prefix for array length marker (e.g., '#' produces '[#3]')"
    ],
    key_order: [
      type: :any,
      default: nil,
      doc: "Key ordering information for preserving map key order"
    ],
    key_folding: [
      type: {:in, [:off, :safe]},
      default: :off,
      doc: "Key folding: 'off' | 'safe' (fold single-key chains to dotted paths)"
    ],
    flatten_depth: [
      type: {:or, [:non_neg_integer, {:in, [:infinity]}]},
      default: :infinity,
      doc: "Max depth for key folding (0 = no folding, :infinity = unlimited)"
    ]
  ]

  @schema_keys MapSet.new(Keyword.keys(@options_schema))

  @default_validated %{
    indent: 2,
    indent_size: 2,
    delimiter: ",",
    length_marker: nil,
    key_order: nil,
    key_folding: :off,
    flatten_depth: :infinity,
    indent_string: "  "
  }

  @doc """
  Returns the options schema.
  """
  @spec schema() :: keyword()
  def schema, do: @options_schema

  @doc """
  Validates and normalizes encoding options.

  ## Examples

      iex> ToonEx.Encode.Options.validate([])
      {:ok, %{indent: 2, delimiter: ",", length_marker: nil, indent_string: "  "}}

      iex> ToonEx.Encode.Options.validate(indent: 4, delimiter: "\t")
      {:ok, %{indent: 4, delimiter: "\t", length_marker: nil, indent_string: "    "}}

      iex> match?({:error, _}, ToonEx.Encode.Options.validate(indent: -1))
      true

      iex> match?({:error, _}, ToonEx.Encode.Options.validate(delimiter: "invalid"))
      true
  """
  @spec validate(keyword()) :: {:ok, map()} | {:error, Validator.t()}
  def validate([]), do: {:ok, @default_validated}

  def validate(opts) when is_list(opts) do
    case Validator.validate(opts, @options_schema, @schema_keys) do
      {:ok, validated} ->
        validated_map = Map.new(validated)

        if valid_delimiter?(validated_map.delimiter) do
          validated_with_indent =
            Map.put(validated_map, :indent_string, String.duplicate(" ", validated_map.indent))

          {:ok, validated_with_indent}
        else
          {:error,
           %Validator{
             key: :delimiter,
             value: validated_map.delimiter,
             message:
               "must be one of: ',' (comma), '\\t' (tab), or '|' (pipe), got: #{inspect(validated_map.delimiter)}"
           }}
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Validates and normalizes encoding options, raising on error.

  ## Examples

      iex> ToonEx.Encode.Options.validate!([])
      %{indent: 2, delimiter: ",", length_marker: nil, indent_string: "  "}

      iex> ToonEx.Encode.Options.validate!(indent: 4)
      %{indent: 4, delimiter: ",", length_marker: nil, indent_string: "    "}
  """
  @spec validate!(keyword()) :: validated()
  def validate!([]), do: @default_validated

  def validate!(opts) do
    case validate(opts) do
      {:ok, validated} -> validated
      {:error, error} -> raise ArgumentError, Exception.message(error)
    end
  end

  defp valid_delimiter?(delimiter) do
    delimiter in Constants.valid_delimiters()
  end
end
