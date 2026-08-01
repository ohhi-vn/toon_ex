defmodule ToonEx.Encode.Objects do
  @moduledoc """
  Encoding of TOON objects (maps).
  """

  alias ToonEx.Constants
  alias ToonEx.Encode.{Arrays, Primitives, Strings, Writer}
  alias ToonEx.Utils

  # Performance: Inline hot functions to reduce function call overhead
  @compile {:inline,
            build_path_prefix: 2,
            valid_identifier_segment?: 1,
            flatten_depth_allows?: 2,
            collect_forbidden_fold_paths: 1}

  @doc """
  Encodes a map to TOON format.

  ## Examples

      iex> opts = %{indent: 2, delimiter: ",", length_marker: nil}
      iex> map = %{"name" => "Alice", "age" => 30}
      iex> ToonEx.Encode.Objects.encode(map, 0, opts)

  """
  @spec encode(map(), non_neg_integer(), map()) :: [iodata()]
  def encode(map, depth, opts) when is_map(map) do
    map
    |> do_encode_map(depth, opts)
    |> Writer.to_iodata()
  end

  def encode_to_lines(map, depth, opts) do
    map
    |> do_encode_map(depth, opts)
    |> Writer.to_lines()
  end

  # All the real work lives here; both encode/3 and encode_to_lines/3 delegate.
  defp do_encode_map(map, depth, opts) do
    writer = Writer.new(opts.indent)
    keys = get_ordered_keys(map, Map.get(opts, :key_order), [])

    opts =
      if depth == 0 and not Map.has_key?(opts, :forbidden_fold_paths) do
        Map.put(opts, :forbidden_fold_paths, collect_forbidden_fold_paths(keys))
      else
        opts
      end

    path_prefix = Map.get(opts, :current_path_prefix, "")

    Enum.reduce(keys, writer, fn key, acc ->
      encode_entry(acc, key, Map.get(map, key), depth, opts, path_prefix)
    end)
  end

  # Nested map entry — uses encode_to_lines to avoid the binary roundtrip.
  defp encode_map_entry(writer, key, value, depth, opts) do
    encoded_key = Strings.encode_key(key)
    header = [encoded_key, Constants.colon()]
    writer = Writer.push(writer, header, depth)

    current_prefix = Map.get(opts, :current_path_prefix, "")
    new_prefix = build_path_prefix(current_prefix, key)
    nested_opts = Map.put(opts, :current_path_prefix, new_prefix)
    nested_lines = encode_to_lines(value, depth + 1, nested_opts)

    append_lines(writer, nested_lines)
  end

  # Clause 1 — primitive final value
  defp encode_folded_value(writer, folded_key, final_value, depth, opts)
       when is_nil(final_value) or is_boolean(final_value) or
              is_number(final_value) or is_binary(final_value) do
    line = [
      folded_key,
      Constants.colon(),
      Constants.space(),
      Primitives.encode(final_value, opts.delimiter)
    ]

    Writer.push(writer, line, depth)
  end

  # Clause 2 — list (array) final value
  defp encode_folded_value(writer, folded_key, final_value, depth, opts)
       when is_list(final_value) do
    array_lines = Arrays.encode(folded_key, final_value, depth, opts)
    # 3-arg version — unchanged
    append_lines(writer, array_lines, depth)
  end

  # Clause 3 — empty map final value
  defp encode_folded_value(writer, folded_key, final_value, depth, _opts)
       when is_map(final_value) and map_size(final_value) == 0 do
    Writer.push(writer, [folded_key, Constants.colon()], depth)
  end

  # Clause 4 — non-empty map final value (UPDATED: uses encode_to_lines + append_lines/2)
  defp encode_folded_value(writer, folded_key, final_value, depth, opts)
       when is_map(final_value) do
    nested_opts = Map.put(opts, :flatten_depth, 0)
    header = [folded_key, Constants.colon()]
    writer = Writer.push(writer, header, depth)
    nested_lines = encode_to_lines(final_value, depth + 1, nested_opts)
    # 2-arg version from performance fix
    append_lines(writer, nested_lines)
  end

  # Clause 5 — fallback for any type not covered above (encodes as null)
  defp encode_folded_value(writer, folded_key, _final_value, depth, _opts) do
    Writer.push(
      writer,
      [folded_key, Constants.colon(), Constants.space(), Constants.null_literal()],
      depth
    )
  end

  # NEW helper — pushes pre-built line iodata directly into the writer.
  # Zero binary allocation vs the old append_iodata that did:
  #   IO.iodata_to_binary → String.split("\n") → Enum.reduce Writer.push
  #
  # Note: blank lines (empty iodata) are skipped to preserve the old
  # behaviour of append_iodata which filtered out empty strings.
  defp append_lines(writer, lines) do
    Enum.reduce(lines, writer, fn
      # skip empty lines produced by nested empty objects
      "", acc -> acc
      [], acc -> acc
      line, acc -> %{acc | lines: [line | acc.lines]}
    end)
  end

  # Collect all dotted keys that should prevent folding
  defp collect_forbidden_fold_paths(keys) do
    Enum.reduce(keys, MapSet.new(), fn key, acc ->
      if String.contains?(key, "."), do: MapSet.put(acc, key), else: acc
    end)
  end

  # Get keys in the correct order based on key_order option
  # Performance: Use MapSet for O(1) membership checks instead of O(n) list `in` checks
  # Pattern 1: key_order is a map with path-specific ordering
  defp get_ordered_keys(map, key_order, path) when is_map(key_order) do
    case Map.fetch(key_order, path) do
      {:ok, ordered} ->
        key_set = MapSet.new(Map.keys(map))
        Enum.filter(ordered, &MapSet.member?(key_set, &1))

      :error ->
        Map.keys(map)
    end
  end

  # Pattern 2: key_order is a list at root level
  defp get_ordered_keys(map, key_order, [])
       when is_list(key_order) and key_order != [] do
    existing_keys = Map.keys(map)
    key_set = MapSet.new(existing_keys)
    ordered_existing = Enum.filter(key_order, &MapSet.member?(key_set, &1))

    if length(ordered_existing) == map_size(map) do
      ordered_existing
    else
      existing_keys
    end
  end

  # Pattern 3: No key_order or not applicable - use map insertion order (Erlang 27+)
  defp get_ordered_keys(map, _key_order, _path) do
    Map.keys(map)
  end

  @doc """
  Encodes a single key-value pair.
  """
  @spec encode_entry(Writer.t(), String.t(), term(), non_neg_integer(), map(), String.t()) ::
          Writer.t()
  def encode_entry(writer, key, value, depth, opts, path_prefix \\ "") do
    # Check for key folding
    if should_fold?(key, value, opts, path_prefix) do
      encode_folded_entry(writer, key, value, depth, opts)
    else
      encode_regular_entry(writer, key, value, depth, opts)
    end
  end

  # Pattern match on value types for better clarity
  defp encode_regular_entry(writer, key, value, depth, opts)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value) do
    encode_primitive_entry(writer, key, value, depth, opts)
  end

  defp encode_regular_entry(writer, key, value, depth, opts) when is_list(value) do
    array_lines = Arrays.encode(key, value, depth, opts)
    append_lines(writer, array_lines, depth)
  end

  # Fragment — inject pre-encoded iodata directly (Jason-style)
  # Must come before is_map guard since Fragment is a struct (which is a map).
  #
  # Performance: Uses iodata_split_lines/1 instead of IO.iodata_to_binary + String.split.
  # This avoids materializing the entire fragment into a contiguous binary before splitting.
  # Instead, we walk the iodata tree and extract sub-binary references via binary_part/3,
  # preserving the zero-copy benefit of iolist construction. Only the final IO.iodata_to_binary
  # at the top-level encoder boundary flattens everything into a single binary.
  defp encode_regular_entry(writer, key, %ToonEx.Fragment{} = fragment, depth, opts) do
    encoded_key = Strings.encode_key(key)
    header = [encoded_key, Constants.colon()]
    writer = Writer.push(writer, header, depth)

    fragment_iodata = fragment.encode.(opts)

    # Split iodata on newlines without converting to binary first.
    # Each line remains as iodata (sub-binary references), preserving
    # the zero-copy benefit of iolist construction.
    case iodata_split_lines(fragment_iodata) do
      [] ->
        writer

      [""] ->
        writer

      lines ->
        indent = opts.indent_string
        indented_lines = Enum.map(lines, fn line -> [indent, line] end)
        append_lines(writer, indented_lines)
    end
  end

  defp encode_regular_entry(writer, key, value, depth, opts) when is_map(value) do
    encode_map_entry(writer, key, value, depth, opts)
  end

  defp encode_regular_entry(writer, key, _value, depth, opts) do
    encode_null_entry(writer, key, depth, opts)
  end

  # ── IOdata line splitter ─────────────────────────────────────────────────────
  # Splits iodata on newline characters without converting to a single binary.
  # Returns a list of iodata chunks, one per line.
  # Preserves sub-binary references (binary_part) for zero-copy line extraction.
  # This avoids the overhead of IO.iodata_to_binary/1 + String.split/2 which
  # materializes the entire fragment into a contiguous binary before splitting.

  @spec iodata_split_lines(iodata()) :: [iodata()]
  defp iodata_split_lines(binary) when is_binary(binary) do
    # Fast path for binary input: :binary.split with :global creates
    # sub-binary references (no full copy of each line).
    :binary.split(binary, "\n", [:global])
  end

  defp iodata_split_lines(list) when is_list(list) do
    do_iodata_split_lines(list, [], [])
  end

  # End of iodata list — finalize current line
  defp do_iodata_split_lines([], current_line_rev, lines_rev) do
    current_line = :lists.reverse(current_line_rev)
    :lists.reverse([current_line | lines_rev])
  end

  # Binary chunk — scan for newlines using :binary.match for O(n) scanning
  # with sub-binary extraction via binary_part (no full copy).
  defp do_iodata_split_lines([chunk | rest], current_line_rev, lines_rev)
       when is_binary(chunk) do
    case chunk do
      "" ->
        # Skip empty binary chunks — they add no content
        do_iodata_split_lines(rest, current_line_rev, lines_rev)

      _ ->
        case :binary.match(chunk, "\n") do
          :nomatch ->
            # No newline in this chunk — add to current line and continue
            do_iodata_split_lines(rest, [chunk | current_line_rev], lines_rev)

          {pos, 1} ->
            # Found newline at position pos — split the chunk using binary_part
            # (creates a sub-binary reference, no data copy)
            before = binary_part(chunk, 0, pos)
            after_pos = pos + 1
            rest_of_chunk = binary_part(chunk, after_pos, byte_size(chunk) - after_pos)

            # Complete current line with "before" part appended
            current_line =
              case before do
                "" -> :lists.reverse(current_line_rev)
                _ -> :lists.reverse(current_line_rev, [before])
              end

            # Continue with rest of chunk (may contain more newlines) and rest of iodata
            do_iodata_split_lines([rest_of_chunk | rest], [], [current_line | lines_rev])
        end
    end
  end

  # Nested iodata list — flatten into processing queue
  defp do_iodata_split_lines([chunk | rest], current_line_rev, lines_rev)
       when is_list(chunk) do
    do_iodata_split_lines(chunk ++ rest, current_line_rev, lines_rev)
  end

  # Single byte (integer) — check if it's a newline
  defp do_iodata_split_lines([chunk | rest], current_line_rev, lines_rev)
       when is_integer(chunk) do
    if chunk == ?\n do
      current_line = :lists.reverse(current_line_rev)
      do_iodata_split_lines(rest, [], [current_line | lines_rev])
    else
      do_iodata_split_lines(rest, [<<chunk>> | current_line_rev], lines_rev)
    end
  end

  # Helper functions for each entry type
  defp encode_primitive_entry(writer, key, value, depth, opts) do
    encoded_key = Strings.encode_key(key)

    line = [
      encoded_key,
      Constants.colon(),
      Constants.space(),
      Primitives.encode(value, opts.delimiter)
    ]

    Writer.push(writer, line, depth)
  end

  defp encode_null_entry(writer, key, depth, _opts) do
    encoded_key = Strings.encode_key(key)
    line = [encoded_key, Constants.colon(), Constants.space(), Constants.null_literal()]
    Writer.push(writer, line, depth)
  end

  # Performance: Return iolist for non-empty prefix to avoid binary concatenation
  # at each nesting level. The iolist is converted to binary only when needed
  # for MapSet membership checks in has_collision?/4.
  defp build_path_prefix("", key), do: key
  defp build_path_prefix(prefix, key), do: [prefix, ".", key]

  # Check if we should fold this key-value pair into a dotted path
  defp should_fold?(key, value, opts, path_prefix) do
    case Map.get(opts, :key_folding, :off) do
      :safe ->
        # Only fold single-key maps with valid identifier segments
        Utils.map?(value) and
          map_size(value) == 1 and
          valid_identifier_segment?(key) and
          flatten_depth_allows?(opts, 1) and
          not has_collision?(key, value, opts, path_prefix)

      _ ->
        false
    end
  end

  # Check if folding would create a collision with forbidden fold paths
  # Performance: Convert iolist path_prefix to binary only at the MapSet boundary.
  # path_prefix may be an iolist (from build_path_prefix) or a binary (initial "").
  # IO.iodata_to_binary/1 on a binary is essentially a no-op, so this is safe for both cases.
  defp has_collision?(key, value, opts, path_prefix) do
    forbidden = Map.get(opts, :forbidden_fold_paths, MapSet.new())

    # Compute what the full folded path would be
    {path, _final_value} = collect_fold_path([key], value, %{flatten_depth: :infinity}, 1)
    local_folded = Enum.join(path, ".")

    # Convert path_prefix from iodata to binary for MapSet membership check
    prefix_bin = IO.iodata_to_binary(path_prefix)

    # Build the full path from root as iodata, then convert to binary for MapSet check
    full_folded_key =
      if prefix_bin == "" do
        local_folded
      else
        IO.iodata_to_binary([prefix_bin, ".", local_folded])
      end

    # Check if the full folded path collides with any forbidden path
    MapSet.member?(forbidden, full_folded_key)
  end

  # Performance: Binary pattern matching instead of regex for O(1) check
  # Matches: ^[A-Za-z_][A-Za-z0-9_]*$
  defp valid_identifier_segment?(<<first, rest::binary>>) do
    do_valid_id_first?(first) and do_valid_id_rest?(rest)
  end

  defp valid_identifier_segment?(_), do: false

  defp do_valid_id_first?(c) when c in ?A..?Z, do: true
  defp do_valid_id_first?(c) when c in ?a..?z, do: true
  defp do_valid_id_first?(?_), do: true
  defp do_valid_id_first?(_), do: false

  defp do_valid_id_rest?(<<>>), do: true
  defp do_valid_id_rest?(<<c, rest::binary>>) when c in ?A..?Z, do: do_valid_id_rest?(rest)
  defp do_valid_id_rest?(<<c, rest::binary>>) when c in ?a..?z, do: do_valid_id_rest?(rest)
  defp do_valid_id_rest?(<<c, rest::binary>>) when c in ?0..?9, do: do_valid_id_rest?(rest)
  defp do_valid_id_rest?(<<?_, rest::binary>>), do: do_valid_id_rest?(rest)
  defp do_valid_id_rest?(_), do: false

  defp flatten_depth_allows?(opts, current_depth) do
    case Map.get(opts, :flatten_depth, :infinity) do
      :infinity -> true
      max when is_integer(max) -> current_depth <= max
    end
  end

  # Encode a folded key-value pair (collapse single-key chains)
  # Pattern match on final value type for clarity
  defp encode_folded_entry(writer, key, value, depth, opts) do
    {path, final_value} = collect_fold_path([key], value, opts, 1)
    folded_key = Enum.join(path, ".")

    encode_folded_value(writer, folded_key, final_value, depth, opts)
  end

  # Recursively collect the path for folding
  # Performance: Use accumulator pattern with [next_key | acc] instead of path ++ [next_key]
  # to avoid O(n²) list concatenation in deep fold chains

  # Pattern 1: Not a map - stop folding
  defp collect_fold_path(path, value, _opts, _current_depth) when not is_map(value) do
    {:lists.reverse(path), value}
  end

  # Pattern 2: Map with size != 1 - stop folding
  defp collect_fold_path(path, value, _opts, _current_depth)
       when is_map(value) and map_size(value) != 1 do
    {:lists.reverse(path), value}
  end

  # Pattern 3: Continue folding if conditions are met
  defp collect_fold_path(path, value, opts, current_depth) when is_map(value) do
    if flatten_depth_allows?(opts, current_depth + 1) do
      [{next_key, next_value}] = Map.to_list(value)

      if valid_identifier_segment?(next_key) do
        collect_fold_path([next_key | path], next_value, opts, current_depth + 1)
      else
        {:lists.reverse(path), value}
      end
    else
      {:lists.reverse(path), value}
    end
  end

  # Private helpers

  defp append_lines(writer, [header | data_rows], depth) do
    # For arrays, the first line is the header at current depth
    # Subsequent lines (data rows for tabular format) should be one level deeper
    writer = Writer.push(writer, header, depth)

    Enum.reduce(data_rows, writer, fn row, acc ->
      Writer.push(acc, row, depth + 1)
    end)
  end
end
