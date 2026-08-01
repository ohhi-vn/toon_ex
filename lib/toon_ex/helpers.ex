defmodule ToonEx.Helpers do
  @moduledoc """
  Provides macro facilities for partial compile-time encoding of TOON.

  These macros encode keys at compile time and strive to create as flat an
  iodata structure as possible to achieve maximum efficiency. The encoding
  happens right at the call site, but returns a `%ToonEx.Fragment{}` struct
  that needs to be passed to one of the "main" encoding functions — for example
  `ToonEx.encode!/2` for final encoding into TOON — this makes it completely
  transparent for most uses.

  Only allows keys that are safe unquoted TOON keys (matching `^[A-Za-z_][A-Za-z0-9_.]*$`).

  ## Example

      # Compile-time encoded map fragment
      fragment = ToonEx.Helpers.toon_map(foo: 1, bar: "hello")
      ToonEx.encode!(%{"data" => fragment})
      #=> "data:\\n  bar: hello\\n  foo: 1"

      # Compile-time encoded map with variable values
      x = 42
      fragment = ToonEx.Helpers.toon_map(count: x, name: "test")
      ToonEx.encode!(fragment)
      #=> "count: 42\\nname: test"

  """

  alias ToonEx.Encode.Primitives
  alias ToonEx.Fragment

  @doc """
  Encodes a TOON map from a compile-time keyword list.

  Keys are validated and encoded at compile time. Values are encoded at runtime.
  The result is a `%ToonEx.Fragment{}` that can be embedded in any TOON encoding.

  Only allows keys that are safe unquoted TOON keys (matching `^[A-Za-z_][A-Za-z0-9_.]*$`).

  ## Examples

      fragment = toon_map(name: "Alice", age: 30)
      ToonEx.encode!(fragment)
      "age: 30\\nname: Alice"

  """
  defmacro toon_map(kv) do
    kv = Macro.expand(kv, __CALLER__)

    # Validate keys and build {key_str, value_ast} pairs
    pairs =
      Enum.map(kv, fn {key, value} ->
        key_str = Atom.to_string(key)
        validate_safe_key!(key_str, __CALLER__)
        {key_str, value}
      end)

    # Sort by key string for deterministic output
    sorted_pairs = Enum.sort_by(pairs, fn {key_str, _value} -> key_str end)

    # Build unique variables for each sorted position
    sorted_vars =
      sorted_pairs
      |> Enum.with_index()
      |> Enum.map(fn {_pair, idx} ->
        Macro.var(:"__toon_val_#{idx}__", __MODULE__)
      end)

    # Build iodata expression using sorted vars in order
    iodata_expr = build_kv_iodata(sorted_pairs, sorted_vars)

    # Value expressions in sorted order (for destructuring)
    sorted_values = Enum.map(sorted_pairs, fn {_key_str, value} -> value end)

    quote do
      {unquote_splicing(sorted_vars)} = {unquote_splicing(sorted_values)}

      %Fragment{
        encode: fn _opts -> unquote(iodata_expr) end
      }
    end
  end

  @doc """
  Encodes a TOON map from a variable containing a map and a compile-time
  list of keys.

  It is equivalent to calling `Map.take/2` before encoding. Keys are
  encoded at compile time.

  ## Examples

      map = %{a: 1, b: 2, c: 3}
      fragment = toon_map_take(map, [:c, :b])
      ToonEx.encode!(fragment)
      "b: 2\\nc: 3"

  """
  defmacro toon_map_take(map, take) do
    take = Macro.expand(take, __CALLER__)

    # Build {atom_key, string_key} pairs, validated at compile time
    key_pairs =
      Enum.map(take, fn key ->
        key_str = Atom.to_string(key)
        validate_safe_key!(key_str, __CALLER__)
        {key, key_str}
      end)

    # Sort by string key for deterministic output
    sorted_key_pairs = Enum.sort_by(key_pairs, fn {_atom, str} -> str end)

    sorted_atom_keys = Enum.map(sorted_key_pairs, fn {atom, _str} -> atom end)
    sorted_string_keys = Enum.map(sorted_key_pairs, fn {_atom, str} -> str end)

    # Build unique variables for each sorted position
    sorted_vars =
      sorted_key_pairs
      |> Enum.with_index()
      |> Enum.map(fn {_pair, idx} ->
        Macro.var(:"__toon_val_#{idx}__", __MODULE__)
      end)

    # Build iodata expression using sorted string keys and vars
    iodata_expr = build_kv_iodata_from_keys(sorted_string_keys, sorted_vars)

    value_exprs =
      Enum.map(sorted_atom_keys, fn atom_key ->
        quote do: Map.get(taken, unquote(atom_key))
      end)

    quote do
      map = unquote(map)

      # Use atom keys for Map.take (works with atom-keyed maps)
      taken = Map.take(map, unquote(sorted_atom_keys))

      case map_size(taken) do
        0 ->
          %Fragment{encode: fn _opts -> [] end}

        _ ->
          # Extract values in sorted key order using atom keys
          {:{}, unquote_splicing(sorted_vars)} =
            {:{}, unquote_splicing(value_exprs)}

          %Fragment{encode: fn _opts -> unquote(iodata_expr) end}
      end
    end
  end

  # Build iodata expression from {key_str, value_ast, var} triples
  defp build_kv_iodata(sorted_pairs, sorted_vars) do
    kv_lines =
      Enum.zip(sorted_pairs, sorted_vars)
      |> Enum.map(fn {{key_str, _value}, var} ->
        quote do
          [unquote(key_str), ":", " ", Primitives.encode(unquote(var), ",")]
        end
      end)

    case kv_lines do
      [] ->
        quote(do: [])

      [single] ->
        single

      multiple ->
        Enum.intersperse(multiple, quote(do: "\n"))
        |> then(fn list -> quote(do: [unquote_splicing(list)]) end)
    end
  end

  # Build iodata expression from separate key list and var list
  defp build_kv_iodata_from_keys(sorted_string_keys, sorted_vars) do
    kv_lines =
      Enum.zip(sorted_string_keys, sorted_vars)
      |> Enum.map(fn {key_str, var} ->
        quote do
          [unquote(key_str), ":", " ", Primitives.encode(unquote(var), ",")]
        end
      end)

    case kv_lines do
      [] ->
        quote(do: [])

      [single] ->
        single

      multiple ->
        Enum.intersperse(multiple, quote(do: "\n"))
        |> then(fn list -> quote(do: [unquote_splicing(list)]) end)
    end
  end

  defp validate_safe_key!(key_str, env) do
    unless Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_.]*$/, key_str) do
      raise CompileError,
        description: "invalid TOON key for compile-time encoding: #{inspect(key_str)}",
        file: env.file,
        line: env.line
    end

    :ok
  end
end
