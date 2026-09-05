defmodule ToonEx.Btoon do
  @moduledoc """
  BTOON — a compact binary codec for the TOON data model.

  BTOON is the binary transport encoding of the TOON data model (see the
  BTOON specification in repo [BTOON](https://github.com/ohhi-vn/btoon_specs)). Unlike TOON's text form it
  is optimized for CPU cost first and wire size second:

    * a fixed 8-byte envelope (`"BTON"` magic, version, flags) with an
      optional per-message string table, optional embedded schema and an
      8-byte-aligned body;
    * inline `SmallInt` values and fixed-width little-endian integers and
      floats (never varints);
    * strings deduplicated against a session dictionary and per-message
      string table via `StringRef`;
    * homogeneous numeric lists as `TypedArray` and homogeneous object lists
      as columnar `ObjectTable`, both padded so decoders can expose zero-copy
      views;
    * optional schema mode that drops keys and tags entirely.

  Every input maps to exactly one byte sequence (deterministic encoding).

  ## Quick start

      iex> bin = ToonEx.Btoon.encode!(%{"name" => "Alice", "age" => 30})
      iex> ToonEx.Btoon.decode!(bin)
      %{"name" => "Alice", "age" => 30}

  ## Encodable values

  `nil`, booleans, integers, floats, strings (binaries), `ToonEx.Btoon.Binary`
  blobs, `ToonEx.Btoon.TypedArray`, `ToonEx.Btoon.ObjectTable`, lists and maps with
  string keys. Map keys are sorted during encoding, so field order is
  deterministic but not preserved.

  ## Options

  See `ToonEx.Btoon.Encode.Options` and `ToonEx.Btoon.Decode.Options` for the accepted
  encode/decode options.
  """

  alias ToonEx.Btoon

  @doc """
  Encodes data to the BTOON binary format.

  Returns `{:ok, binary}` or `{:error, Btoon.EncodeError.t()}`.
  """
  @spec encode(Btoon.Types.encodable(), keyword()) ::
          {:ok, binary()} | {:error, Btoon.EncodeError.t()}
  def encode(data, opts \\ []), do: Btoon.Encode.encode(data, opts)

  @doc """
  Encodes data to the BTOON binary format, raising `Btoon.EncodeError` on
  error.
  """
  @spec encode!(Btoon.Types.encodable(), keyword()) :: binary()
  def encode!(data, opts \\ []), do: Btoon.Encode.encode!(data, opts)

  @doc """
  Encodes data to BTOON iodata without flattening to a single binary, raising
  `Btoon.EncodeError` on error.

  Returns an iodata structure suitable for passing directly to IO functions or
  `IO.iodata_to_binary/1`. This avoids an intermediate flattening step when the
  caller intends to write the result to a socket or file.

  ## Examples

      iex> iodata = Btoon.encode_to_iodata!(%{"a" => [1, 2]})
      iex> IO.iodata_to_binary(iodata) == Btoon.encode!(%{"a" => [1, 2]})
      true
  """
  @spec encode_to_iodata!(Btoon.Types.encodable(), keyword()) :: iodata()
  def encode_to_iodata!(data, opts \\ []), do: Btoon.Encode.encode_to_iodata!(data, opts)

  @doc """
  Decodes a BTOON binary.

  Returns `{:ok, value}` or `{:error, Btoon.DecodeError.t()}`.
  """
  @spec decode(binary(), keyword()) :: {:ok, term()} | {:error, Btoon.DecodeError.t()}
  def decode(binary, opts \\ []), do: Btoon.Decode.decode(binary, opts)

  @doc """
  Decodes a BTOON binary, raising `Btoon.DecodeError` on error.
  """
  @spec decode!(binary(), keyword()) :: term()
  def decode!(binary, opts \\ []), do: Btoon.Decode.decode!(binary, opts)
end
