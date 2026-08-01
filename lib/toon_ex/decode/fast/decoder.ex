defmodule ToonEx.Decode.Fast.Decoder do
  @moduledoc """
  High-performance TOON decoder using pure binary pattern matching.

  ## Performance Design

  1. **No NimbleParsec** – direct binary pattern matching replaces parser combinator overhead
  2. **No regex in hot paths** – binary pattern matching replaces all regex in the decode loop
  3. **Line-by-line processing** – tail-recursive accumulators with `:lists.reverse/1`
  4. **Zero-copy slicing** – `binary_part/3` creates O(1) sub-binary references
  5. **Erlang BIFs** – `:binary.split/3`, `:binary.match/2`, `:maps.from_list/1`
  6. **Compile-time inlining** – `@compile {:inline, [...]}` for all hot functions
  7. **Minimal allocations** – tuple line info `{content, indent, is_blank}` instead of maps
  8. **Fast-path splitting** – `:binary.split/3` when no quotes present; quote-aware fallback
  9. **Skip metadata** – no MapSet/key_order tracking when `expand_paths` is off (default)
  """

  alias ToonEx.DecodeError

  # Delimiter constants – module attributes compile to literals
  @comma ","
  @tab "\t"
  @pipe "|"

  # Inline all hot-path functions to eliminate call overhead
  @compile {:inline,
            [
              parse_value: 1,
              do_parse_value: 1,
              parse_number_or_string: 1,
              try_parse_int: 1,
              unquote_key: 1,
              unquote_string: 1,
              unescape_string: 1,
              trim_leading: 1,
              trim_trailing: 1,
              count_leading_spaces: 2,
              find_colon_space: 1,
              contains_byte: 2,
              ends_with_colon: 1,
              build_map: 2,
              build_map_from_fields: 3,
              normalize_number: 2,
              has_decimal_or_exponent: 1,
              detect_delimiter: 2,
              peek_indent: 1,
              first_content_indent: 1,
              remove_list_marker: 1,
              strip_trailing_colon: 1,
              is_whitespace_only: 1,
              has_bracket_colon_space: 1,
              is_tabular_header: 1,
              is_list_header: 1,
              is_list_array_header: 1,
              strip_dash_prefix: 1,
              do_strip_trailing_quote: 1,
              escape_char: 1,
              flush_unescape_chunk: 4,
              finalize_unescape: 4,
              has_array_marker: 1,
              is_row_line: 2,
              find_unquoted_byte: 2,
              find_uqb: 4,
              take_digits: 3,
              validate_count: 4,
              do_has_tab_no_comma: 1
            ]}

  # ── Public API ──────────────────────────────────────────────────────────────

  @spec decode(binary, keyword) :: {:ok, term} | {:error, DecodeError.t()}
  def decode(input, opts \\ []) when is_binary(input) do
    validated = validate_opts(opts)

    try do
      {:ok, do_decode(input, validated)}
    rescue
      e in DecodeError ->
        {:error, e}

      e ->
        {:error,
         DecodeError.exception(message: "Decode failed: #{Exception.message(e)}", input: input)}
    end
  end

  @spec decode!(binary, keyword) :: term
  def decode!(input, opts \\ []) when is_binary(input) do
    case decode(input, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  # ── Option Handling ─────────────────────────────────────────────────────────

  defp validate_opts(opts) do
    %{
      keys: Keyword.get(opts, :keys, :strings),
      strict: Keyword.get(opts, :strict, true),
      indent_size: Keyword.get(opts, :indent_size, 2),
      expand_paths: Keyword.get(opts, :expand_paths, :off)
    }
  end

  # ── Main Decode Logic ───────────────────────────────────────────────────────

  defp do_decode(input, opts) do
    lines = preprocess(input)

    if opts.strict do
      validate_no_tab_indent(input)
      validate_indentation(lines, opts)
    end

    {result, quoted_keys} =
      case lines do
        [] -> {%{}, []}
        _ -> parse_root(lines, opts)
      end

    if opts.expand_paths == :safe do
      # Pass {key_order, quoted_keys_set} so expand_paths can process keys
      # in document order for correct LWW resolution.
      quoted_keys_set =
        quoted_keys
        |> Enum.filter(fn {_, was_quoted} -> was_quoted end)
        |> Enum.map(fn {key, _} -> key end)
        |> MapSet.new()

      key_order = Enum.map(quoted_keys, fn {key, _} -> key end)
      expand_paths(result, {key_order, quoted_keys_set}, opts.strict)
    else
      result
    end
  end

  # ── Preprocessing ───────────────────────────────────────────────────────────

  # Split input into lines, compute indent, detect blanks, strip comments.
  # Returns list of {content, indent, is_blank} tuples (3-tuple, not map).
  # Uses :binary.split/3 (BIF) for line splitting – faster than String.split/2.
  defp preprocess(input) do
    input
    |> strip_bom()
    |> :binary.split("\n", [:global])
    |> Enum.map(&strip_trailing_cr/1)
    |> do_preprocess([])
    |> drop_trailing_blank()
  end

  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(input), do: input

  defp strip_trailing_cr(<<>>), do: <<>>

  defp strip_trailing_cr(line) do
    size = byte_size(line)

    if size > 0 and :binary.last(line) == ?\r do
      binary_part(line, 0, size - 1)
    else
      line
    end
  end

  defp do_preprocess([], acc), do: :lists.reverse(acc)

  defp do_preprocess([line | rest], acc) do
    {trimmed, indent} = count_leading_spaces(line, 0)

    cond do
      # Comment line — skip entirely (first non-whitespace char is #)
      is_comment_line(trimmed) ->
        do_preprocess(rest, acc)

      true ->
        is_blank = trimmed == <<>> or is_whitespace_only(trimmed)
        do_preprocess(rest, [{trimmed, indent, is_blank} | acc])
    end
  end

  defp drop_trailing_blank(lines) do
    lines
    |> Enum.reverse()
    |> Enum.drop_while(fn {_, _, is_blank} -> is_blank end)
    |> Enum.reverse()
  end

  # ── Blank validation ────────────────────────────────────────────────────────

  # ── Indentation Validation ──────────────────────────────────────────────────

  defp validate_indentation(lines, opts) do
    indent_size = opts.indent_size

    :lists.foreach(
      fn {_, indent, is_blank} ->
        unless is_blank do
          if indent > 0 and rem(indent, indent_size) != 0 do
            raise DecodeError,
              message: "Indentation must be a multiple of #{indent_size} spaces (strict mode)"
          end
        end
      end,
      lines
    )
  end

  # Check for tab characters in indentation (strict mode per spec §12)
  # Scans the original input once — only called when strict mode is enabled.
  # Use Enum.each instead of :lists.foreach because private function captures
  # (&has_tab_in_leading_whitespace?/1) cannot be invoked by Erlang BIFs.
  defp validate_no_tab_indent(input) do
    input
    |> :binary.split("\n", [:global])
    |> Enum.each(fn line ->
      if has_tab_in_leading_whitespace?(line) do
        raise DecodeError,
          message: "Tab characters are not allowed in indentation (strict mode)"
      end
    end)
  end

  # Binary scan for tab in leading whitespace — O(1) for the common case (no tab)
  @compile {:inline, has_tab_in_leading_whitespace?: 1}
  defp has_tab_in_leading_whitespace?(<<?\t, _::binary>>), do: true

  defp has_tab_in_leading_whitespace?(<<?\s, rest::binary>>),
    do: has_tab_in_leading_whitespace?(rest)

  defp has_tab_in_leading_whitespace?(_), do: false

  # ── Root Form Detection ─────────────────────────────────────────────────────

  defp parse_root([{content, _, _} | _] = lines, opts) do
    cond do
      # Root array: starts with [
      binary_part(content, 0, 1) == "[" ->
        {parse_root_array(lines, opts), []}

      # Single non-blank line → check if it's a primitive (not a key-value line)
      # Per TOON spec §5: a single line that is neither a valid array header nor
      # a key-value line decodes to a single primitive.
      # Quoted strings like "a:b" are primitives even with colons inside.
      length(lines) == 1 and is_root_primitive?(content) ->
        {parse_value(content), []}

      # Object (default)
      true ->
        parse_object(lines, 0, opts, [], [], false)
    end
  end

  # Check if a single-line content is a root primitive (not a key-value line).
  # A quoted string that starts AND ends with " is a complete primitive value,
  # even if it contains colons (e.g., "a:b", "http://example.com").
  # A quoted key followed by ": " or ":" (e.g., "key": value) does NOT end
  # with a quote, so it correctly falls through to object parsing.
  defp is_root_primitive?(<<"\"", _::binary>> = content) do
    :binary.last(content) == ?"
  end

  defp is_root_primitive?(content) do
    not contains_byte(content, ?:)
  end

  # ── Root Array Parsing ─────────────────────────────────────────────────────

  defp parse_root_array([{content, _, _} | rest] = lines, opts) do
    cond do
      # Bare empty array: []
      content == "[]" ->
        check_trailing(rest, content, opts)
        []

      # Root keyed tabular: [N:<delim?>]{fields}:
      is_keyed_header(content) ->
        {count, delimiter, fields} = parse_root_keyed_header(content)
        child_indent = opts.indent_size
        {entry_rows, remaining} = take_entry_rows(rest, 0, child_indent, opts)
        validate_count(length(entry_rows), count, content, opts)
        check_trailing(remaining, content, opts)
        parse_entry_into_object(entry_rows, fields, delimiter, opts)

      # Root tabular: [N]{fields}: (no closing bracket after digits)
      is_tabular_header(content) ->
        {count, delimiter, fields} = parse_root_tabular_header(content)
        leaf_fc = leaf_count(fields)
        {rows, remaining} = take_tabular_rows(rest, 0, delimiter, leaf_fc, opts)
        validate_count(length(rows), count, content, opts)
        check_trailing(remaining, content, opts)
        parse_tabular_rows(rows, fields, leaf_fc, delimiter, opts, [])

      # Root list: [N]:
      is_list_header(content) ->
        {count, delimiter} = parse_root_list_header(content)
        {items, remaining} = parse_list_array_items(rest, 0, delimiter, opts)
        validate_count(length(items), count, content, opts)
        check_trailing(remaining, content, opts)
        items

      # Root inline: [N]: v1,v2
      has_bracket_colon_space(content) ->
        {count, delimiter, values_str} = parse_root_inline_header(content)
        values = split_and_parse(values_str, delimiter)
        validate_count(length(values), count, content, opts)
        check_trailing(rest, content, opts)
        values

      true ->
        {result, _quoted_keys} = parse_object(lines, 0, opts, [], [], false)
        result
    end
  end

  # Check for trailing content after a root array (strict mode per spec §5)
  defp check_trailing([], _content, _opts), do: :ok

  defp check_trailing(_lines, content, opts) do
    if opts.strict do
      raise DecodeError,
        message: "Trailing content after root array",
        input: content
    end
  end

  # ── Object Parsing ──────────────────────────────────────────────────────────

  # Main loop: process lines at `depth`, accumulate {key, value} pairs.
  # Returns the built map when lines are exhausted or depth decreases.
  # quoted_keys is a list of {key, was_quoted} tuples in reverse document order.
  # This preserves both key ordering (for LWW in path expansion) and quoted status.
  defp parse_object([], _depth, opts, acc, quoted_keys, _in_list_item),
    do: {build_map(:lists.reverse(acc), opts), quoted_keys}

  defp parse_object([{_, _, true} | rest], depth, opts, acc, quoted_keys, in_list_item) do
    parse_object(rest, depth, opts, acc, quoted_keys, in_list_item)
  end

  defp parse_object([{_, indent, _} | _], depth, opts, acc, quoted_keys, _in_list_item) when indent < depth do
    {build_map(:lists.reverse(acc), opts), quoted_keys}
  end

  defp parse_object([{_, indent, _} | _], depth, opts, acc, quoted_keys, _in_list_item) when indent > depth do
    # In strict mode, validate that over-indented lines only appear after a scope-opening line
    # (object header, array header, etc.)
    if opts.strict do
      raise DecodeError,
        message: "Over-indented line: expected indent #{depth} or less, got #{indent} (previous line did not open a scope)",
        input: "line at indent #{indent}"
    end
    {build_map(:lists.reverse(acc), opts), quoted_keys}
  end

  defp parse_object([{content, _indent, false} | rest], depth, opts, acc, quoted_keys, in_list_item) do
    case parse_entry(content, rest, depth, opts, in_list_item) do
      {:kv, key, value, remaining, was_quoted} ->
        qk = [{key, was_quoted} | quoted_keys]
        parse_object(remaining, depth, opts, [{key, value} | acc], qk, in_list_item)

      {:nested, key, remaining, was_quoted} ->
        qk = [{key, was_quoted} | quoted_keys]
        {nested_value, remaining2, nested_qk} = parse_nested_object(remaining, depth, opts, in_list_item)
        parse_object(remaining2, depth, opts, [{key, nested_value} | acc], nested_qk ++ qk, in_list_item)

      {:keyed, key, count, delimiter, fields, remaining, was_quoted} ->
        qk = [{key, was_quoted} | quoted_keys]
        child_indent = depth + opts.indent_size
        {entry_rows, remaining2} = take_entry_rows(remaining, depth, child_indent, opts)
        entry_obj = parse_entry_into_object(entry_rows, fields, delimiter, opts)

        if opts.strict and map_size(entry_obj) != count do
          raise DecodeError,
            message:
              "Keyed tabular entry count mismatch: declared #{count}, got #{map_size(entry_obj)}",
            input: content
        end

        parse_object(remaining2, depth, opts, [{key, entry_obj} | acc], qk, in_list_item)

      {:tabular, key, count, delimiter, fields, remaining, was_quoted} ->
        qk = [{key, was_quoted} | quoted_keys]

        {array_value, remaining2} =
          parse_tabular_array(remaining, depth, count, delimiter, fields, opts)

        parse_object(remaining2, depth, opts, [{key, array_value} | acc], qk, in_list_item)

      {:list, key, count, delimiter, remaining, was_quoted} ->
        qk = [{key, was_quoted} | quoted_keys]
        {array_value, remaining2} = parse_list_array(remaining, depth, count, delimiter, opts)
        parse_object(remaining2, depth, opts, [{key, array_value} | acc], qk, in_list_item)
    end
  end

  # Build map from entry list – use BIF :maps.from_list/1 for speed
  defp build_map(entries, opts) do
    if opts.strict do
      check_duplicate_keys(entries)
    end

    case opts.keys do
      :strings -> :maps.from_list(entries)
      :atoms -> Map.new(entries, fn {k, v} -> {String.to_atom(k), v} end)
      :atoms! -> Map.new(entries, fn {k, v} -> {String.to_existing_atom(k), v} end)
    end
  end

  # Check for duplicate keys in strict mode
  defp check_duplicate_keys(entries) do
    seen = MapSet.new()
    check_duplicates(entries, seen)
  end

  defp check_duplicates([], _seen), do: :ok

  defp check_duplicates([{key, _value} | rest], seen) do
    if MapSet.member?(seen, key) do
      raise DecodeError,
        message: "Duplicate field name in strict mode: #{inspect(key)}"
    end

    check_duplicates(rest, MapSet.put(seen, key))
  end

  # Build map from parallel field/value lists without intermediate zip.
  # Handles flat fields (strings) and nested field groups ({:group, name, subfields}).
  defp build_map_from_fields(fields, values, opts) do
    if Enum.any?(fields, &match?({:group, _, _}, &1)) do
      {map, _rest} = do_build_nested(fields, values, opts)
      map
    else
      case opts.keys do
        :strings ->
          :maps.from_list(:lists.zip(fields, values))

        :atoms ->
          :maps.from_list(:lists.zipwith(fn k, v -> {String.to_atom(k), v} end, fields, values))

        :atoms! ->
          :maps.from_list(
            :lists.zipwith(fn k, v -> {String.to_existing_atom(k), v} end, fields, values)
          )
      end
    end
  end

  # ── Entry Line Parsing (Hot Path) ───────────────────────────────────────────

  # Classify and parse a single entry line at the current depth.
  # This function is called for every non-blank line in an object.
  # The `in_list_item` flag allows double indentation for nested objects inside list items.
  defp parse_entry(content, rest, depth, opts, in_list_item) do
    case find_colon_space(content) do
      {:found, pos} ->
        key_part = binary_part(content, 0, pos)
        value_part = binary_part(content, pos + 2, byte_size(content) - pos - 2)

        if has_array_marker(key_part) and valid_array_key_part?(key_part) do
          parse_inline_array_entry(key_part, value_part, rest, depth, opts)
        else
          if opts.strict and has_array_marker(key_part) and not valid_array_key_part?(key_part) do
            raise DecodeError,
              message: "Invalid array header syntax in strict mode",
              input: key_part
          end

          key = unquote_key(key_part)
          was_quoted = key_was_quoted(key_part)
          trimmed_value = trim_leading(value_part) |> trim_trailing()

          if trimmed_value == <<>> do
            # key: with empty value – check for nested object
            # Per TOON spec §8: "key:" with nothing after the colon opens an object;
            # an empty value produces an empty object %{}, not an empty string "".
            case peek_indent(rest) do
              ind when ind > depth ->
                # In strict mode, validate depth jump
                # When inside a list item, double indentation is allowed
                expected_ind = depth + opts.indent_size
                if opts.strict and ind != expected_ind and
                     (not in_list_item or ind != depth + 2 * opts.indent_size) do
                  raise DecodeError,
                    message: "Indentation jump: nested content must be indented by exactly #{opts.indent_size} spaces (got #{ind}, expected #{expected_ind})",
                    input: content
                end
                {:nested, key, rest, was_quoted}
              _ -> {:kv, key, %{}, rest, was_quoted}
            end
          else
            value = parse_value(trimmed_value)
            {:kv, key, value, rest, was_quoted}
          end
        end

      :not_found ->
        parse_entry_no_colon_space(content, rest, depth, opts)
    end
  end

  # Check if key_part has a properly formed array marker:
  # - No whitespace before [
  # - At least one digit after [
  # - Skips quoted prefix (e.g., "key[test]"[3] searches after closing quote)
  defp valid_array_key_part?(key_part) do
    search_start =
      case key_part do
        <<"\"", rest::binary>> ->
          case find_closing_quote(rest, 0) do
            {:found, end_pos} -> end_pos + 2
            :not_found -> 0
          end

        _ ->
          0
      end

    scope_len = byte_size(key_part) - search_start

    case :binary.match(key_part, "[", [{:scope, {search_start, scope_len}}]) do
      {pos, 1} when pos > 0 ->
        case binary_part(key_part, pos - 1, 1) do
          <<c>> when c in [?\s, ?\t] ->
            false

          _ ->
            pos + 1 < byte_size(key_part) and
              (binary_part(key_part, pos + 1, 1) |> :binary.first()) in ?0..?9
        end

      _ ->
        false
    end
  end

  # Handle lines without ": " pattern
  defp parse_entry_no_colon_space(content, rest, depth, opts) do
    cond do
      # Keyed tabular header: key[N:]{fields}:
      is_keyed_header(content) ->
        {key, count, delimiter, fields} = parse_keyed_header_content(content)
        validate_fields_strict(fields, content, opts)
        was_quoted = key_was_quoted(content)
        {:keyed, key, count, delimiter, fields, rest, was_quoted}

      # Tabular header: key[N]{fields}:
      is_tabular_header(content) ->
        {key, count, delimiter, fields} = parse_tabular_header_content(content)
        validate_fields_strict(fields, content, opts)
        was_quoted = key_was_quoted(content)
        {:tabular, key, count, delimiter, fields, rest, was_quoted}

      # List header: key[N]:
      is_list_header(content) ->
        {key, count, delimiter} = parse_list_header_content(content)
        was_quoted = key_was_quoted(content)
        {:list, key, count, delimiter, rest, was_quoted}

      # Nested object: key:
      ends_with_colon(content) ->
        key = content |> strip_trailing_colon() |> unquote_key()
        was_quoted = key_was_quoted(content)

        case peek_indent(rest) do
          ind when ind > depth -> {:nested, key, rest, was_quoted}
          _ -> {:kv, key, %{}, rest, was_quoted}
        end

      true ->
        raise DecodeError, message: "Cannot parse line", input: content
    end
  end

  # Parse inline array entry: key[N<delim?>]: v1,v2,...
  defp parse_inline_array_entry(key_part, value_part, rest, depth, opts) do
    {key, count, delimiter, maybe_fields, extra_remaining} =
      parse_array_header_from_parts(key_part)

    # Non-empty extra_remaining means the bracket syntax didn't consume the whole key_part
    # e.g. foo[2]extra: a,b  →  literal key "foo[2]extra" per spec §6 fall-through
    trimmed_extra = trim_leading(extra_remaining) |> trim_trailing()

    if trimmed_extra != <<>> do
      if opts.strict do
        raise DecodeError,
          message: "Invalid array header syntax in strict mode",
          input: key_part
      end

      literal_key = unquote_key(key_part)
      trimmed_value = trim_leading(value_part) |> trim_trailing()
      value = parse_value(trimmed_value)
      {:kv, literal_key, value, rest, false}
    else
      was_quoted = key_was_quoted(key_part)
      trimmed_value = trim_leading(value_part) |> trim_trailing()

      cond do
        # Tabular array with fields: key[N]{fields}: (value_part empty, fields present)
        maybe_fields != [] and trimmed_value == <<>> ->
          {:tabular, key, count, delimiter, maybe_fields, rest, was_quoted}

        # Fields present but value also present → delimiter mismatch fall-through
        maybe_fields != [] ->
          if opts.strict do
            raise DecodeError,
              message: "Fields present with inline values in strict mode",
              input: key_part
          end

          literal_key = unquote_key(key_part)
          value = parse_value(trimmed_value)
          {:kv, literal_key, value, rest, false}

        # List array or empty inline array: key[N]: with no inline values
        trimmed_value == <<>> ->
          # If the next line is a list item (depth > current, starts with `-`),
          # this is a list array. Otherwise, it's an empty inline array.
          next_is_list =
            case rest do
              [{next_content, next_indent, _} | _] ->
                next_indent > depth and starts_with_list_marker(next_content)

              _ ->
                false
            end

          if next_is_list do
            {:list, key, count, delimiter, rest, was_quoted}
          else
            {:kv, key, [], rest, was_quoted}
          end

        # Inline array: key[N]: v1,v2
        true ->
          values = split_and_parse(trimmed_value, delimiter)

          if opts.strict and length(values) != count do
            raise DecodeError,
              message: "Array length mismatch: declared #{count}, got #{length(values)}",
              input: key_part
          end

          {:kv, key, values, rest, was_quoted}
      end
    end
  end

  # ── Nested Object Parsing ───────────────────────────────────────────────────

  defp parse_nested_object(lines, parent_depth, opts, in_list_item) do
    {nested_lines, remaining} = take_nested(lines, parent_depth)

    if nested_lines == [] do
      {%{}, remaining, []}
    else
      child_depth = first_content_indent(nested_lines)

      # In strict mode, validate that nested content is at least one level deeper
      # and is a multiple of indent_size.
      # Note: When inside a list item, double indentation is allowed (for nested
      # objects inside list items where the encoder uses double indentation).
      if opts.strict do
        depth_diff = child_depth - parent_depth
        if depth_diff <= 0 or rem(depth_diff, opts.indent_size) != 0 do
          raise DecodeError,
            message: "Indentation jump: nested content must be indented by a multiple of #{opts.indent_size} spaces (got #{child_depth}, expected #{parent_depth + opts.indent_size})",
            input: Enum.at(nested_lines, 0) |> elem(0)
        end

        # When not inside a list item, require single-level indentation
        if not in_list_item and child_depth != parent_depth + opts.indent_size do
          raise DecodeError,
            message: "Indentation jump: nested content must be indented by exactly #{opts.indent_size} spaces (got #{child_depth}, expected #{parent_depth + opts.indent_size})",
            input: Enum.at(nested_lines, 0) |> elem(0)
        end
      end

      {result, quoted_keys} = parse_object(nested_lines, child_depth, opts, [], [], in_list_item)
      # Return nested quoted_keys as-is (already in correct order within nested scope)
      {result, remaining, quoted_keys}
    end
  end

  # ── Tabular Array Parsing ───────────────────────────────────────────────────

  defp parse_tabular_array(lines, parent_depth, count, delimiter, fields, opts) do
    leaf_fc = leaf_count(fields)
    {rows, remaining} = take_tabular_rows(lines, parent_depth, delimiter, leaf_fc, opts)

    if opts.strict and length(rows) != count do
      raise DecodeError,
        message: "Tabular array row count mismatch: declared #{count}, got #{length(rows)}"
    end

    result = parse_tabular_rows(rows, fields, leaf_fc, delimiter, opts, [])
    {result, remaining}
  end

  # Take lines that are tabular rows (at depth > parent_depth and look like rows)
  defp take_tabular_rows(lines, parent_depth, delimiter, _field_count, opts) do
    do_take_tabular_rows(lines, parent_depth, delimiter, opts, [])
  end

  defp do_take_tabular_rows([], _base, _delim, _opts, acc), do: {:lists.reverse(acc), []}

  defp do_take_tabular_rows([{_, _, true} = _line | rest], base, delim, opts, acc) do
    if opts.strict and acc != [] do
      raise DecodeError, message: "Blank lines are not allowed inside arrays in strict mode"
    else
      do_take_tabular_rows(rest, base, delim, opts, acc)
    end
  end

  defp do_take_tabular_rows([{content, indent, false} = line | rest], base, delim, opts, acc)
       when indent > base do
    if is_row_line(content, delim) do
      do_take_tabular_rows(rest, base, delim, opts, [line | acc])
    else
      {:lists.reverse(acc), [line | rest]}
    end
  end

  defp do_take_tabular_rows(lines, _base, _delim, _opts, acc), do: {:lists.reverse(acc), lines}

  # Parse tabular rows into list of maps
  defp parse_tabular_rows([], _fields, _fc, _delim, _opts, acc), do: :lists.reverse(acc)

  defp parse_tabular_rows([{content, _, false} | rest], fields, fc, delim, opts, acc) do
    values = split_and_parse(content, delim)

    if length(values) != fc do
      raise DecodeError,
        message: "Row value count mismatch: expected #{fc}, got #{length(values)}",
        input: content
    end

    row_map = build_map_from_fields(fields, values, opts)
    parse_tabular_rows(rest, fields, fc, delim, opts, [row_map | acc])
  end

  defp parse_tabular_rows([{_, _, true} | rest], fields, fc, delim, opts, acc) do
    parse_tabular_rows(rest, fields, fc, delim, opts, acc)
  end

  # ── Keyed Tabular Parsing ───────────────────────────────────────────────────

  # Take entry rows for a keyed tabular scope.
  # Entry rows appear at child_indent (depth + indent_size).
  defp take_entry_rows(lines, parent_depth, child_indent, opts) do
    do_take_entry_rows(lines, parent_depth, child_indent, opts, [])
  end

  defp do_take_entry_rows([], _base_depth, _child_indent, _opts, acc),
    do: {:lists.reverse(acc), []}

  defp do_take_entry_rows([{_, _, true} = _line | rest], base_depth, child_indent, opts, acc) do
    # Allow blank lines before first entry (e.g., between header and first row)
    # Per spec §12: blank lines between header and rows are acceptable
    if opts.strict and acc != [] do
      raise DecodeError,
        message:
          "Blank lines are not allowed inside keyed tabular entries in strict mode (spec §14.2)"
    else
      do_take_entry_rows(rest, base_depth, child_indent, opts, acc)
    end
  end

  defp do_take_entry_rows(
         [{content, indent, false} | rest],
         base_depth,
         child_indent,
         opts,
         acc
       )
       when indent >= child_indent do
    do_take_entry_rows(rest, base_depth, child_indent, opts, [{content, indent, false} | acc])
  end

  defp do_take_entry_rows(lines, _base_depth, _child_indent, _opts, acc),
    do: {:lists.reverse(acc), lines}

  # Parse entry rows into a map of {entry_key => row_map}
  defp parse_entry_into_object([], _fields, _delimiter, _opts), do: %{}

  defp parse_entry_into_object(entry_rows, fields, delimiter, opts) do
    leaf_fc = leaf_count(fields)
    parse_entry_rows(entry_rows, fields, leaf_fc, delimiter, opts, %{})
  end

  defp parse_entry_rows([], _fields, _fc, _delim, _opts, acc), do: acc

  defp parse_entry_rows([{content, _, false} | rest], fields, fc, delim, opts, acc) do
    case find_colon_space(content) do
      {:found, pos} ->
        key_part = binary_part(content, 0, pos)
        cell_values_str = binary_part(content, pos + 2, byte_size(content) - pos - 2)
        entry_key = unquote_key(key_part)
        cell_values = split_and_parse_cells(cell_values_str, delim)

        if length(cell_values) != fc do
          raise DecodeError,
            message: "Entry row cell count mismatch: expected #{fc}, got #{length(cell_values)}",
            input: content
        end

        if opts.strict and Map.has_key?(acc, entry_key) do
          raise DecodeError,
            message: "Duplicate entry key in strict mode: #{inspect(entry_key)}",
            input: content
        end

        row_map = build_map_from_fields(fields, cell_values, opts)
        parse_entry_rows(rest, fields, fc, delim, opts, Map.put(acc, entry_key, row_map))

      :not_found ->
        if opts.strict do
          raise DecodeError,
            message: "Entry row must have a colon-space separator",
            input: content
        else
          # Non-strict mode: skip lines without colon-space at entry depth
          parse_entry_rows(rest, fields, fc, delim, opts, acc)
        end
    end
  end

  defp parse_entry_rows([{_, _, true} | rest], fields, fc, delim, opts, acc) do
    parse_entry_rows(rest, fields, fc, delim, opts, acc)
  end

  # Split an entry row at the first unquoted colon-space.
  # Returns {entry_key, cell_values_str}
  # ── List Array Parsing ──────────────────────────────────────────────────────

  defp parse_list_array(lines, parent_depth, count, delimiter, opts) do
    {items, remaining} = parse_list_array_items(lines, parent_depth, delimiter, opts)

    if opts.strict and length(items) != count do
      raise DecodeError,
        message: "Array length mismatch: declared #{count}, got #{length(items)}"
    end

    {items, remaining}
  end

  defp parse_list_array_items(lines, parent_depth, delimiter, opts) do
    {nested_lines, remaining} = take_nested(lines, parent_depth)

    if nested_lines == [] do
      {[], remaining}
    else
      item_indent = first_content_indent(nested_lines)
      items = parse_list_items(nested_lines, item_indent, delimiter, opts, [])
      {items, remaining}
    end
  end

  # ── List Item Parsing ───────────────────────────────────────────────────────

  defp parse_list_items([], _indent, _delim, _opts, acc), do: :lists.reverse(acc)

  defp parse_list_items([{_, _, true} = _line | rest], indent, delim, opts, acc) do
    # Allow blank lines before the first item (between header and first item)
    if opts.strict and acc != [] do
      raise DecodeError, message: "Blank lines are not allowed inside arrays in strict mode"
    else
      parse_list_items(rest, indent, delim, opts, acc)
    end
  end

  defp parse_list_items([{content, line_indent, false} | rest], indent, delim, opts, acc) do
    # In strict mode, lines at item depth must start with the list marker
    if opts.strict and not starts_with_list_marker(content) do
      raise DecodeError,
        message: "Non-list-item line at item depth in strict mode",
        input: content
    end

    trimmed = remove_list_marker(content)

    cond do
      # Empty list item
      trimmed == <<>> or is_whitespace_only(trimmed) ->
        parse_list_items(rest, indent, delim, opts, [%{} | acc])

      # Inline array item: [N]: v1,v2
      # Must start with "[" to distinguish from key-prefixed inline arrays
      # like "tags[2]: a,b" which should be routed through the key-value path
      # (parse_list_item_object → parse_entry → parse_inline_array_entry).
      binary_part(trimmed, 0, 1) == "[" and has_bracket_colon_space(trimmed) ->
        {item, item_rest} = parse_inline_array_from_trimmed(trimmed, rest, opts)
        parse_list_items(item_rest, indent, delim, opts, [item | acc])

      # Keyless keyed header: [N:]{fields}: — only valid at root level
      binary_part(trimmed, 0, 1) == "[" and is_keyed_header(trimmed) ->
        if opts.strict do
          raise DecodeError,
            message: "Keyless keyed header not allowed as list item in strict mode",
            input: content
        end

        {_, _, delimiter, fields} = parse_keyed_header_content(trimmed)
        validate_fields_strict(fields, trimmed, opts)
        child_indent = line_indent + opts.indent_size
        {entry_rows, remaining} = take_entry_rows(rest, line_indent, child_indent, opts)
        entry_obj = parse_entry_into_object(entry_rows, fields, delimiter, opts)
        parse_list_items(remaining, indent, delim, opts, [entry_obj | acc])

      # List array header: [N]:
      is_list_array_header(trimmed) ->
        {item, item_rest} = parse_nested_list_array_item(trimmed, rest, indent, opts)
        parse_list_items(item_rest, indent, delim, opts, [item | acc])

      # Tabular header on hyphen line: key[N]{fields}:
      is_tabular_header(trimmed) ->
        {item, item_rest} =
          parse_list_item_tabular(trimmed, rest, line_indent, indent, opts)

        parse_list_items(item_rest, indent, delim, opts, [item | acc])

      # List header on hyphen line: key[N]:
      is_list_header(trimmed) ->
        {item, item_rest} =
          parse_list_item_list_array(trimmed, rest, line_indent, indent, opts)

        parse_list_items(item_rest, indent, delim, opts, [item | acc])

      # Quoted string primitive — starts with " and is a complete quoted value.
      # Must be checked BEFORE the colon check because quoted strings like
      # "room:lobby" contain colons but are primitives, not key-value lines.
      # However, "key": value patterns (quoted key followed by colon) should
      # fall through to the colon check below.
      binary_part(trimmed, 0, 1) == "\"" and not quoted_key_value?(trimmed) ->
        parse_list_items(rest, indent, delim, opts, [parse_value(trimmed) | acc])

      # Key-value or nested object on hyphen line
      contains_byte(trimmed, ?:) ->
        {item, item_rest} =
          parse_list_item_object(trimmed, rest, line_indent, indent, opts)

        parse_list_items(item_rest, indent, delim, opts, [item | acc])

      # Primitive value
      true ->
        parse_list_items(rest, indent, delim, opts, [parse_value(trimmed) | acc])
    end
  end

  # Parse inline array from trimmed content: [N<delim?>]: v1,v2
  defp parse_inline_array_from_trimmed(trimmed, rest, opts) do
    {count, delimiter, values_str} = parse_root_inline_header(trimmed)

    values =
      if values_str == <<>> do
        []
      else
        split_and_parse(values_str, delimiter)
      end

    if opts.strict and length(values) != count do
      raise DecodeError,
        message: "Array length mismatch: declared #{count}, got #{length(values)}"
    end

    {values, rest}
  end

  # Parse nested list array item: [N]: with nested items
  defp parse_nested_list_array_item(trimmed, rest, indent, opts) do
    {count, delimiter} = parse_root_list_header(trimmed)
    {items, remaining} = parse_list_array_items(rest, indent, delimiter, opts)

    if opts.strict and length(items) != count do
      raise DecodeError,
        message: "Array length mismatch: declared #{count}, got #{length(items)}"
    end

    {items, remaining}
  end

  # Parse list item with tabular array as first field
  # Per spec §10: rows at depth+2, siblings at depth+1
  defp parse_list_item_tabular(trimmed, rest, _line_indent, item_indent, opts) do
    {key, count, delimiter, fields} = parse_tabular_header_content(trimmed)
    validate_fields_strict(fields, trimmed, opts)
    leaf_fc = leaf_count(fields)
    # Per spec §10: tabular rows appear at depth+2 relative to the hyphen line.
    # The hyphen line is at item_indent, so rows are at item_indent + 2*indent_size.
    # Siblings appear at depth+1 = item_indent + indent_size.
    row_depth = item_indent + 2 * opts.indent_size

    # Take tabular rows (at depth+2 relative to hyphen line)
    {rows, after_rows} = take_tabular_rows_at_depth(rest, row_depth, delimiter, leaf_fc, opts)

    if opts.strict and length(rows) != count do
      raise DecodeError,
        message: "Tabular array row count mismatch: declared #{count}, got #{length(rows)}"
    end

    array_value = parse_tabular_rows(rows, fields, leaf_fc, delimiter, opts, [])

    # Take sibling fields at depth+1 relative to the hyphen line.
    # Per spec §10: siblings appear at item_indent + indent_size.
    sibling_depth = item_indent + opts.indent_size
    {siblings, remaining} = take_siblings_at_depth(after_rows, sibling_depth, opts)

    sibling_map =
      if siblings == [] do
        %{}
      else
        sib_depth = first_content_indent(siblings)
        {sib_map, _qk} = parse_object(siblings, sib_depth, opts, [], [], false)
        sib_map
      end

    # Put tabular array as first field, then merge siblings
    result = Map.put(sibling_map, key, array_value)
    {result, remaining}
  end

  # Parse list item with list array header
  defp parse_list_item_list_array(trimmed, rest, _line_indent, item_indent, opts) do
    {key, count, delimiter} = parse_list_header_content(trimmed)

    # Take all nested lines (depth > item_indent)
    {all_nested, after_all} = take_nested(rest, item_indent)

    # Separate sibling fields from list items.
    sibling_depth = item_indent + opts.indent_size

    {sibling_lines, item_lines} =
      separate_sibling_lines(all_nested, sibling_depth)

    # Parse list items
    items =
      if item_lines == [] do
        []
      else
        item_indent_nested = first_content_indent(item_lines)
        parse_list_items(item_lines, item_indent_nested, delimiter, opts, [])
      end

    if opts.strict and length(items) != count do
      raise DecodeError,
        message: "Array length mismatch: declared #{count}, got #{length(items)}"
    end

    # Parse sibling map
    sibling_map =
      if sibling_lines == [] do
        %{}
      else
        sib_depth = first_content_indent(sibling_lines)
        {sib_map, _qk} = parse_object(sibling_lines, sib_depth, opts, [], [], false)
        sib_map
      end

    result = Map.put(sibling_map, key, items)
    {result, after_all}
  end

  # Separate lines at sibling_depth without `-` marker (sibling fields)
  # from lines with `-` marker or at other depths (list items).
  defp separate_sibling_lines(lines, sibling_depth) do
    separate_sibling_lines(lines, sibling_depth, [], [])
  end

  defp separate_sibling_lines(
         [{content, indent, _escaped?} = line | rest],
         sibling_depth,
         sibs,
         items
       ) do
    if indent == sibling_depth and not starts_with_list_marker(content) do
      separate_sibling_lines(rest, sibling_depth, [line | sibs], items)
    else
      separate_sibling_lines(rest, sibling_depth, sibs, [line | items])
    end
  end

  defp separate_sibling_lines([], _sibling_depth, sibs, items) do
    {:lists.reverse(sibs), :lists.reverse(items)}
  end

  # Parse list item as object (key: value on hyphen line)
  # Per spec §10: the first field on a hyphen line sits at depth+1 relative
  # to the hyphen marker. Continuation lines that are deeper are children;
  # continuation lines at the same depth are siblings.
  # We place the hyphen-line content at `item_indent + indent_size` (the
  # sibling depth) so that `parse_object` correctly distinguishes children
  # (deeper indent) from siblings (same indent).
  defp parse_list_item_object(trimmed, rest, _line_indent, item_indent, opts) do
    # Check for blank lines inside list item fields (strict mode)
    # A blank line between the hyphen line and its continuation fields is an error
    if opts.strict do
      check_no_blank_before_nested(rest, item_indent)
    end

    # Take continuation lines at depth > item_indent
    {continuation, rest2} = take_nested(rest, item_indent)

    # Also consume sibling fields at depth == item_indent that don't start
    # with the list marker (they belong to the same object as the hyphen line).
    {siblings, remaining} = take_item_siblings(rest2, item_indent)

    # The hyphen-line content sits at sibling depth:
    # item_indent + indent_size. This is one level above any children
    # and at the same level as any sibling fields.
    sibling_indent = item_indent + opts.indent_size

    # Sibling fields at item_indent are shifted to sibling_indent so they
    # are parsed alongside the hyphen-line content at the same depth.
    shifted_siblings = Enum.map(siblings, fn {c, _indent, b} -> {c, sibling_indent, b} end)

    # Create synthetic line for the hyphen-line content at sibling_indent
    hyphen_line = {trimmed, sibling_indent, false}
    all_lines = [hyphen_line | continuation ++ shifted_siblings]

    {result, _quoted_keys} = parse_object(all_lines, sibling_indent, opts, [], [], true)
    {result, remaining}
  end

  # Take sibling lines at base_depth that do NOT start with a list marker
  # together with their nested content. These are sibling fields of a list item's object.
  defp take_item_siblings([{content, indent, false} | rest], base_depth)
       when indent == base_depth do
    if starts_with_list_marker(content) do
      {[], [{content, indent, false} | rest]}
    else
      {nested, remaining} = take_nested(rest, base_depth)
      {[{content, indent, false} | nested], remaining}
    end
  end

  defp take_item_siblings(lines, _base_depth), do: {[], lines}

  defp starts_with_list_marker(<<"-", _::binary>>), do: true
  defp starts_with_list_marker(_), do: false

  # Check for blank lines that appear before nested content within a list item
  # (strict mode). A blank line between the hyphen line and its continuation
  # fields is an error per spec §12.
  defp check_no_blank_before_nested([], _item_indent), do: :ok

  defp check_no_blank_before_nested([{_, _, true} | rest], item_indent) do
    case peek_indent(rest) do
      ind when ind > item_indent ->
        raise DecodeError,
          message: "Blank lines are not allowed inside list item fields in strict mode"

      _ ->
        :ok
    end
  end

  defp check_no_blank_before_nested([{_content, indent, false} | _rest], item_indent)
       when indent > item_indent do
    :ok
  end

  defp check_no_blank_before_nested([{_content, _indent, false} | _rest], _item_indent) do
    :ok
  end

  # Take tabular rows at a specific depth
  defp take_tabular_rows_at_depth(lines, depth, delimiter, _field_count, opts) do
    do_take_tab_rows(lines, depth, delimiter, opts, [])
  end

  defp do_take_tab_rows([], _depth, _delim, _opts, acc), do: {:lists.reverse(acc), []}

  defp do_take_tab_rows([{_, _, true} | rest], depth, delim, opts, acc) do
    # Allow blank lines before the first row (between header and first row)
    if opts.strict and acc != [] do
      raise DecodeError, message: "Blank lines are not allowed inside arrays in strict mode"
    else
      do_take_tab_rows(rest, depth, delim, opts, acc)
    end
  end

  defp do_take_tab_rows([{content, indent, false} = line | rest], depth, delim, opts, acc)
       when indent >= depth do
    if is_row_line(content, delim) do
      do_take_tab_rows(rest, depth, delim, opts, [line | acc])
    else
      {:lists.reverse(acc), [line | rest]}
    end
  end

  defp do_take_tab_rows(lines, _depth, _delim, _opts, acc), do: {:lists.reverse(acc), lines}

  # Take sibling fields at a specific depth
  defp take_siblings_at_depth(lines, depth, opts) do
    do_take_siblings(lines, depth, opts, [])
  end

  defp do_take_siblings([], _depth, _opts, acc), do: {:lists.reverse(acc), []}

  defp do_take_siblings([{_, _, true} | rest], depth, opts, acc) do
    do_take_siblings(rest, depth, opts, acc)
  end

  defp do_take_siblings([{_, indent, _} = line | rest], depth, opts, acc) when indent == depth do
    # Sibling at same depth – include it and its nested content
    {nested, remaining} = take_nested(rest, depth)
    all = [line | nested]
    do_take_siblings(remaining, depth, opts, :lists.reverse(all) ++ :lists.reverse(acc))
  end

  defp do_take_siblings(lines, _depth, _opts, acc), do: {:lists.reverse(acc), lines}

  # ── Header Parsing (Binary Pattern Matching) ───────────────────────────────

  # Parse root tabular header: [N]{fields}: (no closing bracket before field list)
  defp parse_root_tabular_header(content) do
    {count_str, after_digits} = take_digits(content, 1, <<>>)

    if count_str == <<>> do
      raise DecodeError, message: "Invalid array header: missing count", input: content
    end

    count = String.to_integer(count_str)

    # Check for delimiter symbol or closing bracket - only tab, pipe, comma allowed before ]
    {delimiter, after_bracket} =
      case after_digits do
        <<?\t, rest::binary>> ->
          {@tab, rest}

        <<"|", rest::binary>> ->
          {@pipe, rest}

        <<?,, rest::binary>> ->
          {@comma, rest}

        <<"]", rest::binary>> ->
          {@comma, rest}

        _ ->
          raise DecodeError,
            message: "Invalid array header: invalid delimiter or whitespace",
            input: content
      end

    # Skip ] if not already consumed by the delimiter case
    after_bracket =
      case after_bracket do
        <<"]", rest::binary>> -> rest
        _ -> after_bracket
      end

    # Parse fields segment from remaining content (starts with {)
    {fields, _after_fields} = parse_fields_segment(after_bracket, delimiter)
    {count, delimiter, fields}
  end

  # Parse root keyed header: [N:<delim?>]{fields}:
  defp parse_root_keyed_header(content) do
    {count, delimiter, after_bracket} = parse_keyed_bracket_from_start(content, 1)
    {fields, _after_fields} = parse_fields_segment(after_bracket, delimiter)
    {count, delimiter, fields}
  end

  # Parse root list header: [N<delim?>]:
  defp parse_root_list_header(content) do
    {count, delimiter, _after_bracket} = parse_bracket_from_start(content, 1)
    {count, delimiter}
  end

  # Parse root inline header: [N<delim?>]: values
  defp parse_root_inline_header(content) do
    {count, delimiter, after_bracket} = parse_bracket_from_start(content, 1)

    # After bracket: should be ": values" or just ":"
    case after_bracket do
      <<": ", values::binary>> ->
        {count, delimiter, values}

      ":" ->
        {count, delimiter, <<>>}

      _ ->
        raise DecodeError, message: "Invalid inline array header", input: content
    end
  end

  # Parse bracket segment starting at position `pos` in `content`.
  # Returns {count, delimiter, rest_after_bracket}
  defp parse_bracket_from_start(content, pos) do
    # content[pos] should be right after '['
    # Parse digits for count
    {count_str, after_digits} = take_digits(content, pos, <<>>)

    if count_str == <<>> do
      raise DecodeError, message: "Invalid array header: missing count", input: content
    end

    # Validate digit format (no leading zeros unless 0 itself)
    if byte_size(count_str) > 1 and :binary.first(count_str) == ?0 do
      raise DecodeError, message: "Invalid array header: leading zero in count", input: content
    end

    count = String.to_integer(count_str)

    # Check for delimiter symbol or closing bracket - only tab, pipe, comma allowed before ]
    {delimiter, after_bracket} =
      case after_digits do
        <<?\t, rest::binary>> ->
          {@tab, rest}

        <<"|", rest::binary>> ->
          {@pipe, rest}

        <<?,, rest::binary>> ->
          {@comma, rest}

        <<"]", rest::binary>> ->
          {@comma, rest}

        _ ->
          raise DecodeError,
            message: "Invalid array header: invalid delimiter or whitespace",
            input: content
      end

    # Skip ] if not already consumed by the delimiter case
    after_bracket =
      case after_bracket do
        <<"]", rest::binary>> -> rest
        _ -> after_bracket
      end

    {count, delimiter, after_bracket}
  end

  # Parse keyed bracket segment: [N<:><delim?>]
  # Returns {count, delimiter, rest_after_bracket}
  defp parse_keyed_bracket_from_start(content, pos) do
    {count_str, after_digits} = take_digits(content, pos, <<>>)

    if count_str == <<>> do
      raise DecodeError, message: "Invalid keyed header: missing count", input: content
    end

    count = String.to_integer(count_str)

    # Expect ':' after count
    case after_digits do
      <<":", rest::binary>> ->
        # Optional delimiter after colon, then ]
        {delimiter, after_delim} =
          case rest do
            <<?\t, r::binary>> -> {@tab, r}
            <<"|", r::binary>> -> {@pipe, r}
            _ -> {@comma, rest}
          end

        case after_delim do
          <<"]", r::binary>> -> {count, delimiter, r}
          _ -> raise DecodeError, message: "Invalid keyed header: missing ]", input: content
        end

      _ ->
        raise DecodeError, message: "Invalid keyed header: expected : after count", input: content
    end
  end

  # Take consecutive digits starting at position
  defp take_digits(content, pos, acc) when pos >= byte_size(content), do: {acc, <<>>}

  defp take_digits(content, pos, acc) do
    case binary_part(content, pos, 1) do
      <<c>> when c >= ?0 and c <= ?9 ->
        take_digits(content, pos + 1, <<acc::binary, c>>)

      _ ->
        {acc, binary_part(content, pos, byte_size(content) - pos)}
    end
  end

  # Parse fields segment: {field1<delim>field2...}
  defp parse_fields_segment(content, delimiter) do
    case content do
      <<"{", rest::binary>> ->
        # Find closing }
        case find_closing_brace(rest) do
          {:found, fields_str, after_brace} ->
            fields = parse_fields_string(fields_str, delimiter)
            {fields, after_brace}

          :not_found ->
            raise DecodeError, message: "Unterminated fields segment", input: content
        end

      _ ->
        {[], content}
    end
  end

  # Find closing } in binary, handling quoted field names and nested {}
  defp find_closing_brace(content) do
    do_find_closing_brace(content, 0, false, 0)
  end

  defp do_find_closing_brace(content, pos, in_quote, depth) do
    if pos >= byte_size(content) do
      :not_found
    else
      <<c, _::binary>> = binary_part(content, pos, byte_size(content) - pos)

      cond do
        c == ?" and not in_quote ->
          do_find_closing_brace(content, pos + 1, true, depth)

        c == ?" and in_quote ->
          if pos > 0 and binary_part(content, pos - 1, 1) == "\\" do
            do_find_closing_brace(content, pos + 1, true, depth)
          else
            do_find_closing_brace(content, pos + 1, false, depth)
          end

        c == ?{ and not in_quote ->
          do_find_closing_brace(content, pos + 1, in_quote, depth + 1)

        c == ?} and not in_quote and depth > 0 ->
          do_find_closing_brace(content, pos + 1, in_quote, depth - 1)

        c == ?} and not in_quote and depth == 0 ->
          fields_str = binary_part(content, 0, pos)
          after_brace = binary_part(content, pos + 1, byte_size(content) - pos - 1)
          {:found, fields_str, after_brace}

        true ->
          do_find_closing_brace(content, pos + 1, in_quote, depth)
      end
    end
  end

  # Parse fields string (between { and }) by delimiter.
  # Returns a list of field entries: leaf fields as strings, nested groups as
  # {:group, name, subfields}.
  defp parse_fields_string(fields_str, delimiter) do
    if fields_str == "" or String.trim(fields_str) == "" do
      []
    else
      if not String.contains?(fields_str, ["\"", "{"]) do
        # Fast path: no quotes, no nested groups — plain identifiers
        fields_str
        |> :binary.split(delimiter, [:global])
        |> Enum.map(&trim_leading/1)
        |> Enum.map(&trim_trailing/1)
      else
        # Full parse: quotes and/or nested groups
        split_fields_respecting_groups(fields_str, delimiter)
        |> Enum.map(&parse_single_field_entry(&1, delimiter))
      end
    end
  end

  # Split fields string by delimiter at depth 0 (outside braces and quotes)
  defp split_fields_respecting_groups(str, delimiter) do
    do_split_fields(str, delimiter, [], false, 0, [])
  end

  defp do_split_fields(<<>>, _delim, current, _in_quote, 0, acc) do
    entry = current |> :lists.reverse() |> IO.iodata_to_binary() |> String.trim()
    :lists.reverse([entry | acc])
  end

  defp do_split_fields(<<>>, _delim, _current, _in_quote, _depth, _acc) do
    raise DecodeError, message: "Unterminated nested field group"
  end

  defp do_split_fields(<<"\\", char, rest::binary>>, delim, current, in_quote, depth, acc) do
    do_split_fields(rest, delim, [<<char>>, "\\" | current], in_quote, depth, acc)
  end

  defp do_split_fields(<<"\"", rest::binary>>, delim, current, in_quote, depth, acc) do
    do_split_fields(rest, delim, ["\"" | current], not in_quote, depth, acc)
  end

  defp do_split_fields(<<c, rest::binary>>, delim, current, false, 0, acc)
       when <<c>> == delim do
    entry = current |> :lists.reverse() |> IO.iodata_to_binary() |> String.trim()
    do_split_fields(rest, delim, [], false, 0, [entry | acc])
  end

  defp do_split_fields(<<?{, rest::binary>>, delim, current, false, depth, acc) do
    do_split_fields(rest, delim, [?{ | current], false, depth + 1, acc)
  end

  defp do_split_fields(<<?}, rest::binary>>, delim, current, false, depth, acc) when depth > 0 do
    do_split_fields(rest, delim, [?} | current], false, depth - 1, acc)
  end

  defp do_split_fields(<<char, rest::binary>>, delim, current, in_quote, depth, acc) do
    do_split_fields(rest, delim, [char | current], in_quote, depth, acc)
  end

  # Parse a single field entry which may be a leaf or a nested group
  defp parse_single_field_entry(entry, delimiter) do
    trimmed = String.trim(entry)

    case trimmed do
      <<"\"", _::binary>> ->
        unquote_key(trimmed)

      _ ->
        case :binary.match(trimmed, "{") do
          {pos, _} ->
            field_name = binary_part(trimmed, 0, pos) |> String.trim()
            inner = binary_part(trimmed, pos + 1, byte_size(trimmed) - pos - 2)
            subfields = parse_fields_string(inner, delimiter)
            {:group, field_name, subfields}

          :nomatch ->
            trimmed
        end
    end
  end

  # Count leaf fields in a field tree
  defp leaf_count(fields) do
    Enum.reduce(fields, 0, fn
      {:group, _name, subfields}, acc -> acc + leaf_count(subfields)
      _leaf, acc -> acc + 1
    end)
  end

  # Check for empty field list and duplicate field names (strict mode only)
  defp validate_fields_strict(fields, content, opts) do
    if opts.strict do
      check_fields_strict(fields, content)
    end
  end

  defp check_fields_strict([], content) do
    raise DecodeError,
      message: "Empty field list in strict mode",
      input: content
  end

  defp check_fields_strict(fields, content) do
    # Check for duplicate names at this level
    names =
      Enum.map(fields, fn
        {:group, name, _} -> name
        leaf -> leaf
      end)

    seen = MapSet.new()
    check_duplicate_names(names, seen, content)

    # Recursively check nested groups
    Enum.each(fields, fn
      {:group, _name, subfields} -> check_fields_strict(subfields, content)
      _leaf -> :ok
    end)
  end

  defp check_duplicate_names([], _seen, _content), do: :ok

  defp check_duplicate_names([name | rest], seen, content) do
    if MapSet.member?(seen, name) do
      raise DecodeError,
        message: "Duplicate field name in header: #{inspect(name)}",
        input: content
    end

    check_duplicate_names(rest, MapSet.put(seen, name), content)
  end

  defp do_build_nested([], values, _opts), do: {%{}, values}

  defp do_build_nested([field | rest], values, opts) do
    {entry_map, remaining} =
      case field do
        {:group, name, subfields} ->
          {sub_map, after_values} = do_build_nested(subfields, values, opts)
          {%{name => sub_map}, after_values}

        leaf_name ->
          [value | remaining_values] = values
          {%{leaf_name => value}, remaining_values}
      end

    {rest_map, final_remaining} = do_build_nested(rest, remaining, opts)
    {Map.merge(entry_map, rest_map), final_remaining}
  end

  # Parse tabular header content: key[N<delim?>]{fields}:
  # Returns {key, count, delimiter, fields}
  defp parse_tabular_header_content(content) do
    # Find [ position
    case :binary.match(content, "[") do
      {bracket_pos, 1} ->
        key_part = binary_part(content, 0, bracket_pos)
        key = unquote_key(key_part)

        {count, delimiter, after_bracket} =
          parse_bracket_from_start(content, bracket_pos + 1)

        {fields, _after_fields} = parse_fields_segment(after_bracket, delimiter)
        {key, count, delimiter, fields}

      :nomatch ->
        raise DecodeError, message: "Invalid tabular header", input: content
    end
  end

  # Parse keyed header content: key[N:<delim?>]{fields}:
  # Returns {key, count, delimiter, fields}
  defp parse_keyed_header_content(content) do
    case :binary.match(content, "[") do
      {bracket_pos, 1} ->
        key_part = binary_part(content, 0, bracket_pos)
        key = unquote_key(key_part)

        {count, delimiter, after_bracket} =
          parse_keyed_bracket_from_start(content, bracket_pos + 1)

        {fields, _after_fields} = parse_fields_segment(after_bracket, delimiter)
        {key, count, delimiter, fields}

      :nomatch ->
        raise DecodeError, message: "Invalid keyed header", input: content
    end
  end

  # Parse list header content: key[N<delim?>]:
  # Returns {key, count, delimiter}
  defp parse_list_header_content(content) do
    case :binary.match(content, "[") do
      {bracket_pos, 1} ->
        key_part = binary_part(content, 0, bracket_pos)
        key = unquote_key(key_part)

        {count, delimiter, _after_bracket} =
          parse_bracket_from_start(content, bracket_pos + 1)

        {key, count, delimiter}

      :nomatch ->
        raise DecodeError, message: "Invalid list header", input: content
    end
  end

  # Parse array header from key_part (before ": ")
  # Returns {key, count, delimiter, fields, extra_remaining}
  # extra_remaining is the text after the bracket/fields segment (if any).
  # A non-empty extra_remaining means the key_part is a literal key (fall-through mode).
  defp parse_array_header_from_parts(key_part) do
    # Skip quoted prefix when searching for the array bracket
    search_start =
      case key_part do
        <<"\"", rest::binary>> ->
          case find_closing_quote(rest, 0) do
            {:found, end_pos} -> end_pos + 2
            :not_found -> 0
          end

        _ ->
          0
      end

    scope_len = byte_size(key_part) - search_start

    case :binary.match(key_part, "[", [{:scope, {search_start, scope_len}}]) do
      {bracket_pos, 1} ->
        key_part_before = binary_part(key_part, 0, bracket_pos)
        key = unquote_key(key_part_before)

        {count, delimiter, after_bracket} =
          parse_bracket_from_start(key_part, bracket_pos + 1)

        {fields, extra_remaining} = parse_fields_segment(after_bracket, delimiter)
        {key, count, delimiter, fields, extra_remaining}

      :nomatch ->
        raise DecodeError, message: "Invalid array header", input: key_part
    end
  end

  # ── Value Parsing ───────────────────────────────────────────────────────────

  defp parse_value(str) do
    size = byte_size(str)

    cond do
      size == 0 ->
        ""

      # Fast-path: check first byte for common cases
      true ->
        first = :binary.first(str)

        cond do
          # Quoted string
          first == ?" ->
            unquote_string(str)

          # Check for whitespace that needs trimming
          first == ?\s or first == ?\t ->
            trimmed = trim_leading(str) |> trim_trailing()
            do_parse_value(trimmed)

          # Check last byte for trailing whitespace
          :binary.last(str) in [?\s, ?\t] ->
            trimmed = trim_trailing(str)
            do_parse_value(trimmed)

          true ->
            do_parse_value(str)
        end
    end
  end

  defp do_parse_value("null"), do: nil
  defp do_parse_value("true"), do: true
  defp do_parse_value("false"), do: false
  defp do_parse_value("[]"), do: []
  defp do_parse_value(<<"\"", _::binary>> = str), do: unquote_string(str)
  defp do_parse_value(str), do: parse_number_or_string(str)

  # Per TOON spec: numbers with leading zeros (except "0" itself) are treated as strings
  defp parse_number_or_string("0"), do: 0
  defp parse_number_or_string("-0"), do: 0

  # Leading zeros make it a string (e.g., "05", "-007")
  defp parse_number_or_string(<<"0", d, _::binary>> = str) when d in ?0..?9, do: str
  defp parse_number_or_string(<<"-0", d, _::binary>> = str) when d in ?0..?9, do: str

  # Leading plus is treated as a string (e.g., "+5", "+inf")
  defp parse_number_or_string(<<"+", _::binary>> = str), do: str

  # Fast path: if first byte is a letter (A-Z, a-z) or underscore, it's a string.
  # This avoids the expensive Float.parse call for the most common case in
  # tabular data — simple string values like "Alice", "active", "user@example.com".
  # Binary pattern matching on the first byte is O(1) and compiled to a jump table.
  defp parse_number_or_string(<<c, _::binary>> = str) when c >= ?A and c <= ?Z, do: str
  defp parse_number_or_string(<<c, _::binary>> = str) when c >= ?a and c <= ?z, do: str
  defp parse_number_or_string(<<?_, _::binary>> = str), do: str

  # Fast path: if first byte is a digit or minus, try Integer.parse first
  # (cheaper than Float.parse for the common integer case).
  # Only fall back to Float.parse if Integer.parse finds a decimal/exponent.
  defp parse_number_or_string(str) do
    case Integer.parse(str) do
      {num, ""} ->
        num

      {_num, _rest} ->
        # Partial integer parse — might be a float (has "." or "e"/"E")
        case Float.parse(str) do
          {fnum, ""} -> normalize_number(fnum, str)
          _ -> str
        end

      :error ->
        # Not a number at all — return as string
        str
    end
  end

  # Convert parsed float to appropriate type based on original string format
  defp normalize_number(num, str) do
    if has_decimal_or_exponent(str) do
      if num == trunc(num), do: trunc(num), else: num
    else
      try_parse_int(str)
    end
  end

  # Try to parse as integer – faster path for the common case
  defp try_parse_int(str) do
    case Integer.parse(str) do
      {num, ""} -> num
      _ -> str
    end
  end

  # Single-pass binary scan for decimal point or exponent
  defp has_decimal_or_exponent(<<>>), do: false
  defp has_decimal_or_exponent(<<?., _::binary>>), do: true
  defp has_decimal_or_exponent(<<c, _::binary>>) when c == ?e or c == ?E, do: true
  defp has_decimal_or_exponent(<<_, rest::binary>>), do: has_decimal_or_exponent(rest)

  # ── String Handling ─────────────────────────────────────────────────────────

  # Unquote a key – strips surrounding quotes and unescapes
  # Check if a trimmed string is a quoted key followed by ":" (e.g., "key": value).
  # Returns false for quoted string primitives like "room:lobby" where the colon
  # is inside the quotes, not after the closing quote.
  defp quoted_key_value?(<<"\"", _::binary>> = trimmed) do
    case find_closing_quote(trimmed, 1) do
      {:found, end_pos} ->
        next_pos = end_pos + 1
        next_pos < byte_size(trimmed) and binary_part(trimmed, next_pos, 1) == ":"

      :not_found ->
        false
    end
  end

  defp quoted_key_value?(_), do: false

  defp unquote_key(<<"\"", rest::binary>>) do
    case do_strip_trailing_quote(rest) do
      {:ok, inner} ->
        unescape_string(inner)

      :error ->
        raise DecodeError, message: "Unterminated quoted key", input: <<"\"", rest::binary>>
    end
  end

  defp unquote_key(key), do: key

  # Strip trailing quote from a binary, returning {:ok, inner} or :error
  defp do_strip_trailing_quote(<<>>), do: :error
  defp do_strip_trailing_quote(<<"\\">>), do: :error
  defp do_strip_trailing_quote(<<"\"">>), do: {:ok, <<>>}
  defp do_strip_trailing_quote(<<"\"", _::binary>>), do: :error

  defp do_strip_trailing_quote(binary) do
    size = byte_size(binary)
    <<last>> = binary_part(binary, size - 1, 1)

    if last == ?" do
      {:ok, binary_part(binary, 0, size - 1)}
    else
      :error
    end
  end

  # Unquote a string value
  defp unquote_string(<<"\"", rest::binary>>) do
    size = byte_size(rest)

    if size > 0 and :binary.last(rest) == ?" do
      inner = binary_part(rest, 0, size - 1)
      unescape_string(inner)
    else
      raise DecodeError, message: "Unterminated quoted string", input: <<"\"", rest::binary>>
    end
  end

  defp unquote_string(str), do: str

  # Jason-style zero-copy unescape: scan the original binary once, building
  # an iodata list of binary_part slices (O(1) sub-binary references) and
  # escape replacement strings.
  defp unescape_string(str), do: do_unescape(str, str, 0, [])

  defp do_unescape(<<>>, original, skip, acc),
    do: finalize_unescape(acc, original, skip, 0)

  defp do_unescape(<<"\\">>, _original, _skip, _acc),
    do: raise(DecodeError, message: "Unterminated escape sequence", input: "\\")

  # Unicode escape \uXXXX
  defp do_unescape(<<"\\", ?u, h1, h2, h3, h4, rest::binary>>, original, skip, acc) do
    acc = flush_unescape_chunk(acc, original, skip, 0)

    code =
      hex_to_int(h1) * 4096 + hex_to_int(h2) * 256 + hex_to_int(h3) * 16 + hex_to_int(h4)

    replacement = <<code::utf8>>
    do_unescape(rest, original, skip + 6, [replacement | acc])
  end

  # Incomplete \u - error
  defp do_unescape(<<"\\", ?u, _rest::binary>>, _original, _skip, _acc),
    do: raise(DecodeError, message: "Invalid escape sequence: \\u", input: "\\u")

  # Simple escapes: \\, \", \n, \r, \t
  defp do_unescape(<<"\\", char, rest::binary>>, original, skip, acc) do
    acc = flush_unescape_chunk(acc, original, skip, 0)
    replacement = escape_char(char)
    do_unescape(rest, original, skip + 2, [replacement | acc])
  end

  defp do_unescape(<<_byte, rest::binary>>, original, skip, acc),
    do: do_unescape_chunk(rest, original, skip, 1, acc)

  defp do_unescape_chunk(<<>>, original, skip, len, acc),
    do: finalize_unescape([binary_part(original, skip, len) | acc], original, skip, 0)

  defp do_unescape_chunk(<<"\\">>, _original, _skip, _len, _acc),
    do: raise(DecodeError, message: "Unterminated escape sequence", input: "\\")

  defp do_unescape_chunk(<<"\\", ?u, h1, h2, h3, h4, rest::binary>>, original, skip, len, acc) do
    part = binary_part(original, skip, len)

    code =
      hex_to_int(h1) * 4096 +
        hex_to_int(h2) * 256 +
        hex_to_int(h3) * 16 +
        hex_to_int(h4)

    replacement = <<code::utf8>>
    do_unescape(rest, original, skip + len + 6, [replacement, part | acc])
  end

  defp do_unescape_chunk(<<"\\", ?u, _rest::binary>>, _original, _skip, _len, _acc),
    do: raise(DecodeError, message: "Invalid escape sequence: \\u", input: "\\u")

  defp do_unescape_chunk(<<"\\", char, rest::binary>>, original, skip, len, acc) do
    part = binary_part(original, skip, len)
    replacement = escape_char(char)
    do_unescape(rest, original, skip + len + 2, [replacement, part | acc])
  end

  defp do_unescape_chunk(<<_byte, rest::binary>>, original, skip, len, acc),
    do: do_unescape_chunk(rest, original, skip, len + 1, acc)

  @compile {:inline, flush_unescape_chunk: 4}
  defp flush_unescape_chunk(acc, _original, _skip, 0), do: acc

  defp flush_unescape_chunk(acc, original, skip, len),
    do: [binary_part(original, skip, len) | acc]

  @compile {:inline, finalize_unescape: 4}
  defp finalize_unescape(acc, _original, _skip, 0),
    do: acc |> :lists.reverse() |> IO.iodata_to_binary()

  defp finalize_unescape(acc, original, skip, len),
    do: [binary_part(original, skip, len) | acc] |> :lists.reverse() |> IO.iodata_to_binary()

  defp escape_char(?\\), do: "\\"
  defp escape_char(?"), do: "\""
  defp escape_char(?n), do: "\n"
  defp escape_char(?r), do: "\r"
  defp escape_char(?t), do: "\t"

  defp escape_char(char),
    do:
      raise(DecodeError, message: "Invalid escape sequence: \\#{<<char>>}", input: <<?\\, char>>)

  # Convert hex digit to integer (case-insensitive)
  defp hex_to_int(char) when char >= ?0 and char <= ?9, do: char - ?0
  defp hex_to_int(char) when char >= ?a and char <= ?f, do: char - ?a + 10
  defp hex_to_int(char) when char >= ?A and char <= ?F, do: char - ?A + 10

  defp hex_to_int(_),
    do: raise(DecodeError, message: "Invalid hex digit in escape sequence")

  # ── Delimiter Splitting ─────────────────────────────────────────────────────

  # Split and parse values in a single pass
  defp split_and_parse(str, delimiter) do
    actual_delimiter = detect_delimiter(str, delimiter)

    if not contains_byte(str, ?") do
      # Fast path: no quotes – use :binary.split (BIF) then list comprehension.
      # List comprehension compiles to a tighter loop than Enum.map because
      # it avoids the Enumerable protocol overhead and the closure allocation
      # for &parse_value/1.
      parts = :binary.split(str, actual_delimiter, [:global])
      for part <- parts, do: parse_value(part)
    else
      # Slow path: quotes present – use quote-aware splitting
      do_split_and_parse(str, actual_delimiter, [], false, [])
    end
  end

  # Quote-aware split and parse
  defp do_split_and_parse("", _delimiter, current, _in_quote, acc) do
    current_str =
      current
      |> :lists.reverse()
      |> IO.iodata_to_binary()
      |> trim_leading()
      |> trim_trailing()

    :lists.reverse([parse_value(current_str) | acc])
  end

  defp do_split_and_parse(<<"\\", char, rest::binary>>, delimiter, current, in_quote, acc) do
    do_split_and_parse(rest, delimiter, [<<char>>, "\\" | current], in_quote, acc)
  end

  defp do_split_and_parse(<<"\"", rest::binary>>, delimiter, current, in_quote, acc) do
    do_split_and_parse(rest, delimiter, ["\"" | current], not in_quote, acc)
  end

  defp do_split_and_parse(<<char, rest::binary>>, delimiter, current, false, acc)
       when <<char>> == delimiter do
    current_str =
      current
      |> :lists.reverse()
      |> IO.iodata_to_binary()
      |> trim_leading()
      |> trim_trailing()

    do_split_and_parse(rest, delimiter, [], false, [parse_value(current_str) | acc])
  end

  defp do_split_and_parse(<<char, rest::binary>>, delimiter, current, in_quote, acc) do
    do_split_and_parse(rest, delimiter, [<<char>> | current], in_quote, acc)
  end

  # Split and parse cell values for tabular entries.
  # Per spec §9.5: the [] empty-array token is NOT recognized in tabular cells;
  # it is treated as the literal string "[]".
  defp split_and_parse_cells(str, delimiter) do
    actual_delimiter = detect_delimiter(str, delimiter)

    if not contains_byte(str, ?") do
      parts = :binary.split(str, actual_delimiter, [:global])
      for part <- parts, do: parse_cell_value(part)
    else
      do_split_and_parse_cells(str, actual_delimiter, [], false, [])
    end
  end

  defp parse_cell_value("[]"), do: "[]"
  defp parse_cell_value(str), do: parse_value(str)

  defp do_split_and_parse_cells("", _delimiter, current, _in_quote, acc) do
    current_str =
      current
      |> :lists.reverse()
      |> IO.iodata_to_binary()
      |> trim_leading()
      |> trim_trailing()

    :lists.reverse([parse_cell_value(current_str) | acc])
  end

  defp do_split_and_parse_cells(<<"\\", char, rest::binary>>, delimiter, current, in_quote, acc) do
    do_split_and_parse_cells(rest, delimiter, [<<char>>, "\\" | current], in_quote, acc)
  end

  defp do_split_and_parse_cells(<<"\"", rest::binary>>, delimiter, current, in_quote, acc) do
    do_split_and_parse_cells(rest, delimiter, ["\"" | current], not in_quote, acc)
  end

  defp do_split_and_parse_cells(<<char, rest::binary>>, delimiter, current, false, acc)
       when <<char>> == delimiter do
    current_str =
      current
      |> :lists.reverse()
      |> IO.iodata_to_binary()
      |> trim_leading()
      |> trim_trailing()

    do_split_and_parse_cells(rest, delimiter, [], false, [parse_cell_value(current_str) | acc])
  end

  defp do_split_and_parse_cells(<<char, rest::binary>>, delimiter, current, in_quote, acc) do
    do_split_and_parse_cells(rest, delimiter, [<<char>> | current], in_quote, acc)
  end

  # Auto-detect delimiter for comma-default case
  defp detect_delimiter(str, @comma) do
    if do_has_tab_no_comma(str), do: @tab, else: @comma
  end

  defp detect_delimiter(_str, delimiter), do: delimiter

  defp do_has_tab_no_comma(<<>>), do: false
  defp do_has_tab_no_comma(<<?\t, _::binary>>), do: true
  defp do_has_tab_no_comma(<<?,, _::binary>>), do: false

  defp do_has_tab_no_comma(<<?", rest::binary>>) do
    # Skip quoted content — tabs inside quotes don't count for auto-detection
    case find_closing_quote(rest, 0) do
      {:found, end_pos} ->
        after_quote = binary_part(rest, end_pos + 1, byte_size(rest) - end_pos - 1)
        do_has_tab_no_comma(after_quote)

      :not_found ->
        do_has_tab_no_comma(rest)
    end
  end

  defp do_has_tab_no_comma(<<_, rest::binary>>), do: do_has_tab_no_comma(rest)

  # ── Utility Functions ──────────────────────────────────────────────────────

  # Count leading spaces and return {trimmed, count}
  defp count_leading_spaces(<<?\s, rest::binary>>, n), do: count_leading_spaces(rest, n + 1)
  defp count_leading_spaces(<<?\t, rest::binary>>, n), do: count_leading_spaces(rest, n + 1)
  defp count_leading_spaces(rest, n), do: {rest, n}

  defp trim_leading(<<?\s, rest::binary>>), do: trim_leading(rest)
  defp trim_leading(<<?\t, rest::binary>>), do: trim_leading(rest)
  defp trim_leading(str), do: str

  defp trim_trailing(str), do: trim_trailing(str, byte_size(str))

  defp trim_trailing(_str, 0), do: <<>>

  defp trim_trailing(str, size) do
    case :binary.last(str) do
      b when b == ?\s or b == ?\t -> trim_trailing(binary_part(str, 0, size - 1), size - 1)
      _ -> str
    end
  end

  # Find first ": " (colon-space) in binary
  defp find_colon_space(content) do
    case :binary.match(content, ": ") do
      {pos, 2} -> {:found, pos}
      :nomatch -> find_cs_fallback(content, 0)
    end
  end

  # Fallback: handle quoted keys that might contain ": "
  defp find_cs_fallback(content, pos) when pos >= byte_size(content), do: :not_found

  defp find_cs_fallback(content, pos) do
    <<c, _::binary>> = binary_part(content, pos, byte_size(content) - pos)

    cond do
      c == ?" ->
        # Skip quoted section
        case find_closing_quote(content, pos + 1) do
          {:found, end_pos} -> find_cs_fallback(content, end_pos + 1)
          :not_found -> :not_found
        end

      c == ?: and pos + 1 < byte_size(content) ->
        <<next, _::binary>> = binary_part(content, pos + 1, byte_size(content) - pos - 1)
        if next == ?\s, do: {:found, pos}, else: find_cs_fallback(content, pos + 1)

      true ->
        find_cs_fallback(content, pos + 1)
    end
  end

  # Find closing quote, handling escapes
  defp find_closing_quote(content, pos) when pos >= byte_size(content), do: :not_found

  defp find_closing_quote(content, pos) do
    <<c, _::binary>> = binary_part(content, pos, byte_size(content) - pos)

    cond do
      c == ?" -> {:found, pos}
      c == ?\\ -> find_closing_quote(content, pos + 2)
      true -> find_closing_quote(content, pos + 1)
    end
  end

  # Check if binary contains a specific byte
  defp contains_byte(<<>>, _byte), do: false
  defp contains_byte(<<byte, _::binary>>, byte), do: true
  defp contains_byte(<<_, rest::binary>>, byte), do: contains_byte(rest, byte)

  # Check if binary ends with colon
  defp ends_with_colon(<<>>), do: false
  defp ends_with_colon(binary) when is_binary(binary), do: :binary.last(binary) == ?:

  # Strip trailing colon
  defp strip_trailing_colon(binary) do
    size = byte_size(binary)

    if size > 0 and :binary.last(binary) == ?: do
      binary_part(binary, 0, size - 1)
    else
      binary
    end
  end

  # Remove list marker "- " or "-"
  defp remove_list_marker(content) do
    content |> trim_leading() |> strip_dash_prefix()
  end

  defp strip_dash_prefix(<<?-, ?\s, rest::binary>>), do: rest
  defp strip_dash_prefix(<<?-, rest::binary>>), do: rest
  defp strip_dash_prefix(binary), do: binary

  # Check if content is whitespace only (spaces, tabs, carriage returns)
  defp is_whitespace_only(<<>>), do: true
  defp is_whitespace_only(<<?\s, rest::binary>>), do: is_whitespace_only(rest)
  defp is_whitespace_only(<<?\t, rest::binary>>), do: is_whitespace_only(rest)
  defp is_whitespace_only(<<?\r, rest::binary>>), do: is_whitespace_only(rest)
  defp is_whitespace_only(_), do: false

  # Check if trimmed content is a comment line (starts with # after whitespace removal)
  # Empty or nil content is never a comment
  defp is_comment_line(<<>>), do: false
  defp is_comment_line(<<"#", _::binary>>), do: true
  defp is_comment_line(_), do: false

  # Check for "]: " pattern (inline array).
  # Scans the entire string for the `]: ` sequence.
  # NOTE: Callers that need to distinguish root inline arrays (`[2]: a,b`)
  # from key-prefixed inline arrays (`tags[2]: a,b`) must also check
  # whether the string starts with `[` before routing to
  # parse_inline_array_from_trimmed (which assumes `[` at position 0).
  defp has_bracket_colon_space(<<?], ?:, ?\s, _::binary>>), do: true
  defp has_bracket_colon_space(<<_, rest::binary>>), do: has_bracket_colon_space(rest)
  defp has_bracket_colon_space(<<>>), do: false

  # Check for keyed tabular header pattern: ends with "}:" and has [N:<delim?>] inside brackets
  # e.g., servers[2:]{host,port}: or servers[2:\t]{host\tport}:
  defp is_keyed_header(content) do
    size = byte_size(content)

    size >= 3 and :binary.last(content) == ?: and
      binary_part(content, size - 2, 1) == "}" and
      contains_byte(content, ?[) and
      has_keyed_bracket(content)
  end

  # Check if the content has a bracket with [N:<delim?>] pattern
  defp has_keyed_bracket(content) do
    case :binary.match(content, "[") do
      {pos, 1} ->
        after_bracket = binary_part(content, pos + 1, byte_size(content) - pos - 1)
        # Read digits after [
        {_digits, after_digits} = take_digits(after_bracket, 0, <<>>)
        # After digits should be :
        byte_size(after_digits) > 0 and :binary.first(after_digits) == ?:

      :nomatch ->
        false
    end
  end

  # Check for tabular header pattern: contains "}:" at end and "[" somewhere, but NOT keyed
  defp is_tabular_header(content) do
    size = byte_size(content)

    if size >= 2 do
      last = :binary.last(content)

      if last == ?: do
        second_last = :binary.first(binary_part(content, size - 2, 1))
        second_last == ?} and contains_byte(content, ?[) and not is_keyed_header(content)
      else
        false
      end
    else
      false
    end
  end

  # Check for list header pattern: ends with "]:" and contains "["
  defp is_list_header(content) do
    size = byte_size(content)

    if size >= 2 do
      last = :binary.last(content)

      if last == ?: do
        second_last = :binary.first(binary_part(content, size - 2, 1))
        second_last == ?] and contains_byte(content, ?[)
      else
        false
      end
    else
      false
    end
  end

  # Check for list array header: starts with "[" and ends with "]:"
  defp is_list_array_header(<<?[, _::binary>> = binary) do
    size = byte_size(binary)

    size >= 2 and :binary.last(binary) == ?: and
      :binary.first(binary_part(binary, size - 2, 1)) == ?]
  end

  defp is_list_array_header(_), do: false

  # Check if key_part has array marker (contains "[")
  defp has_array_marker(<<"\"", rest::binary>>) do
    case find_closing_quote(rest, 0) do
      {:found, end_pos} ->
        after_quote = binary_part(rest, end_pos + 1, byte_size(rest) - end_pos - 1)
        contains_byte(after_quote, ?[)

      :not_found ->
        false
    end
  end

  defp has_array_marker(content), do: contains_byte(content, ?[)

  # Check if a line is a tabular row (no unquoted colon, or delimiter before colon)
  defp is_row_line(content, delimiter) do
    # Fast path: find first unquoted colon
    case find_unquoted_byte(content, ?:) do
      :not_found ->
        # No colon → definitely a row
        true

      {:found, colon_pos} ->
        # Has colon – check if delimiter appears before it
        case find_unquoted_byte(content, :binary.first(delimiter)) do
          :not_found ->
            # Has colon but no delimiter → key-value line
            false

          {:found, delim_pos} ->
            # Delimiter before colon → row; otherwise → key-value line
            delim_pos < colon_pos
        end
    end
  end

  # Find first unquoted occurrence of a byte
  defp find_unquoted_byte(content, byte) do
    find_uqb(content, byte, 0, false)
  end

  defp find_uqb(<<>>, _byte, _pos, _in_quote), do: :not_found

  defp find_uqb(<<"\\", _, rest::binary>>, byte, pos, in_quote) do
    find_uqb(rest, byte, pos + 2, in_quote)
  end

  defp find_uqb(<<?", rest::binary>>, byte, pos, in_quote) do
    find_uqb(rest, byte, pos + 1, not in_quote)
  end

  defp find_uqb(<<c, _rest::binary>>, byte, pos, false) when c == byte do
    {:found, pos}
  end

  defp find_uqb(<<_, rest::binary>>, byte, pos, in_quote) do
    find_uqb(rest, byte, pos + 1, in_quote)
  end

  # Peek at next line's indent (skip blank lines)
  # Tuple format: {content, indent, is_blank}
  defp peek_indent([]), do: 0
  defp peek_indent([{_, _, true} | rest]), do: peek_indent(rest)
  defp peek_indent([{_, indent, _} | _]), do: indent

  # Get the indent of the first non-blank line
  # Tuple format: {content, indent, is_blank}
  defp first_content_indent([]), do: 0
  defp first_content_indent([{_, _, true} | rest]), do: first_content_indent(rest)
  defp first_content_indent([{_, indent, _} | _]), do: indent

  # Take lines that are more indented than base_depth
  # Returns {nested_lines, remaining_lines}
  defp take_nested(lines, base_depth) do
    do_take_nested(lines, base_depth, false, [])
  end

  defp do_take_nested([], _base, _seen, acc), do: {:lists.reverse(acc), []}

  defp do_take_nested([{_, indent, false} = line | rest], base, _seen, acc) when indent > base do
    do_take_nested(rest, base, true, [line | acc])
  end

  defp do_take_nested([{_, _, false} | _] = lines, _base, _seen, acc) do
    {:lists.reverse(acc), lines}
  end

  defp do_take_nested([{_, _, true} = line | rest], base, seen, acc) do
    if seen do
      case peek_indent(rest) do
        ind when ind > base -> do_take_nested(rest, base, true, [line | acc])
        _ -> {:lists.reverse(acc), [line | rest]}
      end
    else
      do_take_nested(rest, base, false, acc)
    end
  end

  # Check if a key was originally quoted
  defp key_was_quoted(<<"\"", _::binary>>), do: true
  defp key_was_quoted(<<?\s, rest::binary>>), do: key_was_quoted(rest)
  defp key_was_quoted(<<?\t, rest::binary>>), do: key_was_quoted(rest)
  defp key_was_quoted(_), do: false

  # Validate count (strict mode only)
  defp validate_count(actual, expected, input, opts) do
    if opts.strict and actual != expected do
      raise DecodeError,
        message: "Count mismatch: declared #{expected}, got #{actual}",
        input: input
    end
  end

  # ── Path Expansion ──────────────────────────────────────────────────────────

  # Expand dotted keys into nested objects per spec §13.4
  # key_order preserves document encounter order so that LWW (last-write-wins)
  # resolution in strict:false mode respects which key appeared later.
  # When key_order is empty (e.g., nested maps inside arrays have no tracked
  # order), fall back to Map.keys for deterministic processing.
  defp expand_paths(result, {key_order, quoted_keys_set}, strict) when is_map(result) do
    # Use key_order (reversed during parsing, so reverse again for document order)
    # instead of Map.to_list which has non-deterministic ordering.
    # Fall back to Map.keys when key_order is empty (nested maps in arrays).
    ordered_keys =
      case key_order do
        [] -> Map.keys(result)
        _ -> :lists.reverse(key_order)
      end

    do_expand_entries(ordered_keys, result, %{}, quoted_keys_set, strict)
  end

  defp expand_paths(result, _meta, _strict), do: result

  defp do_expand_entries([], _result_map, acc, _quoted_keys_set, _strict), do: acc

  defp do_expand_entries([key | rest], result_map, acc, quoted_keys_set, strict) do
    case Map.fetch(result_map, key) do
      :error ->
        # Key not present at this level (e.g., nested key leaked into key_order).
        # Skip it to avoid inserting spurious nil entries.
        do_expand_entries(rest, result_map, acc, quoted_keys_set, strict)

      {:ok, value} ->
        expanded_value = expand_paths_nested(value, quoted_keys_set, strict)

        new_acc =
          if expandable_key?(key) and not MapSet.member?(quoted_keys_set, key) do
            segments = :binary.split(key, ".", [:global])
            nested = build_nested_map(segments, expanded_value)
            deep_merge(acc, nested, strict)
          else
            # Use deep_merge instead of Map.put so that conflict detection
            # works when a non-expanded key (e.g., "a: 2") collides with an
            # earlier expanded key (e.g., "a.b: 1" → %{"a" => %{"b" => 1}}).
            # deep_merge's resolve_merge handles strict=true (error) and
            # strict=false (LWW: later value wins).
            deep_merge(acc, %{key => expanded_value}, strict)
          end

        do_expand_entries(rest, result_map, new_acc, quoted_keys_set, strict)
    end
  end

  defp expand_paths_nested(value, quoted_keys_set, strict) when is_map(value),
    do: expand_paths(value, {[], quoted_keys_set}, strict)

  defp expand_paths_nested(value, quoted_keys_set, strict) when is_list(value),
    do: Enum.map(value, &expand_paths_nested(&1, quoted_keys_set, strict))

  defp expand_paths_nested(value, _quoted_keys_set, _strict), do: value

  # Check if a key is expandable: contains "." and all segments are IdentifierSegments
  # Use Enum.all? instead of :lists.all because private function captures
  # (&valid_identifier_segment?/1) cannot be invoked by Erlang BIFs.
  defp expandable_key?(key) do
    contains_byte(key, ?.) and
      key
      |> :binary.split(".", [:global])
      |> Enum.all?(&valid_identifier_segment?/1)
  end

  # IdentifierSegment: [A-Za-z_][A-Za-z0-9_]*
  defp valid_identifier_segment?(<<first, rest::binary>>) when first in ?A..?Z,
    do: valid_id_rest?(rest)

  defp valid_identifier_segment?(<<first, rest::binary>>) when first in ?a..?z,
    do: valid_id_rest?(rest)

  defp valid_identifier_segment?(<<?_, rest::binary>>), do: valid_id_rest?(rest)
  defp valid_identifier_segment?(_), do: false

  defp valid_id_rest?(<<>>), do: true
  defp valid_id_rest?(<<c, rest::binary>>) when c in ?A..?Z, do: valid_id_rest?(rest)
  defp valid_id_rest?(<<c, rest::binary>>) when c in ?a..?z, do: valid_id_rest?(rest)
  defp valid_id_rest?(<<c, rest::binary>>) when c in ?0..?9, do: valid_id_rest?(rest)
  defp valid_id_rest?(<<?_, rest::binary>>), do: valid_id_rest?(rest)
  defp valid_id_rest?(_), do: false

  # Build nested map from path segments
  defp build_nested_map([segment], value), do: %{segment => value}
  defp build_nested_map([segment | rest], value), do: %{segment => build_nested_map(rest, value)}

  # Deep merge with conflict handling
  # Deep merge with conflict handling per spec §13.4.
  # When strict=true: any type conflict (object vs non-object) raises an error.
  # When strict=false: last-write-wins (LWW) — the value from map2 overwrites map1.
  # Since we process keys in document order and merge each expanded key into the
  # accumulator, map2 always represents the LATER value, so returning v2 on
  # conflict implements correct LWW semantics.
  defp deep_merge(map1, map2, strict) do
    Map.merge(map1, map2, &resolve_merge(&1, &2, &3, strict))
  end

  defp resolve_merge(_key, v1, v2, strict) when is_map(v1) and is_map(v2) do
    deep_merge(v1, v2, strict)
  end

  # Type conflict: one value is a map, the other is not.
  # strict=true → error per spec §14.5
  # strict=false → LWW: v2 (from map2, the later value) wins
  defp resolve_merge(key, _v1, _v2, true = _strict) do
    raise DecodeError, message: "Path expansion conflict at key '#{key}'", reason: :path_conflict
  end

  defp resolve_merge(_key, _v1, v2, false = _strict), do: v2
end
