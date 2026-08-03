defmodule ToonEx.Btoon.Encode do
  @moduledoc """
  BTOON encoder.

  Encodes the BTOON data model (`ToonEx.Btoon.Types.encodable/0`) into the binary
  wire format defined by the BTOON specification:

    * Envelope: `"BTON"` magic, version, flags, reserved, optional string
      table, optional embedded schema, then an 8-byte-aligned body.
    * Value tags (`Btoon.Constants`) with inline `SmallInt` for integers in
      `-32..95` and fixed-width little-endian integers/floats otherwise.
    * Strings deduplicated against a session dictionary and a per-message
      string table via `StringRef`.
    * Homogeneous numeric lists encoded as `TypedArray` and homogeneous
      object lists as columnar `ObjectTable`, both with alignment padding
      for zero-copy decoders.
    * Optional schema mode emitting `SchemaID` + tagless fixed-width values.

  ## Determinism

  Every input maps to exactly one byte sequence: map keys are sorted, strings
  are added to the per-message table in first-encounter order, and numeric
  lists use `Btoon.ElementType.detect_type/1` to pick a single legal type.

  ## API

      iex> Btoon.Encode.encode!(%{"name" => "Alice", "age" => 30})
      <<66, 84, 79, 78, 1, 4, 0, 0, 3, 0, 0, 0, 3, 0, 0, 0, 97, 103, 101, 4, 0,
        0, 0, 110, 97, 109, 101, 5, 0, 0, 0, 65, 108, 105, 99, 101, 0, 0, 0, 0, 10,
        2, 0, 0, 0, 11, 64, 94, 11, 65, 11, 66>>
  """

  alias ToonEx.Btoon
  alias ToonEx.Btoon.{Constants, ElementType, EncodeError, Schema}
  alias ToonEx.Btoon.Encode.Options
  alias ToonEx.Btoon.SchemaCompiler

  @compile {:inline,
            pad_to: 2,
            zeroes: 1,
            encode_int_value: 1,
            encode_binary: 1,
            encode_string_ref: 1,
            encode_string_ref_tuple: 2,
            encode_string: 2,
            encode_int: 2,
            encode_value: 3,
            do_encode_items: 6,
            do_encode_pairs: 5,
            do_encode_columns: 6,
            do_encode_fields: 6,
            encode_field: 4,
            encode_fixed_int: 3}

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  Encodes data to the BTOON binary format.

  Returns `{:ok, binary}` or `{:error, Btoon.EncodeError.t()}`.
  """
  @spec encode(Btoon.Types.encodable(), keyword()) ::
          {:ok, binary()} | {:error, Btoon.EncodeError.t()}
  def encode(data, opts \\ []) do
    case Options.validate(opts) do
      {:ok, validated} ->
        try do
          {:ok, do_encode(data, validated)}
        rescue
          e in EncodeError -> {:error, e}
          e -> {:error, EncodeError.exception(message: Exception.message(e), value: data)}
        end

      {:error, message} ->
        {:error, EncodeError.exception(message: message)}
    end
  end

  @doc """
  Encodes data to the BTOON binary format using pre-validated options.

  Returns `{:ok, binary}` or `{:error, Btoon.EncodeError.t()}`.

  This avoids re-validating options on each call, improving performance for
  repeated encoding with the same options.
  """
  @spec encode_validated(
          Btoon.Types.encodable(),
          Btoon.Encode.Options.validated()
        ) :: {:ok, binary()} | {:error, Btoon.EncodeError.t()}
  def encode_validated(data, validated_opts) do
    {:ok, do_encode(data, validated_opts)}
  rescue
    e in EncodeError -> {:error, e}
    e -> {:error, EncodeError.exception(message: Exception.message(e), value: data)}
  end

  @doc """
  Encodes data to the BTOON binary format, raising on error.
  """
  @spec encode!(Btoon.Types.encodable(), keyword()) :: binary()
  def encode!(data, opts \\ []) do
    validated = Options.validate!(opts)
    do_encode(data, validated)
  rescue
    e in EncodeError -> reraise e, __STACKTRACE__
    e -> reraise EncodeError, [message: Exception.message(e), value: data], __STACKTRACE__
  end

  @doc """
  Encodes data to the BTOON binary format using pre-validated options, raising on error.

  This avoids re-validating options on each call, improving performance for
  repeated encoding with the same options.
  """
  @spec encode_validated!(
          Btoon.Types.encodable(),
          Btoon.Encode.Options.validated()
        ) :: binary()
  def encode_validated!(data, validated_opts) do
    do_encode(data, validated_opts)
  rescue
    e in EncodeError -> reraise e, __STACKTRACE__
    e -> reraise EncodeError, [message: Exception.message(e), value: data], __STACKTRACE__
  end

  @doc """
  Encodes data to BTOON iodata without flattening to a single binary.
  """
  @spec encode_to_iodata!(Btoon.Types.encodable(), keyword()) :: iodata()
  def encode_to_iodata!(data, opts \\ []) do
    validated = Options.validate!(opts)
    ctx = new_ctx(validated)
    {body, _size, ctx} = encode_body(data, validated, ctx)
    assemble_iodata(validated, ctx, body)
  end

  # ── Core encode pipeline ────────────────────────────────────────────────────

  defp do_encode(data, opts) do
    ctx = new_ctx(opts)
    {body, _size, ctx} = encode_body(data, opts, ctx)
    assemble(opts, ctx, body)
  end

  defp encode_body(data, %{schema: nil}, ctx), do: encode_value(data, 0, ctx)

  defp encode_body(data, %{schema: schema}, ctx) when is_map(schema) do
    encode_schema_body(schema, data, ctx)
  end

  defp encode_body(data, %{compiled_schema: compiled}, ctx) when is_map(data) do
    SchemaCompiler.encode_schema_body(compiled, data, ctx)
  end

  defp encode_body(_data, %{schema: schema}, _ctx) do
    raise EncodeError, message: "schema mode requires a map value", value: schema
  end

  # ── Assembly ────────────────────────────────────────────────────────────

  defp assemble(opts, ctx, body) do
    table_entries = :lists.reverse(ctx.table_rev)
    do_assemble(opts, table_entries, body) |> IO.iodata_to_binary()
  end

  defp assemble_iodata(opts, ctx, body) do
    table_entries = :lists.reverse(ctx.table_rev)
    do_assemble(opts, table_entries, body)
  end

  defp do_assemble(opts, table_entries, body) do
    {table_iodata, table_size} =
      if opts.no_string_table do
        {[], 0}
      else
        case table_entries do
          [] -> {[], 0}
          _ -> {build_table(table_entries), 4 + table_bytes(table_entries)}
        end
      end

    {schema_iodata, schema_size} =
      case opts.schema do
        nil ->
          {[], 0}

        schema ->
          id_size = if opts.schema_id_uint16, do: 2, else: 4
          {Schema.envelope(schema, id_size), Schema.envelope_size(schema, id_size)}
      end

    flags = compute_flags(opts, table_entries)

    header =
      <<Constants.magic()::binary, Constants.version(), flags, Constants.reserved()::16-little>>

    pos = Constants.header_size()
    pos = pos + table_size
    pad1 = pad_to(pos, 8)
    pos = pos + pad1 + schema_size
    pad2 = pad_to(pos, 8)

    [
      header,
      table_iodata,
      zeroes(pad1),
      schema_iodata,
      zeroes(pad2),
      body
    ]
  end

  defp build_table(entries) do
    [<<length(entries)::32-little>> | Enum.map(entries, &[<<byte_size(&1)::32-little>>, &1])]
  end

  defp table_bytes(entries), do: Enum.reduce(entries, 0, &(byte_size(&1) + 4 + &2))

  defp compute_flags(opts, table_entries) do
    flags =
      if opts.dictionary && Btoon.Dictionary.size(opts.dictionary) > 0 do
        Constants.flag_session_dictionary()
      else
        0
      end

    flags =
      if opts.no_string_table do
        Bitwise.bor(flags, Constants.flag_no_string_table())
      else
        if table_entries != [] do
          Bitwise.bor(flags, Constants.flag_string_table())
        else
          flags
        end
      end

    flags =
      if opts.schema do
        Bitwise.bor(flags, Constants.flag_schema())
      else
        flags
      end

    if opts.schema_id_uint16 do
      Bitwise.bor(flags, Constants.flag_schema_id_uint16())
    else
      flags
    end
  end

  # ── Context ─────────────────────────────────────────────────────────────────

  defmodule Ctx do
    @moduledoc false
    defstruct dictionary: %{},
              session_size: 0,
              string_table: :auto,
              no_string_table: false,
              schema_id_size: 4,
              typed_arrays: true,
              object_tables: true,
              table_ids: %{},
              table_rev: [],
              next_table_id: 0
  end

  defp new_ctx(opts) do
    dictionary = opts.dictionary || Btoon.Dictionary.new([])
    dict_lookup = Btoon.Dictionary.lookup(dictionary)
    session_size = Btoon.Dictionary.size(dictionary)

    %Ctx{
      dictionary: dict_lookup,
      session_size: session_size,
      string_table: opts.string_table,
      no_string_table: opts.no_string_table,
      schema_id_size: if(opts.schema_id_uint16, do: 2, else: 4),
      typed_arrays: opts.typed_arrays,
      object_tables: opts.object_tables,
      table_ids: %{},
      table_rev: [],
      next_table_id: session_size
    }
  end

  # Optimized context update - reuses the struct without creating new maps unnecessarily
  defp update_table(%Ctx{} = ctx, string, id) do
    %Ctx{
      ctx
      | table_ids: Map.put(ctx.table_ids, string, id),
        table_rev: [string | ctx.table_rev],
        next_table_id: id + 1
    }
  end

  # ── Value dispatch ──────────────────────────────────────────────────────────

  # Returns {iodata, bytes_written, ctx}. `offset` is the byte offset of the
  # value's first byte relative to the start of the body (0 at body start).

  defp encode_value(nil, _offset, ctx), do: {<<Constants.tag_null()>>, 1, ctx}
  defp encode_value(false, _offset, ctx), do: {<<Constants.tag_false()>>, 1, ctx}
  defp encode_value(true, _offset, ctx), do: {<<Constants.tag_true()>>, 1, ctx}

  defp encode_value(value, _offset, ctx) when is_integer(value), do: encode_int(value, ctx)

  defp encode_value(value, _offset, ctx) when is_float(value) do
    encode_float(value, ctx)
  end

  defp encode_value(value, _offset, ctx) when is_binary(value), do: encode_string(value, ctx)

  defp encode_value(%{__struct__: mod} = value, offset, ctx) do
    case mod do
      Btoon.Binary ->
        {iodata, size} = encode_binary(value.data)
        {iodata, size, ctx}

      Btoon.TypedArray ->
        encode_typed_array(value, offset, ctx)

      Btoon.ObjectTable ->
        encode_object_table(value, offset, ctx)

      _other ->
        {encoded, size, ctx} =
          value
          |> Btoon.Encoder.encode([])
          |> encode_value(offset, ctx)

        {encoded, size, ctx}
    end
  end

  defp encode_value(value, offset, ctx) when is_list(value) do
    encode_list(value, offset, ctx)
  end

  defp encode_value(value, offset, ctx) when is_map(value) do
    encode_object(value, offset, ctx)
  end

  defp encode_value(value, _offset, ctx) when is_atom(value) do
    encode_string(Atom.to_string(value), ctx)
  end

  defp encode_value(value, _offset, _ctx) do
    raise EncodeError, message: "cannot encode value", value: value
  end

  # ── Integers ────────────────────────────────────────────────────────────────

  defp encode_int(value, ctx) do
    {iodata, size} = encode_int_value(value)
    {iodata, size, ctx}
  end

  # Shared integer encoding: SmallInt (bare byte 0x20..0x9F), Int32, Int64.
  defp encode_int_value(value) do
    cond do
      value >= -32 and value <= 95 ->
        {<<value + 64::8>>, 1}

      value >= -2_147_483_648 and value <= 2_147_483_647 ->
        {<<Constants.tag_int32(), value::32-little-signed>>, 5}

      true ->
        {<<Constants.tag_int64(), value::64-little-signed>>, 9}
    end
  end

  # ── Floats ──────────────────────────────────────────────────────────────────

  defp encode_float(value, ctx) do
    if ElementType.f32_exact?(value) do
      {<<Constants.tag_float32(), value::32-little-float>>, 5, ctx}
    else
      {<<Constants.tag_float64(), value::64-little-float>>, 9, ctx}
    end
  end

  # ── Strings & references ────────────────────────────────────────────────────

  # Strings deduplicate against the session dictionary first, then the
  # per-message string table (when :auto). Both keys and string values use
  # this path, so a ref id identifies one entry in the combined dictionary
  # (session entries first, then per-message entries).

  defp encode_string(string, ctx) do
    case Map.fetch(ctx.dictionary, string) do
      {:ok, id} ->
        encode_string_ref_tuple(id, ctx)

      :error ->
        if ctx.no_string_table or ctx.string_table == :off do
          {<<Constants.tag_string(), byte_size(string)::32-little, string::binary>>,
           5 + byte_size(string), ctx}
        else
          case Map.fetch(ctx.table_ids, string) do
            {:ok, id} ->
              encode_string_ref_tuple(id, ctx)

            :error ->
              id = ctx.next_table_id

              ctx = update_table(ctx, string, id)

              encode_string_ref_tuple(id, ctx)
          end
        end
    end
  end

  defp encode_string_ref(id) do
    {iodata, size} = encode_int_value(id)
    {[<<Constants.tag_string_ref()>> | iodata], size + 1}
  end

  defp encode_string_ref_tuple(id, ctx) do
    {iodata, size} = encode_string_ref(id)
    {iodata, size, ctx}
  end

  defp encode_binary(data) do
    {<<Constants.tag_binary(), byte_size(data)::32-little, data::binary>>, 5 + byte_size(data)}
  end

  # ── Arrays ──────────────────────────────────────────────────────────────────

  defp encode_list(list, offset, ctx) do
    if ctx.typed_arrays do
      case ElementType.detect_type(list) do
        {:ok, type} ->
          encode_typed_array(
            %Btoon.TypedArray{type: type, data: ElementType.list_to_buffer(type, list)},
            offset,
            ctx
          )

        :error ->
          encode_list_fallback(list, offset, ctx)
      end
    else
      encode_list_fallback(list, offset, ctx)
    end
  end

  defp encode_list_fallback(list, offset, ctx) do
    if ctx.object_tables do
      case ElementType.detect_object_table(list) do
        {:ok, names, types, columns_data} ->
          columns =
            Enum.zip([names, types, columns_data])
            |> Enum.map(fn {name, type, values} ->
              %Btoon.ObjectTable.Column{
                name: name,
                type: type,
                data: ElementType.list_to_buffer(type, values)
              }
            end)

          encode_object_table(
            %Btoon.ObjectTable{row_count: length(list), columns: columns},
            offset,
            ctx
          )

        :error ->
          encode_array_general(list, offset, ctx)
      end
    else
      encode_array_general(list, offset, ctx)
    end
  end

  defp encode_array_general(list, offset, ctx) do
    {rev_iodata, count, size, ctx} = do_encode_items(list, offset + 5, ctx, [], 0, 0)

    {[<<Constants.tag_array(), count::32-little>> | :lists.reverse(rev_iodata)], 5 + size, ctx}
  end

  defp do_encode_items([], _offset, ctx, acc, count, size), do: {acc, count, size, ctx}

  defp do_encode_items([item | rest], offset, ctx, acc, count, size) do
    {iodata, item_size, ctx} = encode_value(item, offset, ctx)
    do_encode_items(rest, offset + item_size, ctx, [iodata | acc], count + 1, size + item_size)
  end

  # ── Objects ─────────────────────────────────────────────────────────────────

  defp encode_object(map, offset, ctx) do
    pairs = Map.to_list(map)

    if all_binary_keys?(pairs) do
      sorted = Enum.sort(pairs)
      {rev_iodata, size, ctx} = do_encode_pairs(sorted, offset + 5, ctx, [], 0)

      {[<<Constants.tag_object(), map_size(map)::32-little>> | :lists.reverse(rev_iodata)],
       5 + size, ctx}
    else
      # Stringify keys; later duplicates overwrite earlier ones — same semantics as before.
      stringified = Map.new(pairs, fn {k, v} -> {to_string(k), v} end)
      sorted = Enum.sort(stringified)
      {rev_iodata, size, ctx} = do_encode_pairs(sorted, offset + 5, ctx, [], 0)

      {[
         <<Constants.tag_object(), map_size(stringified)::32-little>> | :lists.reverse(rev_iodata)
       ], 5 + size, ctx}
    end
  end

  defp all_binary_keys?(pairs), do: Enum.all?(pairs, fn {k, _v} -> is_binary(k) end)

  # Replaces both do_encode_pairs/6 and do_encode_pairs/7 — one unified arity.
  defp do_encode_pairs([], _offset, ctx, acc, size), do: {acc, size, ctx}

  defp do_encode_pairs([{key, value} | rest], offset, ctx, acc, size) do
    {key_iodata, key_size, ctx} = encode_string(key, ctx)
    {value_iodata, value_size, ctx} = encode_value(value, offset + key_size, ctx)

    do_encode_pairs(
      rest,
      offset + key_size + value_size,
      ctx,
      [value_iodata, key_iodata | acc],
      size + key_size + value_size
    )
  end

  # ── Typed arrays ────────────────────────────────────────────────────────────

  defp encode_typed_array(%Btoon.TypedArray{type: type, data: data}, offset, ctx) do
    elem_size = ElementType.element_size(type)
    count = div(byte_size(data), elem_size)
    # Buffer begins at offset + 7 (tag + element type + count + pad-length byte).
    pad = pad_to(offset + 7, elem_size)

    iodata =
      [
        <<Constants.tag_typed_array(), ElementType.type_byte(type), count::32-little, pad>>,
        zeroes(pad),
        data
      ]

    {iodata, 7 + pad + byte_size(data), ctx}
  end

  # ── Object tables ───────────────────────────────────────────────────────────

  defp encode_object_table(
         %Btoon.ObjectTable{row_count: row_count, columns: columns},
         offset,
         ctx
       ) do
    # When session dictionary is active, column names MUST be StringRef (per spec §14)
    # This means they must be present in the session dictionary.
    if ctx.session_size > 0 do
      Enum.each(columns, fn column ->
        unless Map.has_key?(ctx.dictionary, column.name) do
          raise EncodeError,
            message:
              "ObjectTable column name #{inspect(column.name)} not in session dictionary; " <>
                "when session dictionary is active, all column names must be present in it",
            value: column.name
        end
      end)
    end

    {col_iodata, col_size, ctx} = do_encode_columns(columns, row_count, offset + 9, ctx, [], 0)

    {[
       <<Constants.tag_object_table(), row_count::32-little, length(columns)::32-little>>,
       col_iodata
     ], 9 + col_size, ctx}
  end

  # Each column is a name ref, element type, pad-length byte, padding and the
  # aligned raw buffer. The buffer begins at offset + name_size + 2, so padding
  # is computed to align it to the element size.
  defp do_encode_columns([], _row_count, _offset, ctx, acc, size),
    do: {:lists.reverse(acc), size, ctx}

  defp do_encode_columns([column | rest], row_count, offset, ctx, acc, size) do
    {name_iodata, name_size, ctx} = encode_string(column.name, ctx)

    unless ElementType.numeric?(column.type) do
      raise EncodeError,
        message: "object table column requires a numeric type",
        value: column.type
    end

    elem_size = ElementType.element_size(column.type)
    data_size = row_count * elem_size
    pad = pad_to(offset + name_size + 2, elem_size)

    column_iodata = [
      name_iodata,
      <<ElementType.type_byte(column.type)>>,
      <<pad>>,
      zeroes(pad),
      column.data
    ]

    column_size = name_size + 1 + 1 + pad + data_size

    do_encode_columns(
      rest,
      row_count,
      offset + column_size,
      ctx,
      [column_iodata | acc],
      size + column_size
    )
  end

  # ── Schema mode ─────────────────────────────────────────────────────────────

  defp encode_schema_body(%Schema{id: id, fields: fields}, map, ctx) do
    {rev_iodata, size, ctx} = do_encode_fields(fields, map, ctx.schema_id_size, ctx, [], 0)
    id_iodata = if ctx.schema_id_size == 2, do: <<id::16-little>>, else: <<id::32-little>>
    {[id_iodata | :lists.reverse(rev_iodata)], ctx.schema_id_size + size, ctx}
  end

  defp do_encode_fields([], _map, _offset, ctx, acc, size), do: {acc, size, ctx}

  defp do_encode_fields([%{name: name, type: type} | rest], map, offset, ctx, acc, size) do
    case Map.fetch(map, name) do
      :error ->
        raise EncodeError, message: "missing value for schema field", value: name

      {:ok, value} ->
        {field_iodata, field_size, ctx} = encode_field(type, value, offset, ctx)

        do_encode_fields(
          rest,
          map,
          offset + field_size,
          ctx,
          [field_iodata | acc],
          size + field_size
        )
    end
  end

  defp encode_field(type, value, _offset, ctx)
       when type in [:int8, :uint8, :int16, :uint16, :int32, :uint32, :int64, :uint64] do
    encode_fixed_int(type, value, ctx)
  end

  defp encode_field(type, value, _offset, ctx) when type in [:float32, :float64] do
    if is_float(value) do
      {ElementType.encode_raw(type, value), ElementType.size(type), ctx}
    else
      raise EncodeError, message: "schema field #{inspect(type)} requires a float", value: value
    end
  end

  defp encode_field(:null, nil, _offset, ctx), do: {<<>>, 0, ctx}

  defp encode_field(:null, value, _offset, _ctx) do
    raise EncodeError, message: "null schema field requires nil", value: value
  end

  defp encode_field(:bool, value, _offset, ctx) when is_boolean(value) do
    {<<if(value, do: 1, else: 0)>>, 1, ctx}
  end

  defp encode_field(:bool, value, _offset, _ctx) do
    raise EncodeError, message: "bool schema field requires a boolean", value: value
  end

  defp encode_field(:string, value, _offset, ctx) when is_binary(value),
    do: encode_string(value, ctx)

  defp encode_field(:string, value, _offset, _ctx) do
    raise EncodeError, message: "string schema field requires a binary", value: value
  end

  defp encode_field(:binary, %Btoon.Binary{data: data}, _offset, ctx) do
    {iodata, size} = encode_binary(data)
    {iodata, size, ctx}
  end

  defp encode_field(:binary, value, _offset, ctx) when is_binary(value) do
    {iodata, size} = encode_binary(value)
    {iodata, size, ctx}
  end

  defp encode_field(:array, value, offset, ctx), do: encode_value(value, offset, ctx)
  defp encode_field(:object, value, offset, ctx), do: encode_value(value, offset, ctx)

  defp encode_fixed_int(type, value, ctx) when is_integer(value) do
    {min, max} = ElementType.int_range(type)

    if value >= min and value <= max do
      {ElementType.encode_raw(type, value), ElementType.size(type), ctx}
    else
      raise EncodeError,
        message: "value out of range for schema field #{inspect(type)}",
        value: value
    end
  end

  defp encode_fixed_int(type, value, _ctx) do
    raise EncodeError, message: "schema field #{inspect(type)} requires an integer", value: value
  end

  # ── Alignment helpers ───────────────────────────────────────────────────────

  @doc false
  def pad_to(pos, align) when align > 0, do: rem(align - rem(pos, align), align)

  @doc false
  def zeroes(0), do: <<>>
  def zeroes(n) when n > 0, do: :binary.copy(<<0>>, n)
end
