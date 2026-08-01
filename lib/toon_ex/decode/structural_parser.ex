defmodule ToonEx.Decode.StructuralParser do
  @moduledoc """
  Structural parser for TOON format that handles indentation-based nesting.

  This parser processes TOON input by analyzing indentation levels and building
  a hierarchical structure from the flat text representation.
  """

  alias ToonEx.Decode.Parser
  alias ToonEx.DecodeError

  # Performance: Direct binary constants to eliminate function call overhead
  @colon ":"
  @space " "
  @comma ","
  @tab "\t"
  @pipe "|"
  @double_quote "\""

  # Performance: Inline hot functions to reduce function call overhead during decoding
  @compile {:inline,
            parse_value: 1,
            do_parse_value: 1,
            parse_number_or_string: 1,
            unquote_string: 1,
            unquote_key: 1,
            extract_delimiter: 1,
            parse_fields: 2,
            parse_delimited_values: 2,
            remove_list_marker: 1,
            line_kind: 1,
            empty_list_item_value?: 1,
            do_trim_leading: 1,
            do_trim_trailing: 1,
            has_decimal_or_exponent?: 1,
            detect_delimiter: 2}

  # Pre-compiled regex patterns for performance - avoids recompilation on every call
  @tabular_array_header_regex ~r/^((?:"[^"]*"|[\w.]+))(\[\d+.*\])\{([^}]+)\}:$/
  @root_tabular_array_regex ~r/^\[((\d+))([^\]]*)\]\{([^}]+)\}:$/
  @list_array_header_regex ~r/^((?:"[^"]*"|[\w.]+))(\[\d+[^\]]*\]):$/
  @array_length_regex ~r/\[(\d+)/
  @array_header_with_values_regex ~r/\[(\d+)([^\]]*)\]$/
  @inline_array_header_regex ~r/^\[([^\]]+)\]:\s*(.*)$/
  @array_header_with_colon_regex ~r/^[\w"]+(\[(\d+)[^\]]*\]):/

  # Module-level regex patterns for structural matching
  @tabular_header_pattern ~r/^(?:"[^"]*"|[\w.]+)\[\d+.*\]\{[^}]+\}:$/
  @list_header_pattern ~r/^(?:"[^"]*"|[\w.]+)\[\d+.*\]:$/
  @inline_array_pattern ~r/^\[.*?\]: .+/
  @list_array_header_pattern ~r/^\[\d+[^\]]*\]:$/
  @field_pattern ~r/^[\w"]+\s*:/
  @tabular_header_regex ~r/^((?:"[^"]*"|[\w.]+))(\[\d+.*\])\{([^}]+)\}:$/
  @list_array_regex ~r/^((?:"[^"]*"|[\w.]+))\[(\d+).*\]:$/

  @type line_info :: %{
          content: String.t(),
          indent: non_neg_integer(),
          line_number: non_neg_integer(),
          original: String.t()
        }

  @type parse_metadata :: %{
          quoted_keys: MapSet.t(String.t()),
          key_order: list(String.t())
        }

  @doc """
  Parses TOON input string into a structured format.

  Returns a tuple of {result, metadata} where metadata contains quoted_keys and key_order.
  """
  @spec parse(String.t(), map()) :: {:ok, {term(), parse_metadata()}} | {:error, DecodeError.t()}

  # In parse/2, reverse key_order once before returning:
  def parse(input, opts) when is_binary(input) do
    lines = preprocess_lines(input)

    if opts.strict, do: validate_indentation(lines, opts)

    initial_metadata = %{quoted_keys: MapSet.new(), key_order: []}

    {result, metadata} =
      case lines do
        [] -> {%{}, initial_metadata}
        _ -> parse_structure(lines, 0, opts, initial_metadata)
      end

    # Reverse once here — O(N) — instead of appending O(N) times above.
    final_metadata = %{metadata | key_order: Enum.reverse(metadata.key_order)}

    {:ok, {result, final_metadata}}
  rescue
    e in DecodeError ->
      {:error, e}

    e ->
      {:error,
       DecodeError.exception(message: "Parse failed: #{Exception.message(e)}", input: input)}
  end

  # Preprocess input into line information structures

  defp preprocess_lines(input) do
    input
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(&build_line_info/1)
    |> drop_trailing_blank()
  end

  defp build_line_info({line, line_num}) do
    trimmed = String.trim_leading(line)
    # Indent = bytes trimmed by trim_leading — works for ASCII spaces only,
    # which is correct (TOON spec: indentation is spaces, not arbitrary whitespace).
    indent = byte_size(line) - byte_size(trimmed)
    is_blank = trimmed == "" or String.trim_trailing(trimmed) == ""
    %{content: trimmed, indent: indent, line_number: line_num, original: line, is_blank: is_blank}
  end

  # Avoids the double Enum.reverse of the old "reverse → drop_while → reverse"
  # approach by finding the last non-blank index in a single forward pass.
  defp drop_trailing_blank(lines) do
    last_non_blank =
      lines
      |> Enum.with_index()
      |> Enum.reduce(-1, fn {line, idx}, acc ->
        if line.is_blank, do: acc, else: idx
      end)

    if last_non_blank < 0, do: [], else: Enum.take(lines, last_non_blank + 1)
  end

  # Validate indentation in strict mode
  defp validate_indentation(lines, opts) do
    Enum.each(lines, fn line ->
      # Skip blank lines
      unless line.is_blank do
        # Check for tab characters in INDENTATION only (not in content after the key/value starts)
        # We need to check the leading whitespace before any content
        # Find where content starts (first non-whitespace character)
        leading_whitespace =
          line.original
          |> String.to_charlist()
          |> Enum.take_while(&(&1 == ?\s or &1 == ?\t))
          |> List.to_string()

        if String.contains?(leading_whitespace, "\t") do
          raise DecodeError,
            message: "Tab characters are not allowed in indentation (strict mode)",
            input: line.original
        end

        # Check if indent is a multiple of indent_size
        if line.indent > 0 and rem(line.indent, opts.indent_size) != 0 do
          raise DecodeError,
            message: "Indentation must be a multiple of #{opts.indent_size} spaces (strict mode)",
            input: line.original
        end
      end
    end)
  end

  # Parse a structure starting from given lines at a specific indent level
  defp parse_structure(lines, base_indent, opts, metadata) do
    {root_type, _} = detect_root_type(lines)

    case root_type do
      :root_array ->
        parse_root_array(lines, opts, metadata)

      :root_primitive ->
        parse_root_primitive(lines, opts, metadata)

      :object ->
        parse_object_lines(lines, base_indent, opts, metadata)
    end
  end

  # Detect if the root is an array or object or primitive
  defp detect_root_type([%{content: content} | rest]) do
    cond do
      # Root array header patterns
      String.starts_with?(content, "[") ->
        {:root_array, :inline}

      String.match?(content, ~r/^\[.*\]\{.*\}:/) ->
        {:root_array, :tabular}

      String.match?(content, ~r/^\[.*\]:/) ->
        {:root_array, :list}

      # Single line -> check if it's a primitive or key-value
      rest == [] ->
        cond do
          # Tabular array header key[N]{fields}: ... — must be detected before
          # the generic key-value check because {fields} sits between [N] and ":"
          # and breaks the simpler regex.
          String.match?(content, ~r/^(?:"[^"]*"|[\w.]+)\[\d+[^\]]*\]\{[^}]+\}:/) ->
            # Route to :object so parse_entry_line raises DecodeError on the
            # missing / malformed data rows (4 declared, 0 present here).
            {:object, nil}

          # List array header key[N]: ... (inline value on header line is also invalid)
          String.match?(content, ~r/^(?:"[^"]*"|[\w.]+)\[\d+[^\]]*\]:/) ->
            {:object, nil}

          # Normal key-value pair
          String.match?(content, ~r/^(?:"(?:[^"\\]|\\.)*"|[\w.-]+)(?:\[[^\]]*\])?:(?:\s|$)/) ->
            {:object, nil}

          true ->
            {:root_primitive, nil}
        end

      # Multiple lines -> object
      true ->
        {:object, nil}
    end
  end

  # Parse root primitive value (single value without key)

  defp parse_root_primitive([%{content: content}], _opts, metadata) do
    unless valid_primitive?(content) do
      raise DecodeError,
        message: "Invalid TOON value: #{inspect(content)}",
        input: content
    end

    {parse_value(content), metadata}
  end

  defp valid_primitive?(content) do
    # Performance: Binary/String checks instead of regex for primitive validation
    # Original: content in ~w(null true false) or
    #           String.starts_with?(content, "\"") or
    #           String.match?(content, ~r/^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$/) or
    #           not String.match?(content, ~r/[:,\n\r]/)
    # Unquoted string: valid if it doesn't contain :, ,, \n, or \r
    content in ~w(null true false) or
      String.starts_with?(content, "\"") or
      do_valid_number_format?(content) or
      not do_contains_colon_comma_newline?(content)
  end

  # Performance: Binary scan for forbidden characters in unquoted strings
  # Checks for: : , \n \r
  defp do_contains_colon_comma_newline?(<<>>), do: false
  defp do_contains_colon_comma_newline?(<<?:, _rest::binary>>), do: true
  defp do_contains_colon_comma_newline?(<<?,, _rest::binary>>), do: true
  defp do_contains_colon_comma_newline?(<<?\n, _rest::binary>>), do: true
  defp do_contains_colon_comma_newline?(<<?\r, _rest::binary>>), do: true

  defp do_contains_colon_comma_newline?(<<_byte, rest::binary>>),
    do: do_contains_colon_comma_newline?(rest)

  # Performance: Binary character range checks instead of regex for number format validation
  # Matches: ^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$
  defp do_valid_number_format?(<<>>), do: false
  defp do_valid_number_format?(<<?-, rest::binary>>), do: do_valid_number_digits?(rest)

  defp do_valid_number_format?(<<c, rest::binary>>) when c in ?0..?9,
    do: do_valid_number_digits?(<<c, rest::binary>>)

  defp do_valid_number_format?(_), do: false

  defp do_valid_number_digits?(<<>>), do: true

  defp do_valid_number_digits?(<<c, rest::binary>>) when c in ?0..?9,
    do: do_valid_number_digits?(rest)

  defp do_valid_number_digits?(<<?., rest::binary>>), do: do_valid_number_frac?(rest)

  defp do_valid_number_digits?(<<c, rest::binary>>) when c == ?e or c == ?E,
    do: do_valid_number_exp_sign?(rest)

  defp do_valid_number_digits?(_), do: false

  defp do_valid_number_frac?(<<>>), do: true

  defp do_valid_number_frac?(<<c, rest::binary>>) when c in ?0..?9,
    do: do_valid_number_frac?(rest)

  defp do_valid_number_frac?(<<c, rest::binary>>) when c == ?e or c == ?E,
    do: do_valid_number_exp_sign?(rest)

  defp do_valid_number_frac?(_), do: false

  defp do_valid_number_exp_sign?(<<>>), do: false

  defp do_valid_number_exp_sign?(<<c, rest::binary>>) when c == ?+ or c == ?-,
    do: do_valid_number_exp_digits?(rest)

  defp do_valid_number_exp_sign?(<<c, rest::binary>>) when c in ?0..?9,
    do: do_valid_number_exp_digits?(<<c, rest::binary>>)

  defp do_valid_number_exp_sign?(_), do: false

  defp do_valid_number_exp_digits?(<<>>), do: true

  defp do_valid_number_exp_digits?(<<c, rest::binary>>) when c in ?0..?9,
    do: do_valid_number_exp_digits?(rest)

  defp do_valid_number_exp_digits?(_), do: false

  # Parse root-level array
  defp parse_root_array([%{content: header_line} = line_info | rest], opts, metadata) do
    case Parser.parse_line(header_line) do
      {:ok, [result], "", _, _, _} ->
        # Handle inline array
        case result do
          {key, value} when is_list(value) ->
            # Track metadata from parsed key-value
            was_quoted = key_was_quoted?(header_line)
            updated_metadata = add_key_to_metadata(key, was_quoted, metadata)
            {value, updated_metadata}

          _ ->
            raise DecodeError, message: "Invalid root array format", input: header_line
        end

      {:error, _reason, _, _, _, _} ->
        # Try parsing as tabular or list format
        parse_complex_root_array(line_info, rest, opts, metadata)
    end
  end

  defp parse_complex_root_array(%{content: header}, rest, opts, metadata) do
    cond do
      # Inline array with delimiter marker: [3\t]: ... or [3|]: ... or [3]: ...
      String.starts_with?(header, "[") and String.contains?(header, "]: ") ->
        {parse_root_inline_array(header, opts), metadata}

      # Tabular array: [N]{fields}:
      String.starts_with?(header, "[") and String.contains?(header, "]{") and
          String.ends_with?(header, "}:") ->
        {parse_tabular_array_data(header, rest, 0, opts), metadata}

      # List array: [N]:
      String.starts_with?(header, "[") and String.ends_with?(header, "]:") ->
        {parse_list_array_items(rest, 0, opts), metadata}

      true ->
        raise DecodeError, message: "Invalid root array header", input: header
    end
  end

  # Parse root inline array from header line
  defp parse_root_inline_array(header, opts) do
    # Extract everything after ": "
    case String.split(header, ": ", parts: 2) do
      [array_marker, values_str] ->
        # Extract declared length from [N]
        declared_length =
          case Regex.run(@array_length_regex, array_marker) do
            [_, length_str] -> String.to_integer(length_str)
            _ -> nil
          end

        delimiter = extract_delimiter(array_marker)
        values = parse_delimited_values(values_str, delimiter)

        # Validate length if declared (strict mode only per TOON spec Section 14.1)
        if Map.get(opts, :strict, true) && declared_length && length(values) != declared_length do
          raise DecodeError,
            message: "Array length mismatch: declared #{declared_length}, got #{length(values)}",
            input: header
        end

        values

      _ ->
        raise DecodeError, message: "Invalid root inline array", input: header
    end
  end

  # Helper function to build map with appropriate key type
  # Performance: Use :maps.from_list/1 for string keys (faster C implementation than Map.new/1)
  defp build_map_with_keys(entries, opts) do
    case opts.keys do
      :strings -> :maps.from_list(entries)
      :atoms -> Map.new(entries, fn {k, v} -> {String.to_atom(k), v} end)
      :atoms! -> Map.new(entries, fn {k, v} -> {String.to_existing_atom(k), v} end)
    end
  end

  # Performance: Build map directly from parallel field/value lists without intermediate zip
  defp build_map_from_fields_and_values(fields, values, opts) do
    case opts.keys do
      :strings ->
        :maps.from_list(:lists.zip(fields, values))

      :atoms ->
        :maps.from_list(
          :lists.zipwith(
            fn k, v -> {String.to_atom(k), v} end,
            fields,
            values
          )
        )

      :atoms! ->
        :maps.from_list(
          :lists.zipwith(
            fn k, v -> {String.to_existing_atom(k), v} end,
            fields,
            values
          )
        )
    end
  end

  defp put_key(map, key, value, opts) do
    case opts.keys do
      :strings -> Map.put(map, key, value)
      :atoms -> Map.put(map, String.to_atom(key), value)
      :atoms! -> Map.put(map, String.to_existing_atom(key), value)
    end
  end

  defp empty_map(_opts), do: %{}

  # Parse object from lines
  defp parse_object_lines(lines, base_indent, opts, metadata) do
    {entries, _remaining, updated_metadata} = parse_entries(lines, base_indent, opts, metadata)

    {build_map_with_keys(entries, opts), updated_metadata}
  end

  # Parse entries at a specific indentation level
  defp parse_entries([], _base_indent, _opts, metadata), do: {[], [], metadata}

  defp parse_entries([line | rest] = lines, base_indent, opts, metadata) do
    cond do
      # Skip blank lines (only at root level or when not strict)
      line.is_blank ->
        # When strict, blank lines in nested content should be rejected by take_nested_lines
        parse_entries(rest, base_indent, opts, metadata)

      # Skip lines that are less indented (parent level)
      line.indent < base_indent ->
        {[], lines, metadata}

      # Lines more indented than expected - in strict mode this is an error
      line.indent > base_indent ->
        if opts.strict do
          raise DecodeError,
            message: "Over-indented line: expected indent #{base_indent}, got #{line.indent}",
            input: line.original
        else
          {[], lines, metadata}
        end

      # Process line at current level
      true ->
        case parse_entry_line(line, rest, base_indent, opts, metadata) do
          {:entry, key, value, remaining, updated_metadata} ->
            {entries, final_remaining, final_metadata} =
              parse_entries(remaining, base_indent, opts, updated_metadata)

            {[{key, value} | entries], final_remaining, final_metadata}

          {:skip, remaining, updated_metadata} ->
            parse_entries(remaining, base_indent, opts, updated_metadata)
        end
    end
  end

  # Parse a single entry line
  defp parse_entry_line(%{content: content} = line_info, rest, base_indent, opts, metadata) do
    # Track if key was quoted by checking if line starts with quote
    was_quoted = key_was_quoted?(content)

    case Parser.parse_line(content) do
      {:ok, [result], "", _, _, _} ->
        case result do
          {key, value} when is_list(value) ->
            updated_meta = add_key_to_metadata(key, was_quoted, metadata)

            # Check if this is an empty array with nested content (list or tabular format)
            # Pattern like items[3]: with indented lines following
            if value == [] and peek_next_indent(rest) > base_indent do
              # This is a list/tabular array header, not an inline array
              # Fall through to special line handling
              case handle_special_line(line_info, rest, base_indent, opts, updated_meta) do
                {:skip, _, updated_meta2} ->
                  # If special line handling doesn't work, treat as empty array
                  {:entry, key, [], rest, updated_meta2}

                result ->
                  result
              end
            else
              # Inline array - ALWAYS re-parse to respect leading zeros and other edge cases
              # The Parser module may have already parsed numbers incorrectly
              # Extract array marker from content to get delimiter
              corrected_value =
                case Regex.run(@array_header_with_colon_regex, content) do
                  [_, array_marker, length_str] ->
                    declared_length = String.to_integer(length_str)
                    delimiter = extract_delimiter(array_marker)
                    # Re-parse the values with correct delimiter
                    case String.split(content, ": ", parts: 2) do
                      [_, values_str] ->
                        values = parse_delimited_values(values_str, delimiter)

                        # Validate length (strict mode only per TOON spec Section 14.1)
                        if Map.get(opts, :strict, true) && length(values) != declared_length do
                          raise DecodeError,
                            message:
                              "Array length mismatch: declared #{declared_length}, got #{length(values)}",
                            input: content
                        end

                        values

                      _ ->
                        value
                    end

                  _ ->
                    value
                end

              {:entry, key, corrected_value, rest, updated_meta}
            end

          {key, value} ->
            updated_meta = add_key_to_metadata(key, was_quoted, metadata)

            # Check if value is a primitive (not a container that can have nested content)
            # Primitives: string, number, boolean, nil, atom
            # Containers: map, list
            is_primitive = not (is_map(value) or is_list(value))

            case peek_next_indent(rest) do
              indent when indent > base_indent ->
                if is_primitive and opts.strict do
                  # Primitive value cannot have nested content - over-indented line
                  raise DecodeError,
                    message:
                      "Over-indented line after primitive field: primitive fields cannot have nested content",
                    input: Enum.at(rest, 0).original
                else
                  {nested_value, nested_meta} =
                    parse_nested_value(key, rest, base_indent, opts, updated_meta)

                  {remaining_lines, _} = skip_nested_lines(rest, base_indent)

                  {:entry, key, nested_value, remaining_lines, nested_meta}
                end

              _ ->
                # FIX 1: When the raw value string is empty (e.g. "key: "), preserve
                # the Parser's result (%{} from empty_kv) instead of calling
                # parse_value(""), which would incorrectly return "".
                corrected_value =
                  case String.split(content, ": ", parts: 2) do
                    [_, value_str] ->
                      trimmed_str = String.trim(value_str)
                      if trimmed_str == "", do: value, else: parse_value(trimmed_str)

                    _ ->
                      value
                  end

                {:entry, key, corrected_value, rest, updated_meta}
            end
        end

      {:ok, [parsed_result], rest_content, _, _, _} when rest_content != "" ->
        case parsed_result do
          {key, _partial_value} ->
            updated_meta = add_key_to_metadata(key, was_quoted, metadata)

            case String.split(content, ": ", parts: 2) do
              [array_header, values_str] ->
                # Re-parse as array if header contains [N]
                case Regex.run(@array_header_with_values_regex, array_header) do
                  [_, length_str, delimiter_marker] ->
                    declared_length = String.to_integer(length_str)
                    delimiter = extract_delimiter("[#{delimiter_marker}]")
                    values = parse_delimited_values(values_str, delimiter)

                    # Validate length (strict mode only per TOON spec Section 14.1)
                    if Map.get(opts, :strict, true) && length(values) != declared_length do
                      raise DecodeError,
                        message:
                          "Array length mismatch: declared #{declared_length}, got #{length(values)}",
                        input: content
                    end

                    {:entry, key, values, rest, updated_meta}

                  nil ->
                    # Not an array line — original scalar fallback
                    full_value = parse_value(String.trim(values_str))
                    {:entry, key, full_value, rest, updated_meta}
                end

              _ ->
                {:skip, rest, metadata}
            end

          _ ->
            {:skip, rest, metadata}
        end

      {:ok, _, _, _, _, _} ->
        # Unexpected parse result
        {:skip, rest, metadata}

      {:error, reason, _, _, _, _} ->
        # Try to handle special cases like array headers
        # If it still fails, raise an error
        case handle_special_line(line_info, rest, base_indent, opts, metadata) do
          {:skip, _, _meta} ->
            raise DecodeError,
              message: "Failed to parse line: #{reason}",
              input: content

          result ->
            result
        end
    end
  end

  # Pattern matching helpers for handle_special_line
  defp tabular_array_header?(content), do: String.match?(content, @tabular_header_pattern)
  defp list_array_header?(content), do: String.match?(content, @list_header_pattern)

  defp line_kind(content) do
    cond do
      String.match?(content, @tabular_header_pattern) ->
        :tabular_array

      String.match?(content, @list_header_pattern) ->
        :list_array

      String.ends_with?(content, @colon) and
          not String.contains?(content, @space) ->
        :nested_object

      true ->
        :unknown
    end
  end

  # Handle special line formats (array headers, etc.)
  defp handle_special_line(%{content: content} = line_info, rest, base_indent, opts, meta) do
    case line_kind(content) do
      :tabular_array -> parse_tabular_array_entry(line_info, rest, base_indent, opts, meta)
      :list_array -> parse_list_array_entry(line_info, rest, base_indent, opts, meta)
      :nested_object -> parse_nested_object_entry(content, rest, base_indent, opts, meta)
      :unknown -> {:skip, rest, meta}
    end
  end

  defp parse_tabular_array_entry(line_info, rest, base_indent, opts, metadata) do
    {{key, array_value}, updated_meta} =
      parse_tabular_array(line_info, rest, base_indent, opts, metadata)

    {remaining, _} = skip_nested_lines(rest, base_indent)
    {:entry, key, array_value, remaining, updated_meta}
  end

  defp parse_list_array_entry(line_info, rest, base_indent, opts, metadata) do
    {{key, array_value}, updated_meta} =
      parse_list_array(line_info, rest, base_indent, opts, metadata)

    {remaining, _} = skip_nested_lines(rest, base_indent)
    {:entry, key, array_value, remaining, updated_meta}
  end

  defp parse_nested_object_entry(content, rest, base_indent, opts, metadata) do
    key = content |> String.trim_trailing(":") |> unquote_key()
    was_quoted = key_was_quoted?(content)
    updated_meta = add_key_to_metadata(key, was_quoted, metadata)

    case peek_next_indent(rest) do
      indent when indent > base_indent ->
        # In strict mode, validate that nested content is indented by a positive
        # multiple of indent_size relative to base_indent.
        # This allows both single-level (base_indent + indent_size) and double-level
        # (base_indent + 2 * indent_size) indentation for nested objects inside list items.
        if opts.strict do
          depth_diff = indent - base_indent

          if depth_diff <= 0 or rem(depth_diff, opts.indent_size) != 0 do
            raise DecodeError,
              message:
                "Indentation jump: expected indent #{base_indent + opts.indent_size}, got #{indent}",
              input: hd(rest).original
          end
        end

        {nested_value, nested_meta} = parse_nested_object(rest, base_indent, opts, updated_meta)
        {remaining, _} = skip_nested_lines(rest, base_indent)
        {:entry, key, nested_value, remaining, nested_meta}

      _ ->
        {:entry, key, %{}, rest, updated_meta}
    end
  end

  # Parse nested value (object or array)
  defp parse_nested_value(_key, lines, base_indent, opts, metadata) do
    nested_lines = take_nested_lines(lines, base_indent)

    # Use the actual indent of the first nested line, not base_indent + indent_size
    # This allows non-multiple indentation when strict=false
    actual_indent = get_first_content_indent(nested_lines)

    # In strict mode, validate that nested content is indented by a positive
    # multiple of indent_size relative to base_indent.
    # This allows both single-level (base_indent + indent_size) and double-level
    # (base_indent + 2 * indent_size) indentation for nested objects inside list items.
    if opts.strict do
      depth_diff = actual_indent - base_indent

      if depth_diff <= 0 or rem(depth_diff, opts.indent_size) != 0 do
        raise DecodeError,
          message:
            "Depth jump: nested content must be indented by a multiple of #{opts.indent_size} spaces (got #{actual_indent}, expected #{base_indent + opts.indent_size})",
          input: Enum.at(nested_lines, 0) |> Map.get(:original, "")
      end
    end

    parse_object_lines(nested_lines, actual_indent, opts, metadata)
  end

  # Parse nested object
  defp parse_nested_object(lines, base_indent, opts, metadata) do
    nested_lines = take_nested_lines(lines, base_indent)
    # Use the actual indent of the first nested line, not base_indent + indent_size
    actual_indent = get_first_content_indent(nested_lines)

    # In strict mode, validate that nested content is indented by a positive
    # multiple of indent_size relative to base_indent.
    # This allows both single-level (base_indent + indent_size) and double-level
    # (base_indent + 2 * indent_size) indentation for nested objects inside list items.
    if opts.strict do
      depth_diff = actual_indent - base_indent

      if depth_diff <= 0 or rem(depth_diff, opts.indent_size) != 0 do
        raise DecodeError,
          message:
            "Depth jump: nested content must be indented by a multiple of #{opts.indent_size} spaces (got #{actual_indent}, expected #{base_indent + opts.indent_size})",
          input: Enum.at(nested_lines, 0) |> Map.get(:original, "")
      end
    end

    parse_object_lines(nested_lines, actual_indent, opts, metadata)
  end

  # Parse tabular array
  defp parse_tabular_array(%{content: header}, rest, base_indent, opts, metadata) do
    case Regex.run(@tabular_array_header_regex, header) do
      [_, raw_key, array_marker, fields_str] ->
        key = unquote_key(raw_key)
        was_quoted = key_was_quoted?(header)
        updated_meta = add_key_to_metadata(key, was_quoted, metadata)

        delimiter = extract_delimiter(array_marker)
        fields = parse_fields(fields_str, delimiter)

        # Extract declared length from array_marker
        declared_length =
          case Regex.run(@array_length_regex, array_marker) do
            [_, len_str] -> String.to_integer(len_str)
            nil -> nil
          end

        data_rows = take_nested_lines(rest, base_indent)

        # In strict mode, filter rows to only include those at exactly one level deeper
        # and validate that first row is exactly one level deeper
        filtered_data_rows =
          if opts.strict and data_rows != [] do
            expected_row_indent = base_indent + opts.indent_size
            first_row_indent = get_first_content_indent(data_rows)

            if first_row_indent != expected_row_indent do
              raise DecodeError,
                message:
                  "Depth jump: tabular rows must be indented by exactly #{opts.indent_size} spaces (got #{first_row_indent}, expected #{expected_row_indent})",
                input: Enum.at(data_rows, 0).original
            end

            # Check for over-indented lines in strict mode
            over_indented =
              Enum.find(data_rows, fn line ->
                not line.is_blank and line.indent > expected_row_indent
              end)

            if over_indented do
              raise DecodeError,
                message:
                  "Over-indented line after tabular rows: tabular rows cannot have nested content",
                input: over_indented.original
            end

            # Filter rows to only include those at the expected indent level
            Enum.filter(data_rows, fn line ->
              line.indent == expected_row_indent or line.is_blank
            end)
          else
            # In non-strict mode, include all nested lines
            data_rows
          end

        # Validate row count when a length was declared (always the case in TOON)
        if declared_length != nil and length(filtered_data_rows) != declared_length do
          raise DecodeError,
            message:
              "Tabular array row count mismatch: declared #{declared_length}, got #{length(filtered_data_rows)}",
            input: header
        end

        array_data = parse_tabular_data_rows(filtered_data_rows, fields, delimiter, opts)
        {{key, array_data}, updated_meta}

      nil ->
        raise DecodeError, message: "Invalid tabular array header", input: header
    end
  end

  # Parse tabular array data rows
  # Performance: Single-pass processing - filter blanks and parse in one traversal
  defp parse_tabular_data_rows(lines, fields, delimiter, opts) do
    field_count = length(fields)

    expected_indent =
      if lines != [] do
        get_first_content_indent(lines)
      else
        0
      end

    Enum.reduce(lines, [], fn line, acc ->
      if line.is_blank do
        if opts.strict do
          raise DecodeError,
            message: "Blank lines are not allowed inside arrays in strict mode",
            input: line.original
        end

        acc
      else
        # In strict mode, validate all rows have the same indent
        if opts.strict and line.indent != expected_indent do
          raise DecodeError,
            message:
              "Inconsistent row indentation: expected #{expected_indent}, got #{line.indent}",
            input: line.original
        end

        values = parse_delimited_values(line.content, delimiter)

        if length(values) != field_count do
          raise DecodeError,
            message: "Row value count mismatch: expected #{field_count}, got #{length(values)}",
            input: line.content
        end

        # Build map directly from zipped fields and values
        row_map = build_map_from_fields_and_values(fields, values, opts)
        [row_map | acc]
      end
    end)
    |> :lists.reverse()
  end

  # Parse tabular array data (for root arrays)
  defp parse_tabular_array_data(header, rest, base_indent, opts) do
    case Regex.run(@root_tabular_array_regex, header) do
      [_, _full_length, length_str, delimiter_marker, fields_str] ->
        declared_length = String.to_integer(length_str)
        delimiter = extract_delimiter("[#{delimiter_marker}]")
        fields = parse_fields(fields_str, delimiter)
        data_rows = take_nested_lines(rest, base_indent)

        # Validate row count
        if length(data_rows) != declared_length do
          raise DecodeError,
            message:
              "Tabular array row count mismatch: declared #{declared_length}, got #{length(data_rows)}",
            input: header
        end

        parse_tabular_data_rows(data_rows, fields, delimiter, opts)

      nil ->
        raise DecodeError, message: "Invalid tabular array header", input: header
    end
  end

  # Parse list array
  defp parse_list_array(%{content: header}, rest, base_indent, opts, metadata) do
    case Regex.run(@list_array_header_regex, header) do
      [_, raw_key, array_marker] ->
        length_str =
          case Regex.run(@array_length_regex, array_marker) do
            [_, len] -> len
            nil -> "0"
          end

        declared_length = String.to_integer(length_str)
        key = unquote_key(raw_key)
        was_quoted = key_was_quoted?(header)
        updated_meta = add_key_to_metadata(key, was_quoted, metadata)

        # Extract delimiter from array marker and pass through opts
        delimiter = extract_delimiter(array_marker)
        opts_with_delimiter = Map.put(opts, :delimiter, delimiter)

        items = parse_list_array_items(rest, base_indent, opts_with_delimiter)

        # Validate length
        # Validate item count (strict mode only per TOON spec Section 14.1)
        if Map.get(opts, :strict, true) && length(items) != declared_length do
          raise DecodeError,
            message: "Array length mismatch: declared #{declared_length}, got #{length(items)}",
            input: header
        end

        {{key, items}, updated_meta}

      nil ->
        raise DecodeError, message: "Invalid list array header", input: header
    end
  end

  # Parse list array items
  defp parse_list_array_items(lines, base_indent, opts) do
    list_lines = take_nested_lines(lines, base_indent)
    # Use the actual indent of the first list item, not base_indent + indent_size
    actual_indent = get_first_content_indent(list_lines)

    # In strict mode, validate that list items are exactly one level deeper
    if opts.strict and actual_indent != base_indent + opts.indent_size do
      raise DecodeError,
        message:
          "Depth jump: list items must be indented by exactly #{opts.indent_size} spaces (got #{actual_indent}, expected #{base_indent + opts.indent_size})",
        input: Enum.at(list_lines, 0) |> Map.get(:original, "")
    end

    parse_list_items(list_lines, actual_indent, opts, [])
  end

  # Parse individual list items
  defp parse_list_items([], _expected_indent, _opts, acc), do: Enum.reverse(acc)

  defp parse_list_items([line | rest], expected_indent, opts, acc) do
    cond do
      # Skip blank lines (validate in strict mode if within array content)
      line.is_blank ->
        if opts.strict do
          raise DecodeError,
            message: "Blank lines are not allowed inside arrays in strict mode",
            input: line.original
        else
          parse_list_items(rest, expected_indent, opts, acc)
        end

      # In strict mode, validate all list items have the expected indent
      opts.strict and line.indent != expected_indent ->
        raise DecodeError,
          message:
            "Inconsistent list item indentation: expected #{expected_indent}, got #{line.indent}",
          input: line.original

      # Inline array item with values on same line: - [N]: val1,val2
      # (must have content after ": ", otherwise it's a list-format array header)
      String.contains?(line.content, "]: ") and
          String.starts_with?(String.trim_leading(line.content), "- [") ->
        {item, remaining} = parse_inline_array_item(line, rest, expected_indent, opts)
        parse_list_items(remaining, expected_indent, opts, [item | acc])

      # List item marker (with space "- " or just "-")
      String.starts_with?(String.trim_leading(line.content), "-") ->
        {item, remaining} = parse_list_item(line, rest, expected_indent, opts)
        parse_list_items(remaining, expected_indent, opts, [item | acc])

      true ->
        parse_list_items(rest, expected_indent, opts, acc)
    end
  end

  # Pattern matching helpers for list item parsing
  defp remove_list_marker(content) do
    content
    |> String.trim_leading()
    |> String.replace_prefix("- ", "")
    |> String.replace_prefix("-", "")
  end

  defp inline_array_with_values?(str), do: String.match?(str, @inline_array_pattern)
  defp list_array_header_only?(str), do: String.match?(str, @list_array_header_pattern)

  # Parse a single list item
  defp parse_list_item(%{content: content} = line, rest, expected_indent, opts) do
    trimmed = remove_list_marker(content)
    route_list_item(trimmed, rest, line, expected_indent, opts)
  end

  defp route_list_item("", rest, _line, _expected_indent, _opts), do: {%{}, rest}

  defp route_list_item(trimmed, rest, line, expected_indent, opts) do
    cond do
      String.trim(trimmed) == "" ->
        {%{}, rest}

      inline_array_with_values?(trimmed) ->
        parse_inline_array_from_line(trimmed, rest)

      list_array_header_only?(trimmed) ->
        parse_nested_list_array(trimmed, rest, line, expected_indent, opts)

      tabular_array_header?(trimmed) ->
        parse_list_item_with_array(trimmed, rest, line, expected_indent, opts, :tabular)

      list_array_header?(trimmed) ->
        parse_list_item_with_array(trimmed, rest, line, expected_indent, opts, :list)

      true ->
        parse_list_item_normal(trimmed, rest, line, expected_indent, opts)
    end
  end

  defp parse_list_item_normal(trimmed, rest, line, expected_indent, opts) do
    delimiter = Map.get(opts, :delimiter, ",")

    result = Parser.parse_line(trimmed)

    case result do
      {:ok, [result], "", _, _, _} ->
        handle_complete_parse(result, trimmed, rest, line, expected_indent, opts)

      {:ok, [{key, partial_value}], remaining_input, _, _, _}
      when is_binary(remaining_input) and remaining_input != "" ->
        handle_partial_parse(
          key,
          partial_value,
          remaining_input,
          delimiter,
          trimmed,
          rest,
          line,
          expected_indent,
          opts
        )

      {:error, _, _, _, _, _} ->
        handle_parse_error(trimmed, rest, expected_indent, opts)
    end
  end

  defp handle_partial_parse(
         key,
         partial_value,
         remaining_input,
         delimiter,
         trimmed,
         rest,
         line,
         expected_indent,
         opts
       ) do
    if delimiter != "," and String.starts_with?(remaining_input, ",") do
      full_value = parse_value(to_string(partial_value) <> remaining_input)

      continuation_lines = take_item_lines(rest, expected_indent)

      item_indent =
        if continuation_lines != [],
          do: continuation_lines |> Enum.map(& &1.indent) |> Enum.min(),
          else: line.indent

      adjusted_content = "#{key}: #{full_value}"
      item_lines = [%{line | content: adjusted_content, indent: item_indent} | continuation_lines]
      empty_metadata = %{quoted_keys: MapSet.new(), key_order: []}
      {object, _} = parse_object_lines(item_lines, item_indent, opts, empty_metadata)
      remaining = Enum.drop(rest, length(continuation_lines))
      {object, remaining}
    else
      handle_complete_parse({key, partial_value}, trimmed, rest, line, expected_indent, opts)
    end
  end

  # handle_complete_parse/6
  #
  # Builds a map object from a parsed list-item result plus its continuation lines.
  #
  # Design: use line.indent as the base for parse_object_lines so that standard
  # TOON indentation-based nesting works correctly inside list items.
  #
  #   - args:           ← line.indent = 2
  #     device_id: val  ← continuation at indent 4
  #
  # With base = line.indent = 2: peek_next_indent = 4 > 2 → nesting triggered
  # → %{"args" => %{"device_id" => val}} ✓
  #
  # For non-empty valued first fields (e.g. "budget: 500 USD"), the
  # continuation lines are siblings.  We normalise all of them (including the
  # first line) to cont_indent so they share one base level and none triggers
  # spurious nesting via peek_next_indent.

  defp handle_complete_parse(result, trimmed, rest, line, expected_indent, opts) do
    case result do
      {_key, value} ->
        continuation_lines = take_item_lines(rest, expected_indent)

        {item_lines, item_indent} =
          if empty_list_item_value?(value) and continuation_lines != [] do
            cont_indent = continuation_lines |> Enum.map(& &1.indent) |> Enum.min()
            # Length of the list marker that was stripped from line.content
            # ("- " → 2, "-" → 1).  trimmed = remove_list_marker(line.content).
            marker_len = byte_size(line.content) - byte_size(trimmed)
            sibling_indent = line.indent + marker_len

            if cont_indent > sibling_indent do
              # Continuation lines are CHILDREN of this key (deeper than sibling
              # level).  Preserve line.indent so peek_next_indent detects nesting.
              {[%{line | content: trimmed} | continuation_lines], line.indent}
            else
              # Continuation lines are SIBLINGS (same logical indent as this key).
              # Normalise first-line indent to cont_indent so all fields share
              # the same base level in parse_object_lines.
              {[%{line | content: trimmed, indent: cont_indent} | continuation_lines],
               cont_indent}
            end
          else
            # Normal (non-empty) value: all continuation lines are siblings.
            cont_indent =
              if continuation_lines == [],
                do: line.indent,
                else: continuation_lines |> Enum.map(& &1.indent) |> Enum.min()

            {[%{line | content: trimmed, indent: cont_indent} | continuation_lines], cont_indent}
          end

        empty_metadata = %{quoted_keys: MapSet.new(), key_order: []}
        {object, _} = parse_object_lines(item_lines, item_indent, opts, empty_metadata)
        remaining = Enum.drop(rest, length(continuation_lines))
        {object, remaining}

      value ->
        {value, rest}
    end
  end

  # Only %{} (the empty_kv placeholder) represents "no value supplied".
  # nil (null literal) and "" (explicit quoted empty string) are real values
  # and must NOT trigger the children/sibling disambiguation path.
  defp empty_list_item_value?(%{} = m) when map_size(m) == 0, do: true
  defp empty_list_item_value?(_), do: false

  defp handle_parse_error(trimmed, rest, expected_indent, opts) do
    if String.ends_with?(trimmed, ":") and not String.contains?(trimmed, " ") do
      next_indent = peek_next_indent(rest)

      if next_indent > expected_indent do
        parse_nested_key_with_content(trimmed, rest, next_indent, expected_indent, opts)
      else
        {parse_value(trimmed), rest}
      end
    else
      # Strip trailing delimiter comma — it is separator noise, not value data.
      value_str = String.trim_trailing(trimmed, ",")
      {parse_value(value_str), rest}
    end
  end

  # Helper to drop lines at a certain level
  defp drop_lines_at_level(lines, min_indent) do
    Enum.drop_while(lines, fn line -> !line.is_blank and line.indent >= min_indent end)
  end

  # Helper to build object with nested value
  defp build_object_with_nested(key, nested_value, [], opts) do
    put_key(empty_map(opts), key, nested_value, opts)
  end

  defp build_object_with_nested(key, nested_value, more_fields, opts) do
    field_indent = more_fields |> Enum.map(& &1.indent) |> Enum.min()
    empty_metadata = %{quoted_keys: MapSet.new(), key_order: []}
    {remaining_object, _} = parse_object_lines(more_fields, field_indent, opts, empty_metadata)
    put_key(remaining_object, key, nested_value, opts)
  end

  # Parse a key with nested content
  defp parse_nested_key_with_content(trimmed, rest, next_indent, expected_indent, opts) do
    key = trimmed |> String.trim_trailing(":") |> unquote_key()

    # Take lines at the nested level
    nested_lines = take_lines_at_level(rest, next_indent)
    empty_metadata = %{quoted_keys: MapSet.new(), key_order: []}
    {nested_value, _} = parse_object_lines(nested_lines, next_indent, opts, empty_metadata)

    # Skip consumed nested lines
    remaining_after_nested = drop_lines_at_level(rest, next_indent)

    # Take remaining fields at the same level
    more_fields = take_item_lines(remaining_after_nested, expected_indent)

    object = build_object_with_nested(key, nested_value, more_fields, opts)

    final_remaining =
      if more_fields == [],
        do: remaining_after_nested,
        else: Enum.drop(remaining_after_nested, length(more_fields))

    {object, final_remaining}
  end

  # Helper to get nested indent for list arrays
  defp get_nested_indent([], expected_indent, opts),
    do: expected_indent + Map.get(opts, :indent_size, 2)

  defp get_nested_indent(lines, _expected_indent, _opts),
    do: lines |> Enum.map(& &1.indent) |> Enum.min()

  # Helper to parse remaining fields in list item
  defp parse_remaining_fields([], _opts), do: empty_map(nil)

  defp parse_remaining_fields(fields, opts) do
    field_indent = fields |> Enum.map(& &1.indent) |> Enum.min()
    empty_metadata = %{quoted_keys: MapSet.new(), key_order: []}
    {result, _} = parse_object_lines(fields, field_indent, opts, empty_metadata)
    result
  end

  # Parse array from tabular header
  defp parse_array_from_header(trimmed, rest, expected_indent, opts, :tabular) do
    case Regex.run(@tabular_header_regex, trimmed) do
      [_, raw_key, array_marker, fields_str] ->
        key = unquote_key(raw_key)
        delimiter = extract_delimiter(array_marker)
        fields = parse_fields(fields_str, delimiter)
        array_lines = take_array_data_lines(rest, expected_indent, opts)
        {key, parse_tabular_data_rows(array_lines, fields, delimiter, opts)}

      nil ->
        raise DecodeError, message: "Invalid tabular array in list item", input: trimmed
    end
  end

  # Parse array from list header
  defp parse_array_from_header(trimmed, rest, expected_indent, opts, :list) do
    case Regex.run(@list_array_regex, trimmed) do
      [_, raw_key, _length_str] ->
        key = unquote_key(raw_key)
        array_lines = take_array_data_lines(rest, expected_indent, opts)
        nested_indent = get_nested_indent(array_lines, expected_indent, opts)
        {key, parse_list_items(array_lines, nested_indent, opts, [])}

      nil ->
        raise DecodeError, message: "Invalid list array in list item", input: trimmed
    end
  end

  # Parse list item that starts with an array (tabular or list format)
  defp parse_list_item_with_array(trimmed, rest, _line, expected_indent, opts, array_type) do
    {key, array_value} = parse_array_from_header(trimmed, rest, expected_indent, opts, array_type)
    {rest_after_array, _} = skip_array_data_lines(rest, expected_indent)
    remaining_fields = take_item_lines(rest_after_array, expected_indent)

    remaining_object = parse_remaining_fields(remaining_fields, opts)
    object = put_key(remaining_object, key, array_value, opts)

    {remaining, _} = skip_item_lines(rest, expected_indent)
    {object, remaining}
  end

  # Take lines for array data (until we hit a non-array line at same level or higher)
  defp take_array_data_lines(lines, base_indent, opts) do
    # For tabular arrays: take lines at depth > base_indent that DON'T look like fields
    # For list arrays: take all lines > base_indent (list items and their nested content)

    # First, check if the first non-blank line starts with "-" (list array) or not (tabular)
    first_content = Enum.find(lines, fn line -> !line.is_blank end)

    is_list_array =
      case first_content do
        %{content: content} -> String.starts_with?(String.trim_leading(content), "-")
        nil -> false
      end

    if is_list_array do
      # For list arrays, we need to carefully track list items and their content
      # Find the expected indent of list items (should be base_indent + indent_size)
      list_item_indent =
        case first_content do
          %{indent: indent} -> indent
          nil -> base_indent + Map.get(opts, :indent_size, 2)
        end

      # Take all list items and their nested content
      # Stop at lines at list_item_indent level that don't start with "-"
      Enum.take_while(lines, fn line ->
        cond do
          line.is_blank ->
            true

          line.indent > list_item_indent ->
            # Nested content of list items
            true

          line.indent == list_item_indent ->
            # At list item level: only continue if it's a list marker
            String.starts_with?(String.trim_leading(line.content), "-")

          true ->
            false
        end
      end)
    else
      # Tabular array: take lines that don't look like fields
      Enum.take_while(lines, fn line ->
        cond do
          line.is_blank ->
            true

          line.indent > base_indent ->
            # Tabular array: take lines that don't look like "key: value"
            not String.match?(line.content, @field_pattern)

          true ->
            false
        end
      end)
    end
  end

  # Skip array data lines
  defp skip_array_data_lines(lines, base_indent) do
    # Use same logic as take_array_data_lines
    first_content = Enum.find(lines, fn line -> !line.is_blank end)

    is_list_array =
      case first_content do
        %{content: content} -> String.starts_with?(String.trim_leading(content), "-")
        nil -> false
      end

    remaining =
      if is_list_array do
        # Use same logic as take: find list item indent and skip accordingly
        list_item_indent =
          case first_content do
            %{indent: indent} -> indent
            nil -> base_indent + 2
          end

        Enum.drop_while(lines, fn line ->
          cond do
            line.is_blank ->
              true

            line.indent > list_item_indent ->
              true

            line.indent == list_item_indent ->
              String.starts_with?(String.trim_leading(line.content), "-")

            true ->
              false
          end
        end)
      else
        Enum.drop_while(lines, fn line ->
          cond do
            line.is_blank ->
              true

            line.indent > base_indent ->
              not String.match?(line.content, @field_pattern)

            true ->
              false
          end
        end)
      end

    {remaining, length(lines) - length(remaining)}
  end

  # Parse inline array from a line like "[2]: a,b"
  defp parse_inline_array_from_line(trimmed, rest) do
    # Extract: [N], [N|], [N\t] format
    case Regex.run(@inline_array_header_regex, trimmed) do
      [_, array_marker, values_str] ->
        delimiter = extract_delimiter(array_marker)

        values =
          if values_str == "" do
            []
          else
            parse_delimited_values(values_str, delimiter)
          end

        {values, rest}

      nil ->
        # Malformed, return as string
        {trimmed, rest}
    end
  end

  # Parse nested list-format array within a list item (e.g., "- [1]:" with nested items)
  defp parse_nested_list_array(_trimmed, rest, _line, expected_indent, opts) do
    array_lines = take_nested_lines(rest, expected_indent)

    if Enum.empty?(array_lines) do
      {[], rest}
    else
      nested_indent = get_first_content_indent(array_lines)
      array_items = parse_list_items(array_lines, nested_indent, opts, [])
      {rest_after_array, _} = skip_nested_lines(rest, expected_indent)

      {array_items, rest_after_array}
    end
  end

  # Parse inline array item in list
  defp parse_inline_array_item(%{content: content}, rest, _expected_indent, _opts) do
    trimmed = String.trim_leading(content) |> String.replace_prefix("- ", "")

    # Use parse_inline_array_from_line directly since it handles [N]: format
    parse_inline_array_from_line(trimmed, rest)
  end

  # Parse fields from tabular header - use active delimiter per TOON spec Section 6
  # Performance: Use simple String.split when no quotes present (common case for simple identifiers)
  defp parse_fields(fields_str, delimiter) do
    if String.contains?(fields_str, @double_quote) do
      # Quoted field names present - use full quote-aware splitting
      split_respecting_quotes(fields_str, delimiter)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&unquote_key/1)
    else
      # Simple identifiers - fast path with String.split
      String.split(fields_str, delimiter, trim: true)
      |> Enum.map(&String.trim/1)
    end
  end

  # Extract delimiter from array marker like [2], [2|], [2\t]
  # Performance: Binary pattern matching instead of String.contains?
  defp extract_delimiter(array_marker) do
    do_extract_delimiter(array_marker)
  end

  defp do_extract_delimiter(<<>>), do: @comma
  defp do_extract_delimiter(<<?|, _rest::binary>>), do: @pipe
  defp do_extract_delimiter(<<?\t, _rest::binary>>), do: @tab
  defp do_extract_delimiter(<<_byte, rest::binary>>), do: do_extract_delimiter(rest)

  # Parse delimited values from row
  # Performance: Trim during split instead of separate Enum.map pass
  defp parse_delimited_values(row_str, delimiter) do
    actual_delimiter = detect_delimiter(row_str, delimiter)
    split_and_parse_values(row_str, actual_delimiter)
  end

  # Performance: Split and parse in single pass, trimming during split
  defp split_and_parse_values(str, delimiter) do
    do_split_and_parse(str, delimiter, [], false, [])
  end

  defp do_split_and_parse("", _delimiter, current, _in_quote, acc) do
    current_str =
      current
      |> :lists.reverse()
      |> IO.iodata_to_binary()
      |> do_trim_leading()
      |> do_trim_trailing()

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
      |> do_trim_leading()
      |> do_trim_trailing()

    do_split_and_parse(rest, delimiter, [], false, [parse_value(current_str) | acc])
  end

  defp do_split_and_parse(<<char, rest::binary>>, delimiter, current, in_quote, acc) do
    do_split_and_parse(rest, delimiter, [<<char>> | current], in_quote, acc)
  end

  # Extract the auto-detect logic so both places that call it stay readable:
  # Performance: Single-pass binary scan instead of 2x String.contains?
  defp detect_delimiter(row_str, @comma) do
    if do_has_tab_no_comma?(row_str), do: @tab, else: @comma
  end

  defp detect_delimiter(_row_str, delimiter), do: delimiter

  # Single-pass binary scan: returns true if string contains tab but no comma
  defp do_has_tab_no_comma?(<<>>), do: false
  defp do_has_tab_no_comma?(<<?\t, _rest::binary>>), do: true
  defp do_has_tab_no_comma?(<<?,, _rest::binary>>), do: false
  defp do_has_tab_no_comma?(<<_byte, rest::binary>>), do: do_has_tab_no_comma?(rest)

  # Split a string by delimiter, but don't split inside quoted strings
  defp split_respecting_quotes(str, delimiter) do
    # Use a simple state machine approach with iolist building for O(n) performance
    do_split_respecting_quotes(str, delimiter, [], false, [])
  end

  defp do_split_respecting_quotes("", _delimiter, current, _in_quote, acc) do
    # Reverse current iolist and convert to string, then reverse acc
    current_str = current |> :lists.reverse() |> IO.iodata_to_binary()
    :lists.reverse([current_str | acc])
  end

  defp do_split_respecting_quotes(<<"\\", char, rest::binary>>, delimiter, current, in_quote, acc) do
    # Escaped character - keep both backslash and char as iolist
    do_split_respecting_quotes(rest, delimiter, [<<char>>, "\\" | current], in_quote, acc)
  end

  defp do_split_respecting_quotes(<<"\"", rest::binary>>, delimiter, current, in_quote, acc) do
    # Toggle quote state
    do_split_respecting_quotes(rest, delimiter, ["\"" | current], not in_quote, acc)
  end

  # NOTE: delimiter must be a single ASCII byte (`,`, `\t`, or `|`).
  # Do not extend to multi-byte delimiters without replacing the byte-level
  # pattern match below.
  defp do_split_respecting_quotes(<<char, rest::binary>>, delimiter, current, false, acc)
       when <<char>> == delimiter do
    # Delimiter outside quotes - split here, convert current iolist to string
    current_str = current |> Enum.reverse() |> IO.iodata_to_binary()
    do_split_respecting_quotes(rest, delimiter, [], false, [current_str | acc])
  end

  defp do_split_respecting_quotes(<<char, rest::binary>>, delimiter, current, in_quote, acc) do
    # Normal character - prepend to iolist
    do_split_respecting_quotes(rest, delimiter, [<<char>> | current], in_quote, acc)
  end

  # Parse a single value - optimized with fast-path for already-clean strings
  defp parse_value(str) do
    # Fast-path: most tabular values are already clean (no leading/trailing whitespace)
    # Check first and last byte before doing any trimming work
    size = byte_size(str)

    cond do
      size == 0 ->
        do_parse_value("")

      :binary.first(str) in [?\s, ?\t] or :binary.last(str) in [?\s, ?\t] ->
        # Whitespace detected - do full trim
        str
        |> do_trim_leading()
        |> do_trim_trailing()
        |> do_parse_value()

      true ->
        # Already clean - parse directly
        do_parse_value(str)
    end
  end

  # Fast-path binary trimming - avoids String.trim overhead
  defp do_trim_leading(<<?\s, rest::binary>>), do: do_trim_leading(rest)
  defp do_trim_leading(<<?\t, rest::binary>>), do: do_trim_leading(rest)
  defp do_trim_leading(str), do: str

  defp do_trim_trailing(str), do: String.trim_trailing(str)

  defp do_parse_value("null"), do: nil
  defp do_parse_value("true"), do: true
  defp do_parse_value("false"), do: false
  defp do_parse_value("\"" <> _ = str), do: unquote_string(str)
  defp do_parse_value(str), do: parse_number_or_string(str)

  # Parse number or return as string
  # Per TOON spec: numbers with leading zeros (except "0" itself) are treated as strings

  # "0" and "-0" are valid numbers (both return 0)
  defp parse_number_or_string("0"), do: 0
  defp parse_number_or_string("-0"), do: 0

  # Leading zeros make it a string (e.g., "05", "-007")
  defp parse_number_or_string(<<"0", d, _rest::binary>> = str) when d in ?0..?9, do: str
  defp parse_number_or_string(<<"-0", d, _rest::binary>> = str) when d in ?0..?9, do: str

  # Try to parse as number, fall back to string
  defp parse_number_or_string(str) do
    case Float.parse(str) do
      {num, ""} -> normalize_parsed_number(num, str)
      _ -> str
    end
  end

  # Convert parsed float to appropriate type based on original string format
  defp normalize_parsed_number(num, str) do
    if has_decimal_or_exponent?(str) do
      normalize_decimal_number(num)
    else
      String.to_integer(str)
    end
  end

  # Performance: Single-pass binary scan instead of 3x String.contains?
  defp has_decimal_or_exponent?(<<>>), do: false
  defp has_decimal_or_exponent?(<<?., _rest::binary>>), do: true
  defp has_decimal_or_exponent?(<<?e, _rest::binary>>), do: true
  defp has_decimal_or_exponent?(<<?E, _rest::binary>>), do: true
  defp has_decimal_or_exponent?(<<_byte, rest::binary>>), do: has_decimal_or_exponent?(rest)

  defp normalize_decimal_number(num) when num == trunc(num), do: trunc(num)
  defp normalize_decimal_number(num), do: num

  # Remove quotes from key
  defp unquote_key("\"" <> _ = key) do
    key |> String.slice(1..-2//1) |> unescape_string()
  end

  defp unquote_key(key), do: key

  # Check if a key was originally quoted in the source line
  defp key_was_quoted?(original_line) do
    trimmed = String.trim_leading(original_line)
    String.starts_with?(trimmed, "\"")
  end

  # Update metadata with a key, checking if it was quoted
  defp add_key_to_metadata(key, was_quoted, metadata) do
    updated =
      if was_quoted,
        do: %{metadata | quoted_keys: MapSet.put(metadata.quoted_keys, key)},
        else: metadata

    %{updated | key_order: [key | updated.key_order]}
  end

  # Remove quotes and unescape string
  defp unquote_string("\"" <> _ = str) do
    if properly_quoted?(str) do
      str |> String.slice(1..-2//1) |> unescape_string()
    else
      raise DecodeError, message: "Unterminated string", input: str
    end
  end

  defp unquote_string(str), do: str

  # Check if a quoted string is properly terminated
  # The string should start and end with " and the ending " should not be escaped
  defp properly_quoted?(str) when byte_size(str) < 2, do: false

  defp properly_quoted?("\"" <> _ = str) do
    String.ends_with?(str, "\"") and not escaped_quote_at_end?(str)
  end

  defp properly_quoted?(_), do: false

  # Check if the closing quote is escaped
  defp escaped_quote_at_end?(str) do
    # Count consecutive backslashes before the final quote
    # If odd number, the quote is escaped; if even, it's not
    str
    # Remove final quote
    |> String.slice(0..-2//1)
    |> String.reverse()
    |> String.to_charlist()
    |> Enum.take_while(&(&1 == ?\\))
    |> length()
    # Odd number means escaped
    |> rem(2) == 1
  end

  defp unescape_string(str), do: do_unescape(str, [])

  defp do_unescape(<<>>, acc),
    do: acc |> :lists.reverse() |> IO.iodata_to_binary()

  defp do_unescape(<<"\\", char, rest::binary>>, acc) do
    replacement =
      case char do
        ?\\ ->
          "\\"

        ?" ->
          "\""

        ?n ->
          "\n"

        ?r ->
          "\r"

        ?t ->
          "\t"

        _ ->
          raise DecodeError,
            message: "Invalid escape sequence: \\#{<<char>>}",
            input: <<?\\, char>>
      end

    do_unescape(rest, [replacement | acc])
  end

  # Lone trailing backslash (malformed input)
  defp do_unescape(<<"\\">>, _acc),
    do: raise(DecodeError, message: "Unterminated escape sequence", input: "\\")

  # NOTE: Matches one BYTE at a time.  Valid for all ASCII content and for the
  # non-ASCII bytes of multibyte UTF-8 sequences (their high bytes are all ≥ 0x80
  # and cannot equal any ASCII special character, so this is safe).
  defp do_unescape(<<byte, rest::binary>>, acc),
    do: do_unescape(rest, [<<byte>> | acc])

  # Peek at next line's indent (skip blank lines)
  defp peek_next_indent([]), do: 0
  defp peek_next_indent([%{is_blank: true} | rest]), do: peek_next_indent(rest)
  defp peek_next_indent([%{indent: indent} | _]), do: indent

  # Get the indent of the first non-blank line
  defp get_first_content_indent([]), do: 0
  defp get_first_content_indent([%{is_blank: true} | rest]), do: get_first_content_indent(rest)
  defp get_first_content_indent([%{indent: indent} | _]), do: indent

  # Take lines at or above a specific indent level (for nested content at exact level)
  defp take_lines_at_level(lines, min_indent) do
    Enum.take_while(lines, fn line ->
      line.is_blank or line.indent >= min_indent
    end)
  end

  # Take lines that are more indented than base
  defp take_nested_lines(lines, base_indent) do
    # We need to handle blank lines carefully:
    # - Blank lines BETWEEN nested content should be included
    # - Blank lines AFTER nested content should NOT be included
    # We'll use a helper that tracks whether we're still in nested content
    take_nested_lines_helper(lines, base_indent, false)
  end

  defp take_nested_lines_helper([], _base_indent, _seen_content), do: []

  defp take_nested_lines_helper([line | rest], base_indent, seen_content) do
    cond do
      # Non-blank line that's more indented: include it and continue
      !line.is_blank and line.indent > base_indent ->
        [line | take_nested_lines_helper(rest, base_indent, true)]

      # Non-blank line at base level or less: stop here
      !line.is_blank ->
        []

      # Blank line: only include if the next non-blank line is still nested
      line.is_blank ->
        next_content_indent = peek_next_indent(rest)

        if next_content_indent > base_indent do
          [line | take_nested_lines_helper(rest, base_indent, seen_content)]
        else
          # Next content is at base level or less, so stop here
          []
        end
    end
  end

  # Fixed – mirrors the logic of take_nested_lines_helper
  defp skip_nested_lines(lines, base_indent) do
    remaining = do_skip_nested(lines, base_indent)
    {remaining, length(lines) - length(remaining)}
  end

  defp do_skip_nested([], _base_indent), do: []

  defp do_skip_nested([line | rest] = all, base_indent) do
    cond do
      !line.is_blank and line.indent > base_indent ->
        do_skip_nested(rest, base_indent)

      !line.is_blank ->
        all

      line.is_blank ->
        if peek_next_indent(rest) > base_indent do
          do_skip_nested(rest, base_indent)
        else
          all
        end
    end
  end

  # Take lines for a list item (until next item marker at same level)
  defp take_item_lines(lines, base_indent) do
    Enum.take_while(lines, fn line ->
      # Take lines that are MORE indented than base (continuation lines)
      # Stop at next list item marker at the same level
      if line.indent == base_indent do
        not String.starts_with?(String.trim_leading(line.content), "- ")
      else
        line.indent > base_indent
      end
    end)
  end

  # Skip lines for a list item
  defp skip_item_lines(lines, base_indent) do
    remaining =
      Enum.drop_while(lines, fn line ->
        # Skip lines that are MORE indented than base (continuation lines)
        # Stop at next list item marker at the same level
        if line.indent == base_indent do
          not String.starts_with?(String.trim_leading(line.content), "- ")
        else
          line.indent > base_indent
        end
      end)

    {remaining, length(lines) - length(remaining)}
  end
end
