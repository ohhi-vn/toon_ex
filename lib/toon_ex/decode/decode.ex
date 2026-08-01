defmodule ToonEx.Decode do
  @moduledoc """
  Main decoder for TOON format.

  Parses TOON format strings and converts them to Elixir data structures.
  """

  alias ToonEx.Decode.{Options, Fast, StructuralParser}
  alias ToonEx.DecodeError

  @typedoc "Decoded TOON value"
  @type decoded :: nil | boolean() | binary() | number() | list() | map()

  @doc """
  Decodes a TOON format string to Elixir data.

  ## Options

    * `:keys` - How to decode map keys: `:strings` | `:atoms` | `:atoms!` (default: `:strings`)
    * `:strict` - Enable strict mode validation (default: `true`)
    * `:indent_size` - Expected indentation size in spaces (default: 2)
    * `:expand_paths` - Path expansion mode: `:off` | `:safe` (default: `:off`)

  ## Examples

      iex> ToonEx.Decode.decode("name: Alice")
      {:ok, %{"name" => "Alice"}}

      iex> ToonEx.Decode.decode("age: 30")
      {:ok, %{"age" => 30}}

      iex> ToonEx.Decode.decode("tags[2]: a,b")
      {:ok, %{"tags" => ["a", "b"]}}

      iex> ToonEx.Decode.decode("name: Alice", keys: :atoms)
      {:ok, %{name: "Alice"}}
  """
  @spec decode(String.t(), keyword()) :: {:ok, term()} | {:error, DecodeError.t()}
  def decode(string, opts \\ []) when is_binary(string) do
    case Options.validate(opts) do
      {:ok, validated_opts} ->
        try do
          # Use StructuralParser for strict mode with custom indent_size
          # as it has the full depth jump validation
          if validated_opts.strict && validated_opts.indent_size != 2 do
            case StructuralParser.parse(string, validated_opts) do
              {:ok, {result, _metadata}} -> {:ok, result}
              {:error, error} -> {:error, error}
            end
          else
            decoded = do_decode(string, validated_opts)
            {:ok, decoded}
          end
        rescue
          e in DecodeError ->
            {:error, e}

          e ->
            {:error,
             DecodeError.exception(
               message: "Decode failed: #{Exception.message(e)}",
               input: string
             )}
        end

      {:error, error} ->
        {:error,
         DecodeError.exception(
           message: "Invalid options: #{Exception.message(error)}",
           reason: error
         )}
    end
  end

  @doc """
  Decodes a TOON format string to Elixir data, raising on error.

  ## Examples

      iex> ToonEx.Decode.decode!("name: Alice")
      %{"name" => "Alice"}

      iex> ToonEx.Decode.decode!("count: 42")
      %{"count" => 42}
  """
  @spec decode!(String.t(), keyword()) :: decoded()
  def decode!(string, opts \\ []) when is_binary(string) do
    case decode(string, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  # Private functions

  @spec do_decode(String.t(), map()) :: decoded()
  defp do_decode(string, opts) do
    # Use high-performance Fast.Decoder with pure binary pattern matching
    # No NimbleParsec, no regex in hot paths, zero-copy slicing
    case Fast.Decoder.decode(string, Map.to_list(opts)) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end
end
