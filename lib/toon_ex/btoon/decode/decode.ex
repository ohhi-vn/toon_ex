defmodule ToonEx.Btoon.Decode do
  @moduledoc """
  BTOON decoder.

  Parses the BTOON wire format back into the data model:

    * Envelope: `"BTON"` magic, version, flags, optional per-message string
      table and embedded schema, then an 8-byte-aligned body.
    * Tagged values with inline `SmallInt`, fixed-width little-endian
      integers/floats, zero-copy strings and binaries (BEAM sub-binaries).
    * `StringRef` ids resolved against the session dictionary first, then the
      per-message string table.
    * `TypedArray` and `ObjectTable` payloads materialized as lists or
      exposed as zero-copy views (`typed_arrays: :views`).
    * Schema mode: `SchemaID` followed by ordered, tagless fixed-width fields
      decoded strictly according to the (embedded or supplied) schema.

  ## API

      iex> {:ok, value} = ToonEx.Btoon.Decode.decode(<<66, 84, 79, 78, 1, 0, 0, 0, 106>>)
      iex> value
      42
  """

  alias ToonEx.Btoon.{
    Binary,
    Constants,
    DecodeError,
    ElementType,
    ObjectTable,
    Schema,
    TypedArray
  }

  alias ToonEx.Btoon.Decode.Options

  @compile {:inline,
            take!: 4, pad_to: 2, read_int32: 2, read_int64: 2, read_float32: 2, read_float64: 2}

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  Decodes a BTOON binary.

  Returns `{:ok, value}` or `{:error, ToonEx.Btoon.DecodeError.t()}`.
  """
  @spec decode(binary(), keyword()) :: {:ok, term()} | {:error, ToonEx.Btoon.DecodeError.t()}
  def decode(binary, opts \\ []) do
    case Options.validate(opts) do
      {:ok, validated} ->
        try do
          {:ok, do_decode(binary, validated)}
        rescue
          e in DecodeError -> {:error, e}
          e -> {:error, DecodeError.exception(message: Exception.message(e), input: binary)}
        end

      {:error, message} ->
        {:error, DecodeError.exception(message: message, input: binary)}
    end
  end

  @doc """
  Decodes a BTOON binary, raising `ToonEx.Btoon.DecodeError` on error.
  """
  @spec decode!(binary(), keyword()) :: term()
  def decode!(binary, opts \\ []) do
    validated = Options.validate!(opts)
    do_decode(binary, validated)
  rescue
    e in DecodeError -> reraise e, __STACKTRACE__
    e -> raise DecodeError, message: Exception.message(e), input: binary
  end

  defp do_decode(binary, opts) when is_binary(binary) do
    {strings, schema, body_offset} = parse_envelope(binary, opts)
    ctx = new_ctx(strings, opts)

    case schema do
      nil ->
        {value, _next} = decode_value(binary, body_offset, ctx, opts.max_depth)
        value

      schema ->
        decode_schema_body(binary, body_offset, schema, ctx, opts.max_depth)
    end
  end

  # ── Envelope ────────────────────────────────────────────────────────────────

  defp parse_envelope(bin, opts) do
    <<magic::binary-size(4), version, flags, _reserved::16-little>> =
      take!(bin, 0, 8, "envelope header")

    if magic != Constants.magic() do
      raise DecodeError,
        message: "invalid BTOON magic",
        input: bin,
        offset: 0,
        reason: {:bad_magic, magic}
    end

    if version != Constants.version() do
      raise DecodeError,
        message: "unsupported BTOON version #{version}",
        input: bin,
        offset: 4,
        reason: {:bad_version, version}
    end

    offset = Constants.header_size()

    {table_entries, offset} =
      if Bitwise.band(flags, Constants.flag_string_table()) != 0 do
        parse_table(bin, offset)
      else
        {[], offset}
      end

    offset = offset + pad_to(offset, 8)

    {schema, offset} =
      if Bitwise.band(flags, Constants.flag_schema()) != 0 do
        parse_schema(bin, offset)
      else
        {opts.schema, offset}
      end

    offset = offset + pad_to(offset, 8)

    session_entries =
      case opts.dictionary do
        nil -> []
        dict -> ToonEx.Btoon.Dictionary.entries(dict)
      end

    {List.to_tuple(session_entries ++ table_entries), schema, offset}
  end

  defp parse_table(bin, offset) do
    <<count::32-little>> = take!(bin, offset, 4, "string table count")
    parse_table_entries(count, bin, offset + 4, [])
  end

  defp parse_table_entries(0, _bin, offset, acc), do: {:lists.reverse(acc), offset}

  defp parse_table_entries(count, bin, offset, acc) do
    <<len::32-little>> = take!(bin, offset, 4, "string entry length")
    string = take!(bin, offset + 4, len, "string entry")
    parse_table_entries(count - 1, bin, offset + 4 + len, [string | acc])
  end

  defp parse_schema(bin, offset) do
    <<id::32-little>> = take!(bin, offset, 4, "schema id")
    <<name_len::32-little>> = take!(bin, offset + 4, 4, "schema name length")
    name = take!(bin, offset + 8, name_len, "schema name")
    offset = offset + 8 + name_len
    <<field_count::32-little>> = take!(bin, offset, 4, "schema field count")
    {fields, offset} = parse_schema_fields(field_count, bin, offset + 4, [])
    {%Schema{id: id, name: name, fields: fields}, offset}
  end

  defp parse_schema_fields(0, _bin, offset, acc), do: {:lists.reverse(acc), offset}

  defp parse_schema_fields(count, bin, offset, acc) do
    <<name_len::32-little>> = take!(bin, offset, 4, "schema field name length")
    field_name = take!(bin, offset + 4, name_len, "schema field name")

    case ElementType.type_atom_or_nil(byte!(bin, offset + 4 + name_len)) do
      nil ->
        raise DecodeError,
          message: "invalid schema field type",
          input: bin,
          offset: offset + 4 + name_len,
          reason: :invalid_schema_type

      type ->
        field = %{name: field_name, type: type}
        parse_schema_fields(count - 1, bin, offset + 5 + name_len, [field | acc])
    end
  end

  # ── Context ─────────────────────────────────────────────────────────────────

  defmodule Ctx do
    @moduledoc false
    defstruct strings: {},
              keys: :strings,
              typed_arrays: :lists
  end

  defp new_ctx(strings, opts) do
    %Ctx{
      strings: strings,
      keys: opts.keys,
      typed_arrays: opts.typed_arrays
    }
  end

  # ── Value dispatch ──────────────────────────────────────────────────────────

  # Returns {value, next_offset}. `offset` is absolute in `bin`.

  defp decode_value(bin, offset, ctx, depth) do
    if depth <= 0 do
      raise DecodeError,
        message: "maximum nesting depth exceeded",
        input: bin,
        offset: offset,
        reason: :depth_exceeded
    end

    tag = byte!(bin, offset)

    case tag do
      _ when tag >= 0x20 and tag <= 0x9F ->
        {tag - 0x40, offset + 1}

      0x00 ->
        {nil, offset + 1}

      0x01 ->
        {false, offset + 1}

      0x02 ->
        {true, offset + 1}

      0x03 ->
        {read_int32(bin, offset + 1), offset + 5}

      0x04 ->
        {read_int64(bin, offset + 1), offset + 9}

      0x05 ->
        {read_float32(bin, offset + 1), offset + 5}

      0x06 ->
        {read_float64(bin, offset + 1), offset + 9}

      0x07 ->
        decode_string(bin, offset)

      0x08 ->
        decode_binary(bin, offset)

      0x09 ->
        decode_array(bin, offset, ctx, depth)

      0x0A ->
        decode_object(bin, offset, ctx, depth)

      0x0B ->
        decode_ref(bin, offset, ctx)

      0x0C ->
        decode_typed_array(bin, offset, ctx)

      0x0D ->
        decode_object_table(bin, offset, ctx)

      _ ->
        raise DecodeError,
          message: "unknown value tag 0x#{Integer.to_string(tag, 16)}",
          input: bin,
          offset: offset,
          reason: {:invalid_tag, tag}
    end
  end

  defp read_int32(bin, offset) do
    <<value::32-little-signed>> = take!(bin, offset, 4, "int32")
    value
  end

  defp read_int64(bin, offset) do
    <<value::64-little-signed>> = take!(bin, offset, 8, "int64")
    value
  end

  defp read_float32(bin, offset) do
    <<value::32-little-float>> = take!(bin, offset, 4, "float32")
    value
  end

  defp read_float64(bin, offset) do
    <<value::64-little-float>> = take!(bin, offset, 8, "float64")
    value
  end

  # ── Strings & references ────────────────────────────────────────────────────

  defp decode_string(bin, offset) do
    <<len::32-little>> = take!(bin, offset + 1, 4, "string length")
    string = take!(bin, offset + 5, len, "string data")
    {string, offset + 5 + len}
  end

  defp decode_binary(bin, offset) do
    <<len::32-little>> = take!(bin, offset + 1, 4, "binary length")
    data = take!(bin, offset + 5, len, "binary data")
    {%Binary{data: data}, offset + 5 + len}
  end

  # String field/key: a full string tag or a StringRef.
  defp decode_string_or_ref(bin, offset, ctx) do
    tag = byte!(bin, offset)

    cond do
      tag == Constants.tag_string() ->
        decode_string(bin, offset)

      tag == Constants.tag_string_ref() ->
        decode_ref(bin, offset, ctx)

      true ->
        raise DecodeError,
          message: "expected string or string ref",
          input: bin,
          offset: offset,
          reason: {:invalid_string, tag}
    end
  end

  defp decode_ref(bin, offset, ctx) do
    {id, offset} = decode_int(bin, offset + 1)

    if id >= 0 and id < :erlang.tuple_size(ctx.strings) do
      {:erlang.element(id + 1, ctx.strings), offset}
    else
      raise DecodeError,
        message: "string ref #{id} out of range",
        input: bin,
        offset: offset,
        reason: {:invalid_string_ref, id}
    end
  end

  # Integer used by SmallInt/Int32/Int64 and StringRef ids.
  defp decode_int(bin, offset) do
    tag = byte!(bin, offset)

    case tag do
      _ when tag >= 0x20 and tag <= 0x9F ->
        {tag - 0x40, offset + 1}

      0x03 ->
        {read_int32(bin, offset + 1), offset + 5}

      0x04 ->
        {read_int64(bin, offset + 1), offset + 9}

      _ ->
        raise DecodeError,
          message: "expected integer",
          input: bin,
          offset: offset,
          reason: {:invalid_integer, tag}
    end
  end

  # ── Arrays ──────────────────────────────────────────────────────────────────

  defp decode_array(bin, offset, ctx, depth) do
    <<count::32-little>> = take!(bin, offset + 1, 4, "array count")
    {values, offset} = decode_items(count, bin, offset + 5, ctx, depth, [])
    {values, offset}
  end

  defp decode_items(0, _bin, offset, _ctx, _depth, acc), do: {:lists.reverse(acc), offset}

  defp decode_items(count, bin, offset, ctx, depth, acc) do
    {value, offset} = decode_value(bin, offset, ctx, depth - 1)
    decode_items(count - 1, bin, offset, ctx, depth, [value | acc])
  end

  # ── Objects ─────────────────────────────────────────────────────────────────

  defp decode_object(bin, offset, ctx, depth) do
    <<count::32-little>> = take!(bin, offset + 1, 4, "object count")
    {pairs, offset} = decode_pairs(count, bin, offset + 5, ctx, depth, [])
    {build_object(pairs, ctx), offset}
  end

  defp decode_pairs(0, _bin, offset, _ctx, _depth, acc), do: {:lists.reverse(acc), offset}

  defp decode_pairs(count, bin, offset, ctx, depth, acc) do
    {key, offset} = decode_object_key(bin, offset, ctx)
    {value, offset} = decode_value(bin, offset, ctx, depth - 1)
    decode_pairs(count - 1, bin, offset, ctx, depth, [{key, value} | acc])
  end

  defp decode_object_key(bin, offset, ctx), do: decode_string_or_ref(bin, offset, ctx)

  defp build_object(pairs, %Ctx{keys: :strings}), do: Map.new(pairs)

  defp build_object(pairs, %Ctx{keys: keys}) do
    Map.new(pairs, fn {name, value} -> {convert_key(name, keys), value} end)
  end

  defp convert_key(name, :atoms), do: String.to_atom(name)
  defp convert_key(name, :atoms!), do: String.to_existing_atom(name)

  # ── Typed arrays ────────────────────────────────────────────────────────────

  defp decode_typed_array(bin, offset, ctx) do
    <<type_byte, count::32-little, pad>> = take!(bin, offset + 1, 6, "typed array header")

    type = ElementType.type_atom_or_nil(type_byte)

    unless type && ElementType.typed_array_type?(type) do
      raise DecodeError,
        message: "invalid typed array element type 0x#{Integer.to_string(type_byte, 16)}",
        input: bin,
        offset: offset + 1,
        reason: {:invalid_typed_array_type, type_byte}
    end

    elem_size = ElementType.element_size(type)
    data_offset = offset + 7 + pad
    data = take!(bin, data_offset, count * elem_size, "typed array data")

    value =
      case ctx.typed_arrays do
        :views -> %TypedArray{type: type, data: data}
        :lists -> ElementType.buffer_to_list(type, data)
      end

    {value, data_offset + count * elem_size}
  end

  # ── Object tables ───────────────────────────────────────────────────────────

  defp decode_object_table(bin, offset, ctx) do
    <<row_count::32-little, column_count::32-little>> =
      take!(bin, offset + 1, 8, "object table header")

    {columns, offset} = decode_columns(column_count, row_count, bin, offset + 9, ctx, [])

    table = %ObjectTable{row_count: row_count, columns: columns}

    value =
      case ctx.typed_arrays do
        :views -> table
        :lists -> object_table_rows(table, ctx)
      end

    {value, offset}
  end

  defp decode_columns(0, _row_count, _bin, offset, _ctx, acc), do: {:lists.reverse(acc), offset}

  defp decode_columns(count, row_count, bin, offset, ctx, acc) do
    {name, offset} = decode_object_key(bin, offset, ctx)
    <<type_byte, pad>> = take!(bin, offset, 2, "column header")

    type = ElementType.type_atom_or_nil(type_byte)

    unless type && ElementType.numeric?(type) do
      raise DecodeError,
        message: "invalid object table column type 0x#{Integer.to_string(type_byte, 16)}",
        input: bin,
        offset: offset,
        reason: {:invalid_column_type, type_byte}
    end

    elem_size = ElementType.element_size(type)
    data_offset = offset + 2 + pad
    data = take!(bin, data_offset, row_count * elem_size, "column data")

    column = %ObjectTable.Column{name: name, type: type, data: data}

    decode_columns(count - 1, row_count, bin, data_offset + row_count * elem_size, ctx, [
      column | acc
    ])
  end

  defp object_table_rows(%ObjectTable{row_count: row_count, columns: columns}, ctx) do
    col_names = Enum.map(columns, & &1.name)

    values =
      Enum.map(columns, fn %ObjectTable.Column{type: type, data: data} ->
        ElementType.buffer_to_list(type, data)
      end)

    for i <- 0..(row_count - 1) do
      Enum.zip(col_names, Enum.map(values, &Enum.at(&1, i)))
      |> build_object(ctx)
    end
  end

  # ── Schema mode ─────────────────────────────────────────────────────────────

  defp decode_schema_body(bin, offset, schema, ctx, depth) do
    <<_schema_id::32-little>> = take!(bin, offset, 4, "schema id")
    {values, _offset} = decode_schema_fields(bin, offset + 4, schema.fields, ctx, depth, [])
    names = Enum.map(schema.fields, & &1.name)

    case ctx.keys do
      :strings ->
        Map.new(Enum.zip(names, values))

      keys ->
        Map.new(Enum.zip(names, values), fn {name, value} -> {convert_key(name, keys), value} end)
    end
  end

  defp decode_schema_fields(_bin, offset, [], _ctx, _depth, acc),
    do: {:lists.reverse(acc), offset}

  defp decode_schema_fields(bin, offset, [%{type: type} | rest], ctx, depth, acc) do
    {value, offset} = decode_schema_field(bin, offset, type, ctx, depth)
    decode_schema_fields(bin, offset, rest, ctx, depth, [value | acc])
  end

  defp decode_schema_field(bin, offset, type, _ctx, _depth)
       when type in [:int8, :uint8, :int16, :uint16, :int32, :uint32, :int64, :uint64] do
    {value, _rest} =
      ElementType.decode_raw(type, take!(bin, offset, ElementType.size(type), "schema field"))

    {value, offset + ElementType.size(type)}
  end

  defp decode_schema_field(bin, offset, type, _ctx, _depth) when type in [:float32, :float64] do
    {value, _rest} =
      ElementType.decode_raw(type, take!(bin, offset, ElementType.size(type), "schema field"))

    {value, offset + ElementType.size(type)}
  end

  defp decode_schema_field(_bin, offset, :null, _ctx, _depth), do: {nil, offset}

  defp decode_schema_field(bin, offset, :bool, _ctx, _depth) do
    <<byte>> = take!(bin, offset, 1, "schema bool field")
    {byte != 0, offset + 1}
  end

  defp decode_schema_field(bin, offset, :string, ctx, _depth) do
    decode_string_or_ref(bin, offset, ctx)
  end

  defp decode_schema_field(bin, offset, :binary, _ctx, _depth) do
    decode_binary(bin, offset)
  end

  defp decode_schema_field(bin, offset, type, ctx, depth) when type in [:array, :object] do
    decode_value(bin, offset, ctx, depth - 1)
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp byte!(bin, offset) do
    if offset < byte_size(bin) do
      :binary.at(bin, offset)
    else
      raise DecodeError,
        message: "truncated value tag",
        input: bin,
        offset: offset,
        reason: :truncated
    end
  end

  defp take!(bin, offset, len, what) do
    if offset + len <= byte_size(bin) do
      binary_part(bin, offset, len)
    else
      raise DecodeError,
        message: "truncated #{what}",
        input: bin,
        offset: offset,
        reason: :truncated
    end
  end

  defp pad_to(pos, align) when align > 0, do: rem(align - rem(pos, align), align)
end
