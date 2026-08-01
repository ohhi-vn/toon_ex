defmodule ToonEx.Encode.Arrays do
  @moduledoc """
  Encoding of TOON arrays in three formats:
  - Inline: for primitive arrays (e.g., tags[2]: reading,gaming)
  - Tabular: for uniform object arrays (e.g., users[2]{name,age}: Alice,30 / Bob,25)
  - List: for mixed or non-uniform arrays
  """

  alias ToonEx.Encode.{Objects, Primitives, Strings}
  alias ToonEx.Utils

  # Performance: Module attributes are compile-time constants with zero runtime overhead.
  # Replaces Constants.*() function calls in hot encoding paths.
  @colon ":"

  @open_bracket "["
  @close_bracket "]"
  @open_brace "{"
  @close_brace "}"
  @list_item_marker "-"
  @list_item_prefix "- "
  @null_literal "null"

  # Performance: Pre-computed iodata fragments for hot paths.
  # Avoids rebuilding the same list structure on every call.
  @colon_space [":", " "]

  # Performance: Inline hot functions to reduce function call overhead
  @compile {:inline,
            format_length_marker: 2,
            apply_marker: 3,
            build_primitive_line: 3,
            encode_empty_array_item: 1,
            encode_primitive_item: 2,
            format_delimiter_marker: 1,
            get_ordered_map_keys: 2,
            encode_list_item: 3,
            encode_map_entry_with_marker: 5,
            encode_value_with_optional_marker: 5,
            build_empty_array_line: 2,
            build_inline_array_line: 3,
            encode_complex_array_item: 2,
            encode_inline_array_item: 2,
            do_intersperse_map: 4,
            do_prepend_reversed: 2,
            do_prepend_indented: 3,
            do_encode_complex_nested: 3,
            do_encode_list_items: 4}

  @doc """
  Encodes an array with the given key.

  Automatically detects the appropriate format based on array contents.
  """
  @spec encode(String.t(), list(), non_neg_integer(), map()) :: [iodata()]
  def encode(key, list, depth, opts) when is_list(list) do
    if list == [] do
      encode_empty(key, opts.length_marker)
    else
      case Utils.detect_tabular_fields(list) do
        {:ok, fields} ->
          encode_tabular_with_fields(key, list, fields, depth, opts)

        :error ->
          case Utils.detect_array_type(list) do
            {:primitive, _length} ->
              encode_inline(key, list, opts)

            _ ->
              encode_list(key, list, depth, opts)
          end
      end
    end
  end

  # Encode tabular array with pre-computed field tree from single-pass detection.
  # Supports nested field groups (§9.3): a column of nested-uniform objects is
  # rendered as `field{sub1,sub2}` and its leaf values are flattened in
  # depth-first order into each row.
  defp encode_tabular_with_fields(key, list, fields, _depth, opts) do
    length_marker = format_length_marker(length(list), opts.length_marker)
    encoded_key = Strings.encode_key(key)

    final_fields = apply_key_order(fields, Map.get(opts, :key_order))
    fields_iodata = encode_field_tree(final_fields, opts)
    delimiter_marker = format_delimiter_marker(opts.delimiter)

    header = [
      encoded_key,
      @open_bracket,
      length_marker,
      delimiter_marker,
      @close_bracket,
      @open_brace,
      fields_iodata,
      @close_brace,
      @colon
    ]

    paths = Utils.leaf_paths(final_fields)

    rows =
      Enum.map(list, fn obj ->
        do_intersperse_map(
          paths,
          fn path -> Primitives.encode(Utils.value_at_path(obj, path), opts.delimiter) end,
          opts.delimiter,
          []
        )
      end)

    [header | rows]
  end

  @doc """
  Encodes an object in keyed tabular form (§9.5).

  Requires the caller to already have confirmed `Utils.detect_keyed_tabular/1`
  succeeds on `map`. Returns `[header | entry_rows]` without base indentation;
  the caller pushes the header at its depth and each entry row one level deeper.

  When `key` is `nil`, emits a keyless keyed header (`[N:]{...}:`), valid only
  at the root (§5).
  """
  @spec encode_keyed(String.t() | nil, map(), map()) :: [iodata()]
  def encode_keyed(nil, map, opts) do
    {:ok, fields} = Utils.detect_keyed_tabular(map)
    build_keyed_header(nil, map, fields, opts)
  end

  def encode_keyed(key, map, opts) when is_binary(key) do
    {:ok, fields} = Utils.detect_keyed_tabular(map)
    build_keyed_header(Strings.encode_key(key), map, fields, opts)
  end

  # Same as encode_keyed/3 but with a pre-encoded key iodata (list-item paths).
  def encode_keyed_encoded(encoded_key, map, opts) do
    {:ok, fields} = Utils.detect_keyed_tabular(map)
    build_keyed_header(encoded_key, map, fields, opts)
  end

  defp build_keyed_header(encoded_key, map, fields, opts) do
    length_marker = format_length_marker(Utils.object_size(map), opts.length_marker)
    delimiter_marker = format_delimiter_marker(opts.delimiter)

    fields_iodata =
      case Map.get(opts, :key_order) do
        key_order when is_list(key_order) and key_order != [] ->
          encode_field_tree(apply_key_order(fields, key_order), opts)

        _ ->
          encode_field_tree(fields, opts)
      end

    header = [
      encoded_key || [],
      @open_bracket,
      length_marker,
      @colon,
      delimiter_marker,
      @close_bracket,
      @open_brace,
      fields_iodata,
      @close_brace,
      @colon
    ]

    paths = Utils.leaf_paths(fields)

    rows =
      Enum.map(Utils.object_to_list(map), fn {entry_key, entry} ->
        cells =
          do_intersperse_map(
            paths,
            fn path -> Primitives.encode(Utils.value_at_path(entry, path), opts.delimiter) end,
            opts.delimiter,
            []
          )

        [Strings.encode_key(entry_key), @colon_space, cells]
      end)

    [header | rows]
  end

  @doc """
  Encodes an empty array in object-field position using the `key: []` form (§9.1).

  ## Examples

      iex> result = ToonEx.Encode.Arrays.encode_empty("items", nil)
      iex> IO.iodata_to_binary(result)
      "items: []"
  """
  @spec encode_empty(String.t(), String.t() | nil) ::
          nonempty_list(nonempty_list(binary() | nonempty_list(binary())))
  def encode_empty(key, _length_marker \\ nil) do
    [[Strings.encode_key(key), @colon_space, @open_bracket, @close_bracket]]
  end

  @doc """
  Encodes a primitive array in inline format.

  ## Examples

      iex> opts = %{delimiter: ",", length_marker: nil}
      iex> result = ToonEx.Encode.Arrays.encode_inline("tags", ["reading", "gaming"], opts)
      iex> IO.iodata_to_binary(result)
      "tags[2]: reading,gaming"
  """
  @spec encode_inline(String.t(), list(), map()) :: [iodata()]
  def encode_inline(key, list, opts) do
    length_marker = format_length_marker(length(list), opts.length_marker)
    encoded_key = Strings.encode_key(key)

    values = do_intersperse_map(list, &Primitives.encode(&1, opts.delimiter), opts.delimiter, [])

    # Include delimiter marker in header per TOON spec Section 6
    delimiter_marker = format_delimiter_marker(opts.delimiter)

    header = [
      encoded_key,
      @open_bracket,
      length_marker,
      delimiter_marker,
      @close_bracket,
      @colon_space
    ]

    [[header, values]]
  end

  @doc """
  Encodes a uniform object array in tabular format.

  Returns a list where the first element is the header, and subsequent elements
  are data rows (without indentation - indentation is added by the Writer).

  ## Examples

      iex> opts = %{delimiter: ",", length_marker: nil, indent_string: "  "}
      iex> users = [%{"name" => "Alice", "age" => 30}, %{"name" => "Bob", "age" => 25}]
      iex> [header | rows] = ToonEx.Encode.Arrays.encode_tabular("users", users, 0, opts)
      iex> IO.iodata_to_binary(header)
      "users[2]{age,name}:"
      iex> Enum.map(rows, &IO.iodata_to_binary/1)
      ["30,Alice", "25,Bob"]
  """
  @spec encode_tabular(String.t(), list(), non_neg_integer(), map()) :: [iodata()]
  def encode_tabular(key, list, _depth, opts) do
    case list do
      [] ->
        encode_empty(key, opts.length_marker)

      _ ->
        case Utils.detect_tabular_fields(list) do
          {:ok, fields} ->
            encode_tabular_with_fields(key, list, fields, 0, opts)

          :error ->
            # Fallback: encode as list form
            encode_list(key, list, 0, opts)
        end
    end
  end

  @doc """
  Encodes an array in list format (for mixed or non-uniform arrays).

  Returns a list where the first element is the header, and subsequent elements
  are list items (without base indentation - indentation is added by the Writer).

  ## Examples

      iex> opts = %{delimiter: ",", length_marker: nil, indent_string: "  "}
      iex> items = [%{"title" => "Book", "price" => 9}, %{"title" => "Movie", "duration" => 120}]
      iex> [header | list_items] = ToonEx.Encode.Arrays.encode_list("items", items, 0, opts)
      iex> IO.iodata_to_binary(header)
      "items[2]:"
      iex> Enum.map(list_items, &IO.iodata_to_binary/1)
      ["- price: 9", "  title: Book", "- duration: 120", "  title: Movie"]
  """
  @spec encode_list(String.t(), list(), non_neg_integer(), map()) :: [iodata()]
  def encode_list(key, list, depth, opts) do
    length_marker = format_length_marker(length(list), opts.length_marker)
    encoded_key = Strings.encode_key(key)
    delimiter_marker = format_delimiter_marker(opts.delimiter)

    header = [encoded_key, @open_bracket, length_marker, delimiter_marker, @close_bracket, @colon]

    # Performance: Tail-recursive accumulation instead of Enum.flat_map
    items = do_encode_list_items(list, depth, opts, [])
    [header | items]
  end

  # Tail-recursive helper for encoding list items
  defp do_encode_list_items([], _depth, _opts, acc), do: :lists.reverse(acc)

  defp do_encode_list_items([item | rest], depth, opts, acc) do
    encoded = encode_list_item(item, depth, opts)
    do_encode_list_items(rest, depth, opts, do_prepend_reversed(encoded, acc))
  end

  # Prepend items from a list in reverse order to accumulator (avoids intermediate list)
  defp do_prepend_reversed([], acc), do: acc
  defp do_prepend_reversed([h | t], acc), do: do_prepend_reversed(t, [h | acc])

  # Private helpers

  # Render a field tree as iodata, interspersing the active delimiter.
  # A group entry becomes `key{sub1,sub2}`.
  defp encode_field_tree(fields, opts) do
    do_intersperse_map(fields, &encode_field_entry(&1, opts), opts.delimiter, [])
  end

  defp encode_field_entry({:leaf, key}, _opts), do: Strings.encode_key(key)

  defp encode_field_entry({:group, key, children}, opts) do
    [Strings.encode_key(key), @open_brace, encode_field_tree(children, opts), @close_brace]
  end

  # Reorder the top-level fields according to key_order when it covers every
  # top-level field; otherwise keep the detected (first-object) order.
  defp apply_key_order(fields, key_order)
       when is_list(key_order) and key_order != [] do
    top_keys =
      Enum.map(fields, fn
        {:leaf, k} -> k
        {:group, k, _} -> k
      end)

    key_set = MapSet.new(top_keys)
    ordered = Enum.filter(key_order, &MapSet.member?(key_set, &1))

    if length(ordered) == length(fields) do
      Enum.map(ordered, fn k -> Enum.find(fields, fn f -> field_key(f) == k end) end)
    else
      fields
    end
  end

  defp apply_key_order(fields, _key_order), do: fields

  defp field_key({:leaf, k}), do: k
  defp field_key({:group, k, _}), do: k

  defp format_length_marker(length, nil), do: Integer.to_string(length)

  # Performance: Return iolist instead of binary concatenation
  # (marker <> Integer.to_string(length)). The iolist
  # [marker, Integer.to_string(length)] avoids allocating a new binary
  # and copying both strings into it. The final IO.iodata_to_binary at
  # the top-level encoder flattens everything in one pass, so nested
  # iolists are free.
  defp format_length_marker(length, marker), do: [marker, Integer.to_string(length)]

  @compile {:inline, format_delimiter_marker: 1}
  defp format_delimiter_marker(","), do: ""
  defp format_delimiter_marker(delimiter), do: delimiter

  # Performance: Single-pass map+intersperse — avoids two intermediate lists
  # from Enum.map + Enum.intersperse. Builds iolist directly.
  @compile {:inline, do_intersperse_map: 4}
  defp do_intersperse_map([], _fun, _sep, acc), do: :lists.reverse(acc)
  defp do_intersperse_map([last], fun, _sep, acc), do: :lists.reverse([fun.(last) | acc])

  defp do_intersperse_map([h | t], fun, sep, acc),
    do: do_intersperse_map(t, fun, sep, [sep, fun.(h) | acc])

  # Pattern match on empty map first
  defp encode_list_item(item, _depth, _opts) when item == %{} do
    # Empty object encodes as bare hyphen
    [[@list_item_marker]]
  end

  # Map items in list
  defp encode_list_item(item, depth, opts) when is_map(item) do
    keys = get_ordered_map_keys(item, Map.get(opts, :key_order))

    keys
    |> Enum.with_index()
    |> Enum.flat_map(fn {k, index} ->
      v = Utils.object_get(item, k)
      encode_map_entry_with_marker(k, v, index, depth, opts)
    end)
  end

  # Array items in list - delegate to specific handlers
  defp encode_list_item(item, _depth, opts) when is_list(item) and item == [] do
    encode_empty_array_item(opts)
  end

  defp encode_list_item(item, _depth, opts) when is_list(item) do
    if Utils.all_primitives?(item) do
      encode_inline_array_item(item, opts)
    else
      encode_complex_array_item(item, opts)
    end
  end

  # Primitive items in list
  defp encode_list_item(item, _depth, opts) do
    encode_primitive_item(item, opts)
  end

  # Extract helpers for array item types
  defp encode_empty_array_item(opts) do
    length_marker = format_length_marker(0, opts.length_marker)
    [[@list_item_prefix, @open_bracket, length_marker, @close_bracket, @colon]]
  end

  defp encode_inline_array_item(item, opts) do
    length_marker = format_length_marker(length(item), opts.length_marker)
    delimiter_marker = format_delimiter_marker(opts.delimiter)

    values = do_intersperse_map(item, &Primitives.encode(&1, opts.delimiter), opts.delimiter, [])

    [
      [
        @list_item_prefix,
        @open_bracket,
        length_marker,
        delimiter_marker,
        @close_bracket,
        @colon_space,
        values
      ]
    ]
  end

  defp encode_complex_array_item(item, opts) do
    length_marker = format_length_marker(length(item), opts.length_marker)
    delimiter_marker = format_delimiter_marker(opts.delimiter)

    header = [
      @list_item_prefix,
      @open_bracket,
      length_marker,
      delimiter_marker,
      @close_bracket,
      @colon
    ]

    # Performance: Tail-recursive accumulation instead of Enum.flat_map + Enum.map
    nested_items = do_encode_complex_nested(item, opts, [])
    [header | :lists.reverse(nested_items)]
  end

  # Tail-recursive helper for encoding complex nested array items
  defp do_encode_complex_nested([], _opts, acc), do: acc

  defp do_encode_complex_nested([nested_item | rest], opts, acc) do
    nested = encode_list_item(nested_item, 0, opts)
    indented = do_prepend_indented(nested, opts.indent_string, acc)
    do_encode_complex_nested(rest, opts, indented)
  end

  # Prepend items with indent in reverse order to accumulator
  defp do_prepend_indented([], _indent, acc), do: acc

  defp do_prepend_indented([line | rest], indent, acc),
    do: do_prepend_indented(rest, indent, [[indent | line] | acc])

  defp encode_primitive_item(item, opts) do
    [
      [
        @list_item_prefix,
        Primitives.encode(item, opts.delimiter)
      ]
    ]
  end

  # Helper to get ordered keys for map items
  # Performance: Use MapSet for O(1) membership checks instead of O(n) list `in` checks
  # OrderedObject keeps its declared order when no key_order is provided.
  defp get_ordered_map_keys(%ToonEx.OrderedObject{} = item, key_order)
       when is_list(key_order) and key_order != [] do
    apply_order_option(Utils.object_keys(item), key_order)
  end

  defp get_ordered_map_keys(%ToonEx.OrderedObject{} = item, _key_order) do
    Utils.object_keys(item)
  end

  defp get_ordered_map_keys(item, key_order) do
    apply_order_option(Map.keys(item), key_order)
  end

  defp apply_order_option(map_keys, []) do
    Enum.sort(map_keys)
  end

  defp apply_order_option(map_keys, key_order) when is_list(key_order) do
    key_set = MapSet.new(map_keys)
    # Single pass through key_order with O(1) lookups
    ordered = Enum.filter(key_order, &MapSet.member?(key_set, &1))
    # Single pass through map_keys with O(1) lookups
    order_set = MapSet.new(key_order)
    extra = map_keys |> Enum.reject(&MapSet.member?(order_set, &1)) |> Enum.sort()
    ordered ++ extra
  end

  defp apply_order_option(map_keys, _key_order) do
    Enum.sort(map_keys)
  end

  # Helper for encoding map entries with list markers
  defp encode_map_entry_with_marker(k, v, index, depth, opts) do
    encoded_key = Strings.encode_key(k)
    needs_marker = index == 0

    encode_value_with_optional_marker(encoded_key, v, needs_marker, depth, opts)
  end

  # Encode primitive values
  defp encode_value_with_optional_marker(key, v, needs_marker, _depth, opts)
       when is_nil(v) or is_boolean(v) or is_number(v) or is_binary(v) do
    line = build_primitive_line(key, v, opts)
    [apply_marker(line, needs_marker, opts)]
  end

  # Encode empty array
  defp encode_value_with_optional_marker(key, [], needs_marker, _depth, opts) do
    line = build_empty_array_line(key, opts)
    [apply_marker(line, needs_marker, opts)]
  end

  # Encode inline primitive array
  defp encode_value_with_optional_marker(key, v, needs_marker, _depth, opts)
       when is_list(v) do
    if Utils.all_primitives?(v) do
      line = build_inline_array_line(key, v, opts)
      [apply_marker(line, needs_marker, opts)]
    else
      encode_complex_array_value(key, v, needs_marker, opts)
    end
  end

  # Encode map values (keyed tabular on hyphen line if eligible, else nested)
  defp encode_value_with_optional_marker(key, v, needs_marker, depth, opts) when is_map(v) do
    case Utils.detect_keyed_tabular(v) do
      {:ok, _} ->
        [header | rows] = encode_keyed_encoded(key, v, opts)
        header_line = apply_marker(header, needs_marker, opts)
        data_lines = Enum.map(rows, fn row -> [opts.indent_string, opts.indent_string, row] end)
        [header_line | data_lines]

      :error ->
        header_line = [key, @colon]
        nested_result = encode_nested_map(v, depth, opts)

        if needs_marker do
          [[@list_item_prefix, header_line] | nested_result]
        else
          [[opts.indent_string, header_line] | nested_result]
        end
    end
  end

  # Fallback for unsupported types
  defp encode_value_with_optional_marker(key, _v, needs_marker, _depth, opts) do
    line = [key, @colon_space, @null_literal]
    [apply_marker(line, needs_marker, opts)]
  end

  # Helpers for building lines
  defp build_primitive_line(key, value, opts) do
    [key, @colon_space, Primitives.encode(value, opts.delimiter)]
  end

  defp build_empty_array_line(key, _opts) do
    [Strings.encode_key(key), @colon_space, @open_bracket, @close_bracket]
  end

  defp build_inline_array_line(key, values, opts) do
    length_marker = format_length_marker(length(values), opts.length_marker)
    delimiter_marker = format_delimiter_marker(opts.delimiter)

    encoded_values =
      do_intersperse_map(values, &Primitives.encode(&1, opts.delimiter), opts.delimiter, [])

    [
      Strings.encode_key(key),
      @open_bracket,
      length_marker,
      delimiter_marker,
      @close_bracket,
      @colon_space,
      encoded_values
    ]
  end

  # Apply list marker or indent based on needs_marker flag
  defp apply_marker(line, true, _opts) do
    [@list_item_prefix | line]
  end

  defp apply_marker(line, false, opts) do
    [opts.indent_string | line]
  end

  # Handle complex arrays (tabular, list, or nested)
  # Performance: Use single-pass detection instead of re-traversing
  # with tabular_array?/list_array?
  defp encode_complex_array_value(key, v, needs_marker, opts) do
    depth = 0

    case Utils.detect_tabular_fields(v) do
      {:ok, fields} ->
        encode_tabular_array_value_with_fields(key, v, fields, needs_marker, depth, opts)

      :error ->
        case Utils.detect_array_type(v) do
          {:list, _length} ->
            encode_list_array_value(key, v, needs_marker, depth, opts)

          _ ->
            # Shouldn't happen for complex arrays, but handle gracefully
            encode_other_array_value(key, v, needs_marker, depth, opts)
        end
    end
  end

  # Encode tabular array value with pre-computed field tree (avoids re-detection)
  defp encode_tabular_array_value_with_fields(key, v, fields, needs_marker, _depth, opts) do
    length_marker = format_length_marker(length(v), opts.length_marker)
    encoded_key = Strings.encode_key(key)
    delimiter_marker = format_delimiter_marker(opts.delimiter)

    fields_iodata = encode_field_tree(fields, opts)

    header = [
      encoded_key,
      @open_bracket,
      length_marker,
      delimiter_marker,
      @close_bracket,
      @open_brace,
      fields_iodata,
      @close_brace,
      @colon
    ]

    paths = Utils.leaf_paths(fields)

    rows =
      Enum.map(v, fn obj ->
        do_intersperse_map(
          paths,
          fn path -> Primitives.encode(Utils.value_at_path(obj, path), opts.delimiter) end,
          opts.delimiter,
          []
        )
      end)

    header_line = apply_marker(header, needs_marker, opts)
    data_lines = Enum.map(rows, fn row -> [opts.indent_string, opts.indent_string, row] end)
    [header_line | data_lines]
  end

  defp encode_list_array_value(key, v, needs_marker, depth, opts) do
    [header | list_items] = encode(key, v, depth + 1, opts)
    header_line = apply_marker(header, needs_marker, opts)

    item_lines =
      Enum.map(list_items, fn line -> [opts.indent_string, opts.indent_string, line] end)

    [header_line | item_lines]
  end

  defp encode_other_array_value(key, v, needs_marker, depth, opts) do
    nested = encode(key, v, depth + 1, opts)

    if needs_marker do
      [first_line | rest] = nested

      [
        [@list_item_prefix, first_line]
        | Enum.map(rest, fn line -> [opts.indent_string, line] end)
      ]
    else
      Enum.map(nested, fn line -> [opts.indent_string, line] end)
    end
  end

  defp encode_nested_map(v, depth, opts) do
    Objects.encode_to_lines(v, depth + 1, opts)
    |> Enum.map(&[opts.indent_string, &1])
  end
end
