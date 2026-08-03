defmodule ToonEx.Btoon.Constants do
  @moduledoc """
  Binary constants for the BTOON wire format.

  BTOON is the binary transport encoding of the TOON data model (see
  `Btoon`). This module defines the byte-level constants: the envelope
  magic/version, flag bits, value type tags and typed-array / schema
  element type selectors.

  ## Envelope

      +------------------+
      | Magic "BTON"     |  4 bytes
      +------------------+
      | Version          |  1 byte
      +------------------+
      | Flags            |  1 byte
      +------------------+
      | Reserved         |  2 bytes (MUST be zero)
      +------------------+
      | String Table     |  variable, zero-padded to a multiple of 8 bytes
      +------------------+
      | Schema           |  variable (only when the schema flag is set)
      +------------------+
      | Body             |  variable, 8-byte aligned
      +------------------+

  ## Flags

      bit0 (0x01) reserved
      bit1 (0x02) schema included
      bit2 (0x04) string table present
      bit3 (0x08) session dictionary active
      bit4 (0x10) no per-message string table
      bit5 (0x20) schema ID is UInt16
      bits6-7      reserved
  """

  # ── Envelope ────────────────────────────────────────────────────────────────

  @magic <<0x42, 0x54, 0x4F, 0x4E>>

  @version 0x01

  @header_size 8

  @flag_schema 0x02
  @flag_string_table 0x04
  @flag_session_dictionary 0x08
  @flag_no_string_table 0x10
  @flag_schema_id_uint16 0x20

  @reserved 0x0000

  # ── Value type tags ─────────────────────────────────────────────────────────

  @tag_null 0x00
  @tag_false 0x01
  @tag_true 0x02
  @tag_int32 0x03
  @tag_int64 0x04
  @tag_float32 0x05
  @tag_float64 0x06
  @tag_string 0x07
  @tag_binary 0x08
  @tag_array 0x09
  @tag_object 0x0A
  @tag_string_ref 0x0B
  @tag_typed_array 0x0C
  @tag_object_table 0x0D

  # ── SmallInt ─────────────────────────────────────────────────────────────────

  # Inline SmallInt: a single byte 0x20..0x9F whose value is `byte - 64`,
  # covering the range -32..95 with one read and no payload fetch.
  @smallint_min -32
  @smallint_max 95
  @smallint_bias 64
  @smallint_first 0x20
  @smallint_last 0x9F

  # ── Element type selectors ──────────────────────────────────────────────────

  # Shared by TypedArray (0x00..0x08) and Schema fields (0x00..0x0F).
  @element_int8 0x00
  @element_uint8 0x01
  @element_int16 0x02
  @element_uint16 0x03
  @element_int32 0x04
  @element_uint32 0x05
  @element_int64 0x06
  @element_float32 0x07
  @element_float64 0x08
  @element_null 0x09
  @element_bool 0x0A
  @element_string 0x0B
  @element_binary 0x0C
  @element_array 0x0D
  @element_object 0x0E
  @element_uint64 0x0F

  # ── Int32 range bounds ──────────────────────────────────────────────────────

  @int32_min -2_147_483_648
  @int32_max 2_147_483_647

  @compile {:inline,
            magic: 0,
            version: 0,
            header_size: 0,
            flag_schema: 0,
            flag_string_table: 0,
            flag_session_dictionary: 0,
            flag_no_string_table: 0,
            flag_schema_id_uint16: 0,
            reserved: 0,
            tag_null: 0,
            tag_false: 0,
            tag_true: 0,
            tag_int32: 0,
            tag_int64: 0,
            tag_float32: 0,
            tag_float64: 0,
            tag_string: 0,
            tag_binary: 0,
            tag_array: 0,
            tag_object: 0,
            tag_string_ref: 0,
            tag_typed_array: 0,
            tag_object_table: 0,
            smallint_min: 0,
            smallint_max: 0,
            smallint_bias: 0,
            smallint_first: 0,
            smallint_last: 0,
            element_int8: 0,
            element_uint8: 0,
            element_int16: 0,
            element_uint16: 0,
            element_int32: 0,
            element_uint32: 0,
            element_int64: 0,
            element_float32: 0,
            element_float64: 0,
            element_null: 0,
            element_bool: 0,
            element_string: 0,
            element_binary: 0,
            element_array: 0,
            element_object: 0,
            element_uint64: 0,
            int32_min: 0,
            int32_max: 0}

  def magic, do: @magic
  def version, do: @version
  def header_size, do: @header_size

  def flag_schema, do: @flag_schema
  def flag_string_table, do: @flag_string_table
  def flag_session_dictionary, do: @flag_session_dictionary
  def flag_no_string_table, do: @flag_no_string_table
  def flag_schema_id_uint16, do: @flag_schema_id_uint16
  def reserved, do: @reserved

  def tag_null, do: @tag_null
  def tag_false, do: @tag_false
  def tag_true, do: @tag_true
  def tag_int32, do: @tag_int32
  def tag_int64, do: @tag_int64
  def tag_float32, do: @tag_float32
  def tag_float64, do: @tag_float64
  def tag_string, do: @tag_string
  def tag_binary, do: @tag_binary
  def tag_array, do: @tag_array
  def tag_object, do: @tag_object
  def tag_string_ref, do: @tag_string_ref
  def tag_typed_array, do: @tag_typed_array
  def tag_object_table, do: @tag_object_table

  def smallint_min, do: @smallint_min
  def smallint_max, do: @smallint_max
  def smallint_bias, do: @smallint_bias
  def smallint_first, do: @smallint_first
  def smallint_last, do: @smallint_last

  def element_int8, do: @element_int8
  def element_uint8, do: @element_uint8
  def element_int16, do: @element_int16
  def element_uint16, do: @element_uint16
  def element_int32, do: @element_int32
  def element_uint32, do: @element_uint32
  def element_int64, do: @element_int64
  def element_float32, do: @element_float32
  def element_float64, do: @element_float64
  def element_null, do: @element_null
  def element_bool, do: @element_bool
  def element_string, do: @element_string
  def element_binary, do: @element_binary
  def element_array, do: @element_array
  def element_object, do: @element_object
  def element_uint64, do: @element_uint64

  def int32_min, do: @int32_min
  def int32_max, do: @int32_max

  @doc """
  Returns the type tag for a BTOON primitive value tag.
  """
  @spec type_tag(atom()) :: byte()
  def type_tag(:null), do: @tag_null
  def type_tag(false), do: @tag_false
  def type_tag(true), do: @tag_true
  def type_tag(:int32), do: @tag_int32
  def type_tag(:int64), do: @tag_int64
  def type_tag(:float32), do: @tag_float32
  def type_tag(:float64), do: @tag_float64
  def type_tag(:string), do: @tag_string
  def type_tag(:binary), do: @tag_binary
  def type_tag(:array), do: @tag_array
  def type_tag(:object), do: @tag_object
  def type_tag(:string_ref), do: @tag_string_ref
  def type_tag(:typed_array), do: @tag_typed_array
  def type_tag(:object_table), do: @tag_object_table
end
