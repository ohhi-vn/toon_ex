defmodule ToonEx.Encode.Stream do
  @moduledoc """
  Streaming encoder for TOON format.

  This module provides a way to encode large data structures incrementally,
  yielding iodata chunks that can be sent over the network without materializing
  the entire output in memory.

  ## Usage

      # For Plug/Phoenix chunked responses:
      conn
      |> put_resp_content_type("application/toon")
      |> send_chunked(200, fn chunk ->
        ToonEx.Encode.Stream.encode_stream(large_dataset, opts)
        |> Enum.each(&chunk.(&1))
      end)

      # Or as a simple stream:
      stream = ToonEx.Encode.Stream.encode_stream(data, opts)
      |> Stream.map(&IO.iodata_to_binary/1)
      |> Stream.each(&IO.write/1)
      |> Stream.run()

  ## Performance

  The streaming encoder avoids allocating the full output binary upfront.
  It yields iodata chunks that are converted to binaries only when consumed.
  Memory usage stays constant regardless of output size.
  """

  alias ToonEx.Constants
  alias ToonEx.Encode.{Arrays, Objects, Options, Primitives, Strings, Writer}
  alias ToonEx.Utils

  @type opts :: keyword()
  @type iodata_chunk :: iodata()

  @doc """
  Encodes an Elixir term to a stream of TOON iodata chunks.

  Returns an `Enumerable.t()` that yields iodata chunks. Each chunk is a valid
  TOON fragment that can be concatenated to form the complete output.

  ## Options

  Same as `ToonEx.encode/2`:
  - `:indent` - Number of spaces for indentation (default: 2)
  - `:delimiter` - Delimiter for array values: "," | "\t" | "|" (default: ",")
  - `:length_marker` - Prefix for array length marker (default: nil)
  - `:key_folding` - Key folding mode: `:off` | `:safe` (default: `:off`)
  - `:flatten_depth` - Max depth for key folding (default: `:infinity`)

  ## Example

      stream = ToonEx.Encode.Stream.encode_stream(%{"users" => large_list}, indent: 4)
      # Returns an Enumerable that yields iodata chunks
  """
  @spec encode_stream(ToonEx.Types.input(), opts) :: Enumerable.t()
  def encode_stream(data, opts \\ []) do
    validated_opts = Options.validate!(opts)
    normalized = Utils.normalize(data)

    # Build the full output as a stream of chunks
    do_encode_stream(normalized, 0, validated_opts)
  end

  # Main entry - returns a stream of chunks
  defp do_encode_stream(%ToonEx.Fragment{} = fragment, _depth, opts) do
    iodata = fragment.encode.(opts)
    [iodata]
  end

  defp do_encode_stream(data, depth, opts) when is_map(data) do
    # Keyed tabular form at the root mirrors ToonEx.Encode.Objects.encode/3.
    detected =
      if depth == 0, do: Utils.detect_keyed_tabular(data), else: :error

    case detected do
      {:ok, fields} ->
        [header | rows] = Arrays.encode_keyed_fields(nil, data, fields, opts)

        writer =
          Enum.reduce(rows, Writer.push(Writer.new(opts.indent), header, 0), fn row, acc ->
            Writer.push(acc, row, 1)
          end)

        [[Writer.to_iodata(writer)]]

      :error ->
        encode_chunked_map_stream(data, depth, opts)
    end
  end

  # Root arrays render through the writer so header and rows land on their own
  defp do_encode_stream(data, depth, opts) when is_list(data) do
    if data == [] do
      [[Arrays.encode_empty("items", opts.length_marker)]]
    else
      case Utils.detect_tabular_fields(data) do
        {:ok, _fields} ->
          [render_array_lines(Arrays.encode_tabular("items", data, 0, opts), opts)]

        :error ->
          case detect_array_type(data) do
            {:primitive, _} ->
              # Inline arrays are a single line – safe as one raw chunk.
              [[Arrays.encode_inline("items", data, opts)]]

            _ ->
              [render_array_lines(Arrays.encode_list("items", data, depth, opts), opts)]
          end
      end
    end
  end

  # Root arrays render through the writer so header and rows land on their own
  # newline-separated lines (matching `ToonEx.encode!(%{"items" => list})`).
  defp render_array_lines([header | rows], opts) do
    writer =
      Enum.reduce(rows, Writer.push(Writer.new(opts.indent), header, 0), fn row, acc ->
        Writer.push(acc, row, 1)
      end)

    Writer.to_iodata(writer)
  end

  # Encode a single entry
  defp encode_entry_stream(writer, key, value, depth, opts) do
    if should_fold?(key, value, opts, "") do
      encode_folded_entry_stream(writer, key, value, depth, opts)
    else
      encode_regular_entry_stream(writer, key, value, depth, opts)
    end
  end

  # Regular (non-folded) entry encoding
  defp encode_regular_entry_stream(writer, key, value, depth, opts)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value) do
    encoded_key = Strings.encode_key(key)

    line = [
      encoded_key,
      Constants.colon(),
      Constants.space(),
      Primitives.encode(value, opts.delimiter)
    ]

    Writer.push(writer, line, depth)
  end

  defp encode_regular_entry_stream(writer, key, value, depth, opts) when is_list(value) do
    array_lines = Arrays.encode(key, value, depth, opts)
    append_array_lines(writer, array_lines, depth)
  end

  defp encode_regular_entry_stream(writer, key, %ToonEx.Fragment{} = fragment, depth, opts) do
    encoded_key = Strings.encode_key(key)
    header = [encoded_key, Constants.colon()]
    writer = Writer.push(writer, header, depth)

    fragment_iodata = fragment.encode.(opts)

    case iodata_split_lines(fragment_iodata) do
      [] ->
        writer

      [""] ->
        writer

      lines ->
        indent = opts.indent_string
        indented_lines = Enum.map(lines, fn line -> [indent, line] end)
        Writer.push_many(writer, indented_lines, depth)
    end
  end

  defp encode_regular_entry_stream(writer, key, value, depth, opts) when is_map(value) do
    encode_map_entry_stream(writer, key, value, depth, opts)
  end

  defp encode_regular_entry_stream(writer, key, _value, depth, _opts) do
    encode_null_entry_stream(writer, key, depth)
  end

  # Append array lines with proper indentation: header at current depth, rows at depth+1
  defp append_array_lines(writer, [header | data_rows], depth) do
    writer = Writer.push(writer, header, depth)

    Enum.reduce(data_rows, writer, fn row, acc ->
      Writer.push(acc, row, depth + 1)
    end)
  end

  # Null entry
  defp encode_null_entry_stream(writer, key, depth) do
    encoded_key = Strings.encode_key(key)
    line = [encoded_key, Constants.colon(), Constants.space(), Constants.null_literal()]
    Writer.push(writer, line, depth)
  end

  # Folded entry encoding
  defp encode_folded_entry_stream(writer, key, value, depth, opts) do
    {path, final_value} = collect_fold_path([key], value, opts, 1)
    folded_key = Enum.join(path, ".")
    encode_folded_value_stream(writer, folded_key, final_value, depth, opts)
  end

  defp encode_folded_value_stream(writer, folded_key, final_value, depth, opts)
       when is_nil(final_value) or is_boolean(final_value) or is_number(final_value) or
              is_binary(final_value) do
    line = [
      folded_key,
      Constants.colon(),
      Constants.space(),
      Primitives.encode(final_value, opts.delimiter)
    ]

    Writer.push(writer, line, depth)
  end

  defp encode_folded_value_stream(writer, folded_key, final_value, depth, opts)
       when is_list(final_value) do
    array_lines = Arrays.encode(folded_key, final_value, depth, opts)
    Writer.push_many(writer, array_lines, depth)
  end

  defp encode_folded_value_stream(writer, folded_key, final_value, depth, _opts)
       when is_map(final_value) and map_size(final_value) == 0 do
    Writer.push(writer, [folded_key, Constants.colon()], depth)
  end

  defp encode_folded_value_stream(writer, folded_key, final_value, depth, opts)
       when is_map(final_value) do
    case Utils.detect_keyed_tabular(final_value) do
      {:ok, fields} ->
        [header | rows] =
          Arrays.encode_keyed_fields(
            Strings.encode_key(folded_key),
            final_value,
            fields,
            opts
          )

        writer = Writer.push(writer, header, depth)

        Enum.reduce(rows, writer, fn row, acc ->
          Writer.push(acc, row, depth + 1)
        end)

      :error ->
        nested_opts = Map.put(opts, :flatten_depth, 0)
        header = [folded_key, Constants.colon()]
        writer = Writer.push(writer, header, depth)
        nested_lines = Objects.encode_to_lines(final_value, depth + 1, nested_opts)
        Writer.push_many(writer, nested_lines, depth)
    end
  end

  # Map entry encoding for nested maps
  defp encode_map_entry_stream(writer, key, value, depth, opts) do
    case Utils.detect_keyed_tabular(value) do
      {:ok, fields} ->
        [header | rows] =
          Arrays.encode_keyed_fields(Strings.encode_key(key), value, fields, opts)

        writer = Writer.push(writer, header, depth)

        Enum.reduce(rows, writer, fn row, acc ->
          Writer.push(acc, row, depth + 1)
        end)

      :error ->
        encoded_key = Strings.encode_key(key)
        header = [encoded_key, Constants.colon()]
        writer = Writer.push(writer, header, depth)

        current_prefix = Map.get(opts, :current_path_prefix, "")
        new_prefix = build_path_prefix(current_prefix, key)
        nested_opts = Map.put(opts, :current_path_prefix, new_prefix)
        nested_lines = Objects.encode_to_lines(value, depth + 1, nested_opts)
        Writer.push_many(writer, nested_lines, depth)
    end
  end

  # Helper to split iodata on newlines without converting to binary
  defp iodata_split_lines(binary) when is_binary(binary) do
    :binary.split(binary, "\n", [:global])
  end

  defp iodata_split_lines(list) when is_list(list) do
    do_iodata_split_lines(list, [], [])
  end

  defp do_iodata_split_lines([], current_line_rev, lines_rev) do
    current_line = :lists.reverse(current_line_rev)
    :lists.reverse([current_line | lines_rev])
  end

  defp do_iodata_split_lines([chunk | rest], current_line_rev, lines_rev)
       when is_binary(chunk) do
    case chunk do
      "" ->
        do_iodata_split_lines(rest, current_line_rev, lines_rev)

      _ ->
        case :binary.match(chunk, "\n") do
          :nomatch ->
            do_iodata_split_lines(rest, [chunk | current_line_rev], lines_rev)

          {pos, 1} ->
            before = binary_part(chunk, 0, pos)
            after_pos = pos + 1
            rest_of_chunk = binary_part(chunk, after_pos, byte_size(chunk) - after_pos)

            current_line =
              case before do
                "" -> :lists.reverse(current_line_rev)
                _ -> :lists.reverse(current_line_rev, [before])
              end

            do_iodata_split_lines([rest_of_chunk | rest], [], [current_line | lines_rev])
        end
    end
  end

  defp do_iodata_split_lines([chunk | rest], current_line_rev, lines_rev)
       when is_list(chunk) do
    do_iodata_split_lines(chunk ++ rest, current_line_rev, lines_rev)
  end

  defp do_iodata_split_lines([chunk | rest], current_line_rev, lines_rev)
       when is_integer(chunk) do
    if chunk == ?\n do
      current_line = :lists.reverse(current_line_rev)
      do_iodata_split_lines(rest, [], [current_line | lines_rev])
    else
      do_iodata_split_lines(rest, [<<chunk>> | current_line_rev], lines_rev)
    end
  end

  defp encode_chunked_map_stream(data, depth, opts) do
    keys = get_ordered_keys(data, Map.get(opts, :key_order), [])
    writer = Writer.new(opts.indent)

    # When the working writer reaches the chunk threshold its content is
    # flushed as one chunk and iteration continues with a fresh writer, so
    # memory stays bounded and the concatenated chunks equal the full encoding.
    {final_writer, chunks_rev} =
      Enum.reduce(keys, {writer, []}, fn key, {w, acc} ->
        value = Utils.object_get(data, key)
        new_w = encode_entry_stream(w, key, value, depth, opts)

        if writer_is_full?(new_w) do
          {Writer.new(opts.indent), [Writer.to_iodata(new_w) | acc]}
        else
          {new_w, acc}
        end
      end)

    # Flushed chunks hold earlier entries; the remaining writer holds the tail.
    # Newlines go BETWEEN chunks so no trailing newline is introduced.
    tail = Writer.to_iodata(final_writer)

    case Enum.reverse(chunks_rev) do
      [] ->
        [tail]

      chunks ->
        parts = if tail == [], do: chunks, else: chunks ++ [tail]
        Enum.intersperse(parts, Constants.newline())
    end
  end

  # Key ordering (reuse from Objects)
  defp get_ordered_keys(%ToonEx.OrderedObject{} = map, key_order, _path) do
    keys = Utils.object_keys(map)

    case key_order do
      key_order when is_list(key_order) and key_order != [] ->
        key_set = MapSet.new(keys)
        ordered = Enum.filter(key_order, &MapSet.member?(key_set, &1))

        if length(ordered) == length(keys), do: ordered, else: keys

      _ ->
        keys
    end
  end

  defp get_ordered_keys(map, key_order, path) when is_map(key_order) do
    case Map.fetch(key_order, path) do
      {:ok, ordered} ->
        key_set = MapSet.new(Utils.object_keys(map))
        Enum.filter(ordered, &MapSet.member?(key_set, &1))

      :error ->
        Utils.object_keys(map)
    end
  end

  defp get_ordered_keys(map, key_order, [])
       when is_list(key_order) and key_order != [] do
    existing_keys = Utils.object_keys(map)
    key_set = MapSet.new(existing_keys)
    ordered_existing = Enum.filter(key_order, &MapSet.member?(key_set, &1))

    if length(ordered_existing) == length(existing_keys) do
      ordered_existing
    else
      existing_keys
    end
  end

  defp get_ordered_keys(map, _key_order, _path) do
    Utils.object_keys(map)
  end

  # Key folding helpers
  defp should_fold?(key, value, opts, path_prefix) do
    case Map.get(opts, :key_folding, :off) do
      :safe ->
        Utils.map?(value) and
          Utils.object_size(value) == 1 and
          valid_identifier_segment?(key) and
          flatten_depth_allows?(opts, 1) and
          not has_collision?(key, value, opts, path_prefix)

      _ ->
        false
    end
  end

  defp has_collision?(key, value, opts, path_prefix) do
    forbidden = Map.get(opts, :forbidden_fold_paths, MapSet.new())

    {path, _final_value} = collect_fold_path([key], value, %{flatten_depth: :infinity}, 1)
    local_folded = Enum.join(path, ".")

    prefix_bin = IO.iodata_to_binary(path_prefix)

    full_folded_key =
      if prefix_bin == "" do
        local_folded
      else
        IO.iodata_to_binary([prefix_bin, ".", local_folded])
      end

    MapSet.member?(forbidden, full_folded_key)
  end

  defp collect_fold_path(path, value, _opts, _current_depth) when not is_map(value) do
    {:lists.reverse(path), value}
  end

  defp collect_fold_path(path, value, _opts, _current_depth)
       when is_map(value) and map_size(value) != 1 do
    {:lists.reverse(path), value}
  end

  defp collect_fold_path(path, value, opts, current_depth) when is_map(value) do
    if flatten_depth_allows?(opts, current_depth + 1) do
      [{next_key, next_value}] = Utils.object_to_list(value)

      if valid_identifier_segment?(next_key) do
        collect_fold_path([next_key | path], next_value, opts, current_depth + 1)
      else
        {:lists.reverse(path), value}
      end
    else
      {:lists.reverse(path), value}
    end
  end

  defp flatten_depth_allows?(opts, current_depth) do
    case Map.get(opts, :flatten_depth, :infinity) do
      :infinity -> true
      max when is_integer(max) -> current_depth <= max
    end
  end

  defp build_path_prefix("", key), do: key
  defp build_path_prefix(prefix, key), do: [prefix, ".", key]

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

  # Array type detection
  defp detect_array_type(list) do
    case do_detect_array_type(list, {true, true, true, nil, 0, false}) do
      {:primitive, length} -> {:primitive, length}
      {:tabular, length, keys} -> {:tabular, length, keys}
      {:list, length} -> {:list, length}
    end
  end

  defp do_detect_array_type([], {false, true, true, keys, count, _count_only})
       when is_list(keys) and keys != [],
       do: {:tabular, count, keys}

  defp do_detect_array_type([], {true, _, _, _, count, _count_only}),
    do: {:primitive, count}

  defp do_detect_array_type([], {_, _, _, _, count, _count_only}),
    do: {:list, count}

  defp do_detect_array_type([_ | t], {_, _, _, _, count, true}) do
    do_detect_array_type(t, {false, false, false, nil, count + 1, true})
  end

  defp do_detect_array_type([h | t], {all_prim, all_maps, all_prim_vals, keys, count, false}) do
    new_count = count + 1

    cond do
      (not all_prim and not all_maps) or (all_maps and not all_prim_vals) ->
        do_detect_array_type(t, {false, false, false, nil, new_count, true})

      is_nil(h) or is_boolean(h) or is_number(h) or is_binary(h) ->
        do_detect_array_type(t, {all_prim, false, all_prim_vals, nil, new_count, false})

      is_map(h) ->
        h_keys =
          case h do
            %ToonEx.OrderedObject{} -> Utils.object_keys(h)
            _ -> Map.keys(h) |> Enum.sort()
          end

        h_all_prim = do_all_values_primitive?(h)

        new_keys =
          if keys do
            if h_keys == keys, do: keys, else: nil
          else
            h_keys
          end

        if h_all_prim do
          do_detect_array_type(
            t,
            {false, all_maps, all_prim_vals and h_all_prim, new_keys, new_count, false}
          )
        else
          do_detect_array_type(t, {false, false, false, nil, new_count, true})
        end

      true ->
        do_detect_array_type(t, {false, false, false, nil, new_count, true})
    end
  end

  defp do_all_values_primitive?(map) do
    Utils.object_values(map) |> Enum.all?(fn v -> Utils.primitive?(v) end)
  end

  defp writer_is_full?(%Writer{lines: lines}) when length(lines) >= 100, do: true
  defp writer_is_full?(_), do: false
end
