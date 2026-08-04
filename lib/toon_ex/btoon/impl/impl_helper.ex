defmodule ToonEx.Btoon.ImplHelper do
  @moduledoc """
  Helper macro for generating ToonEx.Btoon.Encoder protocol implementations.

  Allows modules to easily implement the ToonEx.Btoon.Encoder protocol by
  providing a list of modules that have an `encode!` function. Mirrors
  `ToonEx.Btoon.ImplHelper` for the TOON text encoder, but targets the BTOON
  binary `ToonEx.Btoon.Encoder` protocol instead.

  ## Usage

  The target struct must have an `encode!` function for real encoding of the
  struct data to BTOON in the module, returning a BTOON-encodable term (such
  as a map with string keys):

  ```Elixir
  use ToonEx.Btoon.ImplHelper, impl: [AModule1, AModule2, ...]
  ```

  or directly:

  ```Elixir
  ToonEx.Btoon.ImplHelper.gen_impl AModule
  ```
  """

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      list_module = Keyword.get(opts, :modules, Keyword.get(opts, :impl, []))

      for mod <- list_module do
        ToonEx.Btoon.ImplHelper.gen_impl(mod)
      end
    end
  end

  defmacro gen_impl(mod) do
    quote do
      defimpl ToonEx.Btoon.Encoder, for: unquote(mod) do
        def encode(%unquote(mod){} = data, opts) do
          data
          |> unquote(mod).encode!(opts)
        end
      end
    end
  end
end
