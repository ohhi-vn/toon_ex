defmodule ToonEx do
  @moduledoc """
  TOON (Token-Oriented Object Notation) encoder and decoder for Elixir.

  TOON is a compact data format optimized for LLM token efficiency, achieving
  30-60% token reduction compared to JSON while maintaining readability.

  ## Features

  - **Token Efficient**: 30-60% fewer tokens than JSON
  - **Human Readable**: Indentation-based structure like YAML
  - **Three Array Formats**: Inline, tabular, and list formats
  - **Type Safe**: Full Dialyzer support with comprehensive typespecs
  - **Protocol Support**: Custom encoding via `ToonEx.Encoder` protocol
  - **Fragment Support**: Inject pre-encoded TOON via `ToonEx.Fragment`
  - **Compile-time Helpers**: Partial compile-time encoding via `ToonEx.Helpers`

  ## Quick Start

      # Encode Elixir data to TOON
      iex> ToonEx.encode!(%{"name" => "Alice", "age" => 30})
      "age: 30\\nname: Alice"

      # Decode TOON to Elixir data
      iex> ToonEx.decode!("name: Alice\\nage: 30")
      %{"name" => "Alice", "age" => 30}

      # Arrays
      iex> ToonEx.encode!(%{"tags" => ["elixir", "toon"]})
      "tags[2]: elixir,toon"

      # Nested objects
      iex> ToonEx.encode!(%{"user" => %{"name" => "Bob"}})
      "user:\\n  name: Bob"

  ## Options

  ### Encoding Options

    * `:indent` - Number of spaces for indentation (default: 2)
    * `:delimiter` - Delimiter for array values: "," | "\\t" | "|" (default: ",")
    * `:length_marker` - Prefix for array length marker (default: nil)
    * `:key_folding` - Key folding mode: `:off` | `:safe` (default: `:off`)
    * `:flatten_depth` - Max depth for key folding: non-negative integer or `:infinity` (default: `:infinity`)

  ### Decoding Options

    * `:keys` - How to decode map keys: `:strings` | `:atoms` | `:atoms!` (default: `:strings`)
    * `:strict` - Enable strict mode validation (default: `true`)
    * `:indent_size` - Expected indentation size in spaces (default: 2)
    * `:expand_paths` - Path expansion mode: `:off` | `:safe` (default: `:off`)

  ### Fragment Encoding

  You can inject pre-encoded TOON data using `ToonEx.Fragment` to avoid
  decode/encode round-trips (e.g., for cached or externally-generated TOON):

      fragment = ToonEx.Fragment.new("name: Alice\\nage: 30")
      ToonEx.encode!(%{"user" => fragment})
      #=> "user:\\n  name: Alice\\n  age: 30"

  ### Compile-time Encoding

  `ToonEx.Helpers` provides macros for partial compile-time encoding,
  where keys are validated and encoded at compile time:

      require ToonEx.Helpers
      fragment = ToonEx.Helpers.toon_map(name: "Alice", age: 30)
      ToonEx.encode!(fragment)
      #=> "age: 30\\nname: Alice"

  ### Custom Encoding

  You can implement the `ToonEx.Encoder` protocol for your structs:

      defmodule User do
        @derive {ToonEx.Encoder, only: [:name, :email]}
        defstruct [:id, :name, :email, :password_hash]
      end

      user = %User{id: 1, name: "Alice", email: "alice@example.com"}
      ToonEx.encode!(user)
      #=> "name: Alice\\nemail: alice@example.com"
  """

  alias ToonEx.{Decode, DecodeError, Encode, EncodeError}

  @doc """
  Encodes Elixir data to TOON format.

  Returns `{:ok, toon_string}` on success, or `{:error, error}` on failure.

  ## Options

    * `:indent` - Number of spaces for indentation (default: 2)
    * `:delimiter` - Delimiter for array values: "," | "\\t" | "|" (default: ",")
    * `:length_marker` - Prefix for array length marker (default: nil)
    * `:key_folding` - Key folding mode: `:off` | `:safe` (default: `:off`)
    * `:flatten_depth` - Max depth for key folding: non-negative integer or `:infinity` (default: `:infinity`)

  ## Examples

      iex> ToonEx.encode(%{"name" => "Alice"})
      {:ok, "name: Alice"}

      iex> ToonEx.encode(%{"tags" => ["a", "b"]})
      {:ok, "tags[2]: a,b"}

      iex> ToonEx.encode(%{"user" => %{"name" => "Bob"}})
      {:ok, "user:\\n  name: Bob"}

      iex> ToonEx.encode(%{"data" => [1, 2, 3]}, delimiter: "\\t")
      {:ok, "data[3\\t]: 1\\t2\\t3"}
  """
  @spec encode(ToonEx.Types.input(), keyword()) ::
          {:ok, String.t()} | {:error, EncodeError.t()}
  defdelegate encode(data, opts \\ []), to: Encode

  @doc """
  Encodes Elixir data to TOON format, raising on error.

  ## Examples

      iex> ToonEx.encode!(%{"name" => "Alice"})
      "name: Alice"

      iex> ToonEx.encode!(%{"tags" => ["a", "b"]})
      "tags[2]: a,b"

      iex> ToonEx.encode!(%{"count" => 42, "active" => true})
      "active: true\\ncount: 42"
  """
  @spec encode!(ToonEx.Types.input(), keyword()) :: String.t()
  defdelegate encode!(data, opts \\ []), to: Encode

  @spec encode!(ToonEx.Types.input(), keyword()) :: iodata()
  defdelegate encode_to_iodata!(data, opts \\ []), to: Encode

  @doc """
  Decodes TOON format string to Elixir data.

  Returns `{:ok, data}` on success, or `{:error, error}` on failure.

  ## Options

    * `:keys` - How to decode map keys: `:strings` | `:atoms` | `:atoms!` (default: `:strings`)
    * `:strict` - Enable strict mode validation (default: `true`)
    * `:indent_size` - Expected indentation size in spaces (default: 2)
    * `:expand_paths` - Path expansion mode: `:off` | `:safe` (default: `:off`)

  ## Examples

      iex> ToonEx.decode("name: Alice")
      {:ok, %{"name" => "Alice"}}

      iex> ToonEx.decode("tags[2]: a,b")
      {:ok, %{"tags" => ["a", "b"]}}
  """
  @spec decode(String.t(), keyword()) ::
          {:ok, ToonEx.Types.encodable()} | {:error, DecodeError.t()}
  defdelegate decode(string, opts \\ []), to: Decode

  @doc """
  Decodes TOON format string to Elixir data, raising on error.

  ## Examples

      iex> ToonEx.decode!("name: Alice")
      %{"name" => "Alice"}
  """
  @spec decode!(String.t(), keyword()) :: ToonEx.Types.encodable()
  defdelegate decode!(string, opts \\ []), to: Decode
end
