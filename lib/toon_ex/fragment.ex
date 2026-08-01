defmodule ToonEx.Fragment do
  @moduledoc """
  Provides a way to inject an already-encoded TOON structure into a
  to-be-encoded structure in optimized fashion.

  This avoids a decoding/encoding round-trip for the subpart.

  This feature can be used for caching parts of the TOON output, or delegating
  the generation of the TOON to a third-party system (e.g. Postgres).

  ## Examples

      # From pre-encoded iodata
      fragment = ToonEx.Fragment.new("name: Alice")
      ToonEx.encode!(%{"user" => fragment})
      #=> "user:\\n  name: Alice"

      # From an encoding function (lazy evaluation)
      fragment = ToonEx.Fragment.new(fn _opts -> "name: Alice" end)
      ToonEx.encode!(%{"user" => fragment})
      #=> "user:\\n  name: Alice"
  """

  defstruct [:encode, :encode_key]

  @type t :: %__MODULE__{
          encode: (keyword() -> iodata()),
          encode_key: (keyword() -> iodata()) | nil
        }

  @doc """
  Creates a new fragment from pre-encoded iodata or an encoding function.

  When given iodata (a binary or list), it will be returned as-is when the
  fragment is encoded. When given a function, it receives the encoding options
  and must return iodata — this allows lazy evaluation of the fragment content.

  ## Examples

      # From pre-encoded iodata
      fragment = ToonEx.Fragment.new("name: Alice")
      ToonEx.encode!(%{"user" => fragment})
      #=> "user:\\n  name: Alice"

      # From an encoding function (lazy evaluation)
      fragment = ToonEx.Fragment.new(fn _opts -> "name: Alice" end)
      ToonEx.encode!(%{"user" => fragment})
      #=> "user:\\n  name: Alice"
  """
  @spec new(iodata() | (keyword() -> iodata())) :: t()
  def new(iodata) when is_list(iodata) or is_binary(iodata) do
    %__MODULE__{
      encode: fn _opts -> iodata end
    }
  end

  def new(encode) when is_function(encode, 1) do
    %__MODULE__{
      encode: encode
    }
  end
end
