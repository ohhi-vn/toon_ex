defprotocol ToonEx.Btoon.Encoder do
  @moduledoc """
  Protocol for encoding custom data structures to BTOON format.

  This protocol allows you to define how your custom structs should be
  encoded to BTOON binary format, similar to `ToonEx.Encoder` for TOON text
  and `Jason.Encoder` for JSON.

  ## Deriving

  The protocol leverages Elixir's `@derive` feature. Accepted options are:

    * `:only` - encodes only values of specified keys.
    * `:except` - encodes all struct fields except specified keys.

  By default all keys except the `:__struct__` key are encoded.

  The generated implementation pre-computes key encoding at compile time
  for maximum runtime efficiency (inspired by `Jason.Encoder`). The encoded
  struct becomes a BTOON object with the resulting fields, which the encoder
  recursively encodes using the normal BTOON dispatch (keys are sorted, etc.).

  ## Example

      defmodule User do
        @derive {ToonEx.Btoon.Encoder, only: [:name, :email]}
        defstruct [:id, :name, :email, :password_hash]
      end

      iex> bin = Btoon.encode!(%User{id: 1, name: "Alice", email: "a@example.com"})
      iex> Btoon.decode!(bin)
      %{"name" => "Alice", "email" => "a@example.com"}

  Or implement the protocol manually:

      defimpl ToonEx.Btoon.Encoder, for: User do
        def encode(user, _opts) do
          %{
            "name" => user.name,
            "email" => user.email
          }
        end
      end
  """

  @fallback_to_any true

  @doc """
  Encodes the given value to a BTOON-encodable form.

  Returns a map (or otherwise encodable term) that is then encoded to the
  BTOON binary format by the encoder.
  """
  @spec encode(t(), keyword()) :: term()
  def encode(value, opts)
end

defimpl ToonEx.Btoon.Encoder, for: Any do
  defmacro __deriving__(module, struct, opts) do
    fields = fields_to_encode(struct, opts)

    # Jason/Tool-style: pre-compute key strings at compile time so we avoid
    # runtime to_string/1 calls for every encode. Returns a map so the encoder
    # recurses through its normal value dispatch.
    key_string_pairs =
      Enum.map(fields, fn field ->
        key_str = to_string(field)
        {field, key_str}
      end)

    map_expr =
      Enum.reduce(key_string_pairs, quote(do: %{}), fn {field, key_str}, acc ->
        var = Macro.var(:"__btoon_field_#{field}__", __MODULE__)

        quote do
          Map.put(unquote(acc), unquote(key_str), unquote(var))
        end
      end)

    field_destructs =
      Enum.map(fields, fn field ->
        var = Macro.var(:"__btoon_field_#{field}__", __MODULE__)
        quote do: unquote(var) = Map.get(struct, unquote(field))
      end)

    quote do
      defimpl ToonEx.Btoon.Encoder, for: unquote(module) do
        def encode(struct, _opts) do
          unquote_splicing(field_destructs)
          unquote(map_expr)
        end
      end
    end
  end

  def encode(%_{} = struct, _opts) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: struct,
      description: """
      ToonEx.Btoon.Encoder protocol must be explicitly implemented for structs.

      You can derive the implementation using:

          @derive {ToonEx.Btoon.Encoder, only: [...]}
          defstruct ...

      or:

          @derive ToonEx.Btoon.Encoder
          defstruct ...
      """
  end

  def encode(value, _opts) do
    raise Protocol.UndefinedError,
      protocol: @protocol,
      value: value
  end

  defp fields_to_encode(struct, opts) do
    cond do
      only = Keyword.get(opts, :only) ->
        only

      except = Keyword.get(opts, :except) ->
        Map.keys(struct) -- [:__struct__ | except]

      true ->
        Map.keys(struct) -- [:__struct__]
    end
  end
end
