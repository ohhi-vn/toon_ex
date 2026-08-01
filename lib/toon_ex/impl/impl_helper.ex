defmodule ToonEx.ToonImplHelper do
  @moduledoc """
  Helper macro for generating ToonEx.Encoder protocol implementations.

  Allows modules to easily implement the ToonEx.Encoder protocol by providing
  a list of modules that have an `encode!` function.
  """
  @doc """
  Macro to generate simple implementation of protocol.
  Support for easy to use with ToonEx.Encoder.

  Utility macro to generate implementation for ToonEx.Encoder.

  The target struct must have `encode!` function for real encoding struct data to TOON in module.

  Usage:

  ```Elixir
  use ToonEx.ToonImplHelper, impl: [AModule1, AModule2, ...]
  ```

  Using macro without option in `use` keyword.
  Target module must have `encode!` function
  Generate implementation for ToonEx.Encoder like this:

  ```Elixir
  gen_impl AModule
  ```
  """

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      list_module = Keyword.get(opts, :impl, [])

      for mod <- list_module do
        ToonEx.ToonImplHelper.gen_impl(mod)
      end
    end
  end

  defmacro gen_impl(mod) do
    quote do
      defimpl ToonEx.Encoder, for: unquote(mod) do
        def encode(%unquote(mod){} = data, opts) do
          data
          |> unquote(mod).encode!(opts)
        end
      end
    end
  end
end
