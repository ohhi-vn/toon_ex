defmodule ToonEx.Btoon.SchemaCompiler do
  @moduledoc """
  Compiles a BTOON schema into a specialized encoder function.

  This eliminates runtime type dispatch and field name lookups during encoding.
  """

  alias ToonEx.Btoon.{
    Binary,
    Constants,
    ElementType,
    EncodeError,
    ObjectTable,
    Schema,
    TypedArray
  }

  @compile {:inline, compile: 1, encode_schema_body: 3}

  @typedoc "Compiled schema with precomputed encoder functions."
  @type compiled_schema :: %{
          id: integer(),
          name: String.t(),
          fields: [
            %{
              name: String.t(),
              type: Btoon.Types.element_type(),
              encoder: (term(), Btoon.Encode.Ctx ->
                          {iodata(), non_neg_integer(), Btoon.Encode.Ctx}),
              size: non_neg_integer()
            }
          ]
        }

  @doc """
  Compiles a schema into a specialized encoder.

  Returns a map with the schema ID, name, and a list of fields with their
  precomputed encoder functions.
  """
  @spec compile(Schema.t()) :: compiled_schema()
  def compile(%Schema{id: id, name: name, fields: fields}) do
    compiled_fields =
      Enum.map(fields, fn %{name: name, type: type} ->
        encoder = compile_field_encoder(type)

        size =
          if type in [
               :int8,
               :uint8,
               :int16,
               :uint16,
               :int32,
               :uint32,
               :int64,
               :uint64,
               :float32,
               :float64,
               :bool
             ],
             do: ElementType.size(type),
             else: 0

        %{name: name, type: type, encoder: encoder, size: size}
      end)

    %{
      id: id,
      name: name,
      fields: compiled_fields
    }
  end

  # Helper to get config from the new flat Ctx structure
  defp get_config(ctx, key) do
    case key do
      :dictionary -> ctx.dictionary
      :string_table -> ctx.string_table
      :typed_arrays -> ctx.typed_arrays
      :object_tables -> ctx.object_tables
      _ -> raise ArgumentError, "unknown config key: #{inspect(key)}"
    end
  end

  @doc """
  Encodes a schema body using a compiled schema.

  This is significantly faster than the generic schema encoder because it:
  - Precomputes encoder functions for each field type
  - Eliminates Map.fetch for field names (uses ordered list)
  - Avoids runtime type dispatch
  """
  @spec encode_schema_body(compiled_schema(), map(), Btoon.Encode.Ctx) ::
          {iodata(), non_neg_integer(), Btoon.Encode.Ctx}
  def encode_schema_body(compiled, map, ctx) do
    fields = compiled.fields
    id = compiled.id

    {rev_iodata, size, ctx} =
      do_encode_compiled_fields(fields, map, ctx.schema_id_size, ctx, [], 0)

    id_iodata = if ctx.schema_id_size == 2, do: <<id::16-little>>, else: <<id::32-little>>
    {[id_iodata | :lists.reverse(rev_iodata)], ctx.schema_id_size + size, ctx}
  end

  defp do_encode_compiled_fields([], _map, _offset, ctx, acc, size), do: {acc, size, ctx}

  defp do_encode_compiled_fields([field | rest], map, offset, ctx, acc, size) do
    # Direct map access - fields are in order, no need to look up by name repeatedly
    value = Map.fetch!(map, field.name)
    {field_iodata, field_size, ctx} = field.encoder.(value, ctx)

    do_encode_compiled_fields(
      rest,
      map,
      offset + field_size,
      ctx,
      [field_iodata | acc],
      size + field_size
    )
  end

  # Shared integer encoding with range checking
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

  # Compile encoder functions for each type
  defp compile_field_encoder(:int8) do
    fn value, ctx -> encode_fixed_int(:int8, value, ctx) end
  end

  defp compile_field_encoder(:uint8) do
    fn value, ctx -> encode_fixed_int(:uint8, value, ctx) end
  end

  defp compile_field_encoder(:int16) do
    fn value, ctx -> encode_fixed_int(:int16, value, ctx) end
  end

  defp compile_field_encoder(:uint16) do
    fn value, ctx -> encode_fixed_int(:uint16, value, ctx) end
  end

  defp compile_field_encoder(:int32) do
    fn value, ctx -> encode_fixed_int(:int32, value, ctx) end
  end

  defp compile_field_encoder(:uint32) do
    fn value, ctx -> encode_fixed_int(:uint32, value, ctx) end
  end

  defp compile_field_encoder(:int64) do
    fn value, ctx -> encode_fixed_int(:int64, value, ctx) end
  end

  defp compile_field_encoder(:uint64) do
    fn value, ctx -> encode_fixed_int(:uint64, value, ctx) end
  end

  defp compile_field_encoder(:float32) do
    fn value, ctx ->
      if is_float(value) do
        {ElementType.encode_raw(:float32, value), 4, ctx}
      else
        raise EncodeError, message: "schema field float32 requires a float", value: value
      end
    end
  end

  defp compile_field_encoder(:float64) do
    fn value, ctx ->
      if is_float(value) do
        {ElementType.encode_raw(:float64, value), 8, ctx}
      else
        raise EncodeError, message: "schema field float64 requires a float", value: value
      end
    end
  end

  defp compile_field_encoder(:null) do
    fn nil, ctx -> {<<>>, 0, ctx} end
  end

  defp compile_field_encoder(:bool) do
    fn value, ctx ->
      if is_boolean(value) do
        {<<if(value, do: 1, else: 0)>>, 1, ctx}
      else
        raise EncodeError, message: "bool schema field requires a boolean", value: value
      end
    end
  end

  defp compile_field_encoder(:string) do
    fn value, ctx ->
      if is_binary(value) do
        encode_string(value, ctx)
      else
        raise EncodeError, message: "string schema field requires a binary", value: value
      end
    end
  end

  defp compile_field_encoder(:binary) do
    fn value, ctx ->
      data =
        if Map.has_key?(value, :__struct__) and value.__struct__ == Binary do
          value.data
        else
          value
        end

      {iodata, size} = encode_binary(data)
      {iodata, size, ctx}
    end
  end

  defp compile_field_encoder(:array) do
    fn value, ctx ->
      encode_value(value, 0, ctx)
    end
  end

  defp compile_field_encoder(:object) do
    fn value, ctx ->
      encode_value(value, 0, ctx)
    end
  end

  # Internal helper functions to avoid calling private functions from Encode module
  defp encode_string(string, ctx) do
    case Map.fetch(get_config(ctx, :dictionary), string) do
      {:ok, id} ->
        encode_string_ref_tuple(id, ctx)

      :error ->
        if get_config(ctx, :string_table) == :off do
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

  defp encode_binary(data) do
    {<<Constants.tag_binary(), byte_size(data)::32-little, data::binary>>, 5 + byte_size(data)}
  end

  defp encode_value(value, _offset, ctx) do
    cond do
      value == nil -> {<<Constants.tag_null()>>, 1, ctx}
      value == false -> {<<Constants.tag_false()>>, 1, ctx}
      value == true -> {<<Constants.tag_true()>>, 1, ctx}
      is_integer(value) -> encode_int(value, ctx)
      is_float(value) -> encode_float(value, ctx)
      is_binary(value) -> encode_string(value, ctx)
      is_list(value) -> encode_list(value, 0, ctx)
      is_map(value) -> encode_object(value, 0, ctx)
      is_atom(value) -> encode_string(Atom.to_string(value), ctx)
      true -> raise EncodeError, message: "cannot encode value", value: value
    end
  end

  defp encode_int(value, ctx) do
    {iodata, size} = encode_int_value(value)
    {iodata, size, ctx}
  end

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

  defp encode_float(value, ctx) do
    if ElementType.f32_exact?(value) do
      {<<Constants.tag_float32(), value::32-little-float>>, 5, ctx}
    else
      {<<Constants.tag_float64(), value::64-little-float>>, 9, ctx}
    end
  end

  defp encode_list(list, _offset, ctx) do
    if get_config(ctx, :typed_arrays) do
      case ElementType.detect_type(list) do
        {:ok, type} ->
          encode_typed_array(
            %TypedArray{type: type, data: ElementType.list_to_buffer(type, list)},
            0,
            ctx
          )

        :error ->
          encode_list_fallback(list, 0, ctx)
      end
    else
      encode_list_fallback(list, 0, ctx)
    end
  end

  defp encode_list_fallback(list, _offset, ctx) do
    if get_config(ctx, :object_tables) do
      case ElementType.detect_object_table(list) do
        {:ok, names, types, columns_data} ->
          columns =
            Enum.zip([names, types, columns_data])
            |> Enum.map(fn {name, type, values} ->
              %ObjectTable.Column{
                name: name,
                type: type,
                data: ElementType.list_to_buffer(type, values)
              }
            end)

          encode_object_table(
            %ObjectTable{row_count: length(list), columns: columns},
            0,
            ctx
          )

        :error ->
          encode_array_general(list, 0, ctx)
      end
    else
      encode_array_general(list, 0, ctx)
    end
  end

  defp encode_array_general(list, _offset, ctx) do
    {rev_iodata, size, ctx} = do_encode_items(list, 5, ctx, [], 0)

    {[<<Constants.tag_array(), length(list)::32-little>> | :lists.reverse(rev_iodata)], 5 + size,
     ctx}
  end

  defp do_encode_items([], _offset, ctx, acc, size), do: {acc, size, ctx}

  defp do_encode_items([item | rest], offset, ctx, acc, size) do
    {iodata, item_size, ctx} = encode_value(item, offset, ctx)
    do_encode_items(rest, offset + item_size, ctx, [iodata | acc], size + item_size)
  end

  defp encode_object(map, _offset, ctx) do
    keys = map |> Map.keys()

    if all_binary_keys?(keys) do
      sorted = Enum.sort(keys)
      {rev_iodata, size, ctx} = do_encode_pairs(sorted, map, 5, ctx, [], 0)

      {[
         <<Constants.tag_object(), length(sorted)::32-little>> | :lists.reverse(rev_iodata)
       ], 5 + size, ctx}
    else
      key_map = Enum.reduce(map, %{}, fn {k, _v}, acc -> Map.put(acc, to_string(k), k) end)
      sorted = key_map |> Map.keys() |> Enum.sort()

      {rev_iodata, size, ctx} =
        do_encode_pairs(sorted, key_map, map, 5, ctx, [], 0)

      {[
         <<Constants.tag_object(), length(sorted)::32-little>> | :lists.reverse(rev_iodata)
       ], 5 + size, ctx}
    end
  end

  defp all_binary_keys?(keys), do: Enum.all?(keys, &is_binary/1)

  defp do_encode_pairs([], _map, _offset, ctx, acc, size), do: {acc, size, ctx}

  defp do_encode_pairs([key | rest], map, offset, ctx, acc, size) do
    {key_iodata, key_size, ctx} = encode_string(key, ctx)

    {value_iodata, value_size, ctx} =
      encode_value(Map.fetch!(map, key), offset + key_size, ctx)

    do_encode_pairs(
      rest,
      map,
      offset + key_size + value_size,
      ctx,
      [value_iodata, key_iodata | acc],
      size + key_size + value_size
    )
  end

  defp do_encode_pairs([], _key_map, _map, _offset, ctx, acc, size), do: {acc, size, ctx}

  defp do_encode_pairs([key | rest], key_map, map, offset, ctx, acc, size) do
    {key_iodata, key_size, ctx} = encode_string(key, ctx)

    {value_iodata, value_size, ctx} =
      encode_value(Map.fetch!(map, Map.fetch!(key_map, key)), offset + key_size, ctx)

    do_encode_pairs(
      rest,
      key_map,
      map,
      offset + key_size + value_size,
      ctx,
      [value_iodata, key_iodata | acc],
      size + key_size + value_size
    )
  end

  defp encode_typed_array(%TypedArray{type: type, data: data}, _offset, ctx) do
    elem_size = ElementType.element_size(type)
    count = div(byte_size(data), elem_size)

    iodata =
      [
        <<Constants.tag_typed_array(), ElementType.type_byte(type), count::32-little, 0>>,
        data
      ]

    {iodata, 7 + byte_size(data), ctx}
  end

  defp encode_object_table(%ObjectTable{row_count: row_count, columns: columns}, _offset, ctx) do
    {col_iodata, col_size, ctx} = do_encode_columns(columns, row_count, 9, ctx, [], 0)

    {[
       <<Constants.tag_object_table(), row_count::32-little, length(columns)::32-little>>,
       col_iodata
     ], 9 + col_size, ctx}
  end

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

    column_iodata = [
      name_iodata,
      <<ElementType.type_byte(column.type)>>,
      <<0>>,
      column.data
    ]

    column_size = name_size + 1 + 1 + data_size

    do_encode_columns(
      rest,
      row_count,
      offset + column_size,
      ctx,
      [column_iodata | acc],
      size + column_size
    )
  end

  defp encode_string_ref(id) do
    {iodata, size} = encode_int_value(id)
    {[<<Constants.tag_string_ref()>> | iodata], size + 1}
  end

  defp encode_string_ref_tuple(id, ctx) do
    {iodata, size} = encode_string_ref(id)
    {iodata, size, ctx}
  end

  defp update_table(%ToonEx.Btoon.Encode.Ctx{} = ctx, string, id) do
    %ToonEx.Btoon.Encode.Ctx{
      ctx
      | table_ids: Map.put(ctx.table_ids, string, id),
        table_rev: [string | ctx.table_rev],
        next_table_id: id + 1
    }
  end
end
