defmodule ToonEx.Btoon.SpecConformanceTest do
  @moduledoc """
  Conformance tests against the BTOON specification v1.0-draft:
  the §26 test vectors, §17 determinism rules, §19 decoder rules,
  §22/§23 extension skipping and §24 security validations.
  """

  use ExUnit.Case, async: true

  alias ToonEx.Btoon
  alias ToonEx.Btoon.{Dictionary, Extension, Schema}

  @magic <<0x42, 0x54, 0x4F, 0x4E, 1>>

  # ── §26.1 primitives ────────────────────────────────────────────────────────

  describe "§26.1 primitive test vectors" do
    test "encode to the exact spec bytes" do
      vectors = [
        {nil, <<@magic, 0, 0, 0, 0>>},
        {false, <<@magic, 0, 0, 0, 1>>},
        {true, <<@magic, 0, 0, 0, 2>>},
        {-32, <<@magic, 0, 0, 0, 0x20>>},
        {0, <<@magic, 0, 0, 0, 0x40>>},
        {42, <<@magic, 0, 0, 0, 0x6A>>},
        {95, <<@magic, 0, 0, 0, 0x9F>>},
        {96, <<@magic, 0, 0, 0, 0x03, 0x60, 0, 0, 0>>},
        {-33, <<@magic, 0, 0, 0, 0x03, 0xDF, 0xFF, 0xFF, 0xFF>>},
        {2_147_483_648, <<@magic, 0, 0, 0, 0x04, 0, 0, 0, 0x80, 0, 0, 0, 0>>},
        {1.5, <<@magic, 0, 0, 0, 0x05, 0, 0, 0xC0, 0x3F>>},
        {1.1, <<@magic, 0, 0, 0, 0x06, 0x9A, 0x99, 0x99, 0x99, 0x99, 0x99, 0xF1, 0x3F>>},
        {Btoon.Binary.new(<<1, 2, 3>>), <<@magic, 0, 0, 0, 0x08, 3, 0, 0, 0, 1, 2, 3>>}
      ]

      Enum.each(vectors, fn {value, expected} ->
        assert Btoon.encode!(value) == expected,
               "encoding #{inspect(value)} does not match the spec vector"

        assert Btoon.decode!(expected) == value
      end)
    end

    test "§8.2 SmallInt boundaries" do
      for value <- [-32, -1, 0, 95] do
        assert byte_size(Btoon.encode!(value)) == 9
      end

      # 96 and -33 MUST NOT use SmallInt
      assert Btoon.encode!(96) == <<@magic, 0, 0, 0, 0x03, 0x60, 0, 0, 0>>
      assert Btoon.encode!(-33) == <<@magic, 0, 0, 0, 0x03, 0xDF, 0xFF, 0xFF, 0xFF>>
    end
  end

  describe "§26.3 strings" do
    @hello <<0x68, 0x65, 0x6C, 0x6C, 0x6F>>

    test "\"hello\" with the per-message string table" do
      assert Btoon.encode!("hello") ==
               <<@magic, 0x04, 0, 0, 1, 0, 0, 0, 5, 0, 0, 0, @hello::binary, 0, 0, 0, 0x0B, 0x40>>
    end

    test "\"hello\" with the string table disabled" do
      assert Btoon.encode!("hello", string_table: :off) ==
               <<@magic, 0, 0, 0, 0x07, 5, 0, 0, 0, @hello::binary>>
    end
  end

  describe "§26.4 TypedArray" do
    test "[1, 2, 3] as int8" do
      assert Btoon.encode!([1, 2, 3]) ==
               <<@magic, 0, 0, 0, 0x0C, 0x00, 3, 0, 0, 0, 0, 1, 2, 3>>
    end
  end

  describe "§26.5 object" do
    test "an object with SmallInt and string values (age/name/Alice)" do
      assert Btoon.encode!(%{"age" => 30, "name" => "Alice"}) ==
               <<@magic, 0x04, 0, 0, 3, 0, 0, 0, 3, 0, 0, 0, "age", 4, 0, 0, 0, "name", 5, 0, 0,
                 0, "Alice", 0, 0, 0, 0, 0x0A, 2, 0, 0, 0, 0x0B, 0x40, 0x5E, 0x0B, 0x41, 0x0B,
                 0x42>>
    end
  end

  describe "§26.6 schema mode" do
    test "Player schema vector" do
      schema =
        Schema.new(100, "Player", [
          %{name: "id", type: :int32},
          %{name: "x", type: :float32},
          %{name: "y", type: :float32},
          %{name: "hp", type: :uint16}
        ])

      assert Btoon.encode!(%{"id" => 1, "x" => 1.0, "y" => 2.5, "hp" => 100}, schema: schema) ==
               <<@magic, 0x02, 0, 0, 100, 0, 0, 0, 6, 0, 0, 0, "Player", 4, 0, 0, 0, 2, 0, 0, 0,
                 "id", 0x04, 1, 0, 0, 0, "x", 0x07, 1, 0, 0, 0, "y", 0x07, 2, 0, 0, 0, "hp", 0x03,
                 0, 0, 0, 0, 100, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0x80, 0x3F, 0, 0, 0x20, 0x40, 100,
                 0>>
    end
  end

  # ── §17 narrowest lossless element type ─────────────────────────────────────

  describe "§17/§13 unsigned element type selection" do
    test "all-nonnegative values use the narrowest unsigned type when no signed type fits" do
      assert Btoon.decode!(Btoon.encode!([200])) == [200]

      {:ok, view} = Btoon.decode(Btoon.encode!([200]), typed_arrays: :views)
      assert view.type == :uint8

      {:ok, view} = Btoon.decode(Btoon.encode!([65_535]), typed_arrays: :views)
      assert view.type == :uint16

      {:ok, view} = Btoon.decode(Btoon.encode!([4_294_967_295]), typed_arrays: :views)
      assert view.type == :uint32

      # Signed preferred when both widths fit
      {:ok, view} = Btoon.decode(Btoon.encode!([100]), typed_arrays: :views)
      assert view.type == :int8

      # Negative values force signed
      {:ok, view} = Btoon.decode(Btoon.encode!([-1, 200]), typed_arrays: :views)
      assert view.type == :int16
    end

    test "uint64 columns are allowed in object tables but not typed arrays" do
      rows = [%{"c" => 18_446_744_073_709_551_615}]
      assert Btoon.decode!(Btoon.encode!(rows)) == rows

      {:ok, table} = Btoon.decode(Btoon.encode!(rows), typed_arrays: :views)
      assert hd(table.columns).type == :uint64

      assert_raise Btoon.EncodeError, fn ->
        Btoon.encode!(Btoon.TypedArray.new(:uint64, <<1::64-little>>))
      end
    end

    test "integers beyond Int64 are rejected" do
      assert_raise Btoon.EncodeError, fn ->
        Btoon.encode!(9_223_372_036_854_775_808)
      end

      assert_raise Btoon.EncodeError, fn ->
        Btoon.encode!(-9_223_372_036_854_775_809)
      end
    end
  end

  # ── §19 decoder rules ───────────────────────────────────────────────────────

  describe "§19 trailing bytes" do
    test "bytes after the body are rejected in dynamic mode" do
      good = Btoon.encode!(42)
      assert_raise Btoon.DecodeError, fn -> Btoon.decode!(good <> <<0>>) end
      assert_raise Btoon.DecodeError, fn -> Btoon.decode!(good <> "garbage") end
    end

    test "bytes after the body are rejected in schema mode" do
      schema = Schema.new(1, "S", [%{name: "v", type: :int32}])
      good = Btoon.encode!(%{"v" => 1}, schema: schema)
      assert_raise Btoon.DecodeError, fn -> Btoon.decode!(good <> <<1>>) end
    end

    test "a message that is exactly the body decodes" do
      assert Btoon.decode!(Btoon.encode!(42)) == 42
    end
  end

  # ── §22/§23 extensions ──────────────────────────────────────────────────────

  describe "§23 extension types" do
    test "known extensions round-trip" do
      ext = Extension.new(0xF0, <<1, 2, 3>>)
      assert Btoon.decode!(Btoon.encode!(ext)) == ext
      assert Btoon.decode!(Btoon.encode!(%{"e" => ext})) == %{"e" => ext}

      # Wire layout: tag + payload length + payload
      assert Btoon.encode!(ext) == <<@magic, 0, 0, 0, 0xF0, 3, 0, 0, 0, 1, 2, 3>>
    end

    test "unknown extension tags are skipped, not fatal" do
      # An array [unknown-ext(0xF7), 42] hand-encoded by a newer encoder.
      bin =
        <<@magic, 0, 0, 0, 0x09, 2, 0, 0, 0, 0xF7, 4, 0, 0, 0, 1, 2, 3, 4, 0x6A>>

      assert Btoon.decode!(bin) == [%Extension{tag: 0xF7, data: <<1, 2, 3, 4>>}, 42]
    end

    test "tags outside the extension range are errors" do
      assert_raise Btoon.DecodeError, fn ->
        Btoon.decode!(<<@magic, 0, 0, 0, 0x0E>>)
      end

      assert_raise Btoon.DecodeError, fn ->
        Btoon.decode!(<<@magic, 0, 0, 0, 0xA0>>)
      end
    end

    test "invalid extension tags are rejected" do
      assert_raise ArgumentError, fn ->
        Extension.new(0x42, <<1>>)
      end

      # A hand-built struct bypassing new/2 is caught at encode time.
      assert_raise Btoon.EncodeError, fn ->
        Btoon.encode!(%Extension{tag: 0x42, data: <<1>>})
      end
    end
  end

  # ── §24 security validations ────────────────────────────────────────────────

  describe "§24 padding validation" do
    test "typed array pad counts beyond 7 are rejected" do
      # [1, 2, 3] int8 typed array with an illegal pad length of 8.
      bin = <<@magic, 0, 0, 0, 0x0C, 0x00, 3, 0, 0, 0, 8, 0, 1, 2, 3>>

      assert_raise Btoon.DecodeError, fn -> Btoon.decode!(bin) end
    end

    test "object table pad counts beyond 7 are rejected" do
      # One column "x" (inline string), int8, pad 9.
      bin =
        <<@magic, 0, 0, 0, 0x0D, 2, 0, 0, 0, 1, 0, 0, 0, 0x07, 1, 0, 0, 0, "x", 0x00, 9, 1, 2>>

      assert_raise Btoon.DecodeError, fn -> Btoon.decode!(bin) end
    end
  end

  # ── §7.5.1 / §11 string table flags ────────────────────────────────────────

  describe "flag 0x10 (no per-message string table)" do
    test "is set automatically when the session dictionary covers all strings" do
      dict = Dictionary.new(["a", "b"])
      bin = Btoon.encode!(%{"a" => 1, "b" => 2}, dictionary: dict)

      <<@magic, flags, _::binary>> = bin
      assert Bitwise.band(flags, 0x08) != 0, "session dictionary flag expected"
      assert Bitwise.band(flags, 0x10) != 0, "no-table flag expected"
      assert Bitwise.band(flags, 0x04) == 0, "no per-message table expected"
    end

    test "is not set when a per-message table entry is needed" do
      dict = Dictionary.new(["a"])
      bin = Btoon.encode!(%{"a" => 1, "c" => 2}, dictionary: dict)

      <<@magic, flags, _::binary>> = bin
      assert Bitwise.band(flags, 0x08) != 0
      assert Bitwise.band(flags, 0x04) != 0
      assert Bitwise.band(flags, 0x10) == 0
    end

    test "is mutually exclusive with the string table flag on decode" do
      assert_raise Btoon.DecodeError, fn ->
        Btoon.decode!(<<@magic, 0x14, 0, 0, 0, 0, 0, 0, 0>>)
      end
    end
  end

  # ── §14 object table column names ───────────────────────────────────────────

  describe "§14 object table column names with a session dictionary" do
    test "names missing from the dictionary are added to the per-message table" do
      dict = Dictionary.new(["known"])
      rows = [%{"known" => 1, "extra" => 2}, %{"known" => 3, "extra" => 4}]

      bin = Btoon.encode!(rows, dictionary: dict)
      assert Btoon.decode!(bin, dictionary: dict) == rows

      <<@magic, flags, _::binary>> = bin
      assert Bitwise.band(flags, 0x08) != 0
      assert Bitwise.band(flags, 0x04) != 0, "per-message table must carry the extra name"
    end

    test "raises when the name cannot become a StringRef" do
      dict = Dictionary.new(["known"])
      rows = [%{"known" => 1, "extra" => 2}]

      assert_raise Btoon.EncodeError, fn ->
        Btoon.encode!(rows, dictionary: dict, no_string_table: true)
      end
    end
  end
end
