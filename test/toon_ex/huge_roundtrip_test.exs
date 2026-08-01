defmodule ToonEx.HugeRoundtripTest do
  @moduledoc """
  Roundtrip test for a ~100MB complex document.

  `ToonEx.Fixtures.ComplexDocs.huge_doc/0` builds a document that mixes every
  TOON array/object form at scale (flat object, tabular array with a nested
  field group, keyed-tabular object, list-format array, and a nested config
  tree). Encoded, it exceeds 100MB.

  The single test covers the full round-trip in one pass:

    1. encode produces a >100MB TOON string
    2. decode recovers a structure equal to the source (`==`)
    3. re-encoding the decoded structure is byte-identical
    4. structural spot checks confirm the data made it through intact
  """
  use ExUnit.Case, async: true

  alias ToonEx.Fixtures.ComplexDocs

  @min_bytes 100_000_000

  test "100MB complex document round-trips through encode and decode" do
    doc = ComplexDocs.huge_doc()

    enc = ToonEx.encode!(doc)
    assert byte_size(enc) > @min_bytes, "expected TOON output over 100MB"

    dec = ToonEx.decode!(enc)
    assert dec == doc

    # Strongest roundtrip guarantee: re-encoding the decoded document is
    # byte-identical to the first encoding.
    assert ToonEx.encode!(dec) == enc

    # Structural spot checks across every format in the document.
    assert map_size(dec["catalog"]) == 115_000
    assert dec["catalog"]["sku_1"] == doc["catalog"]["sku_1"]
    assert dec["catalog"]["sku_115_000"] == doc["catalog"]["sku_115_000"]

    assert length(dec["records"]) == 30_000
    first_record = hd(dec["records"])
    assert first_record["id"] == 1
    assert first_record["score"] == 1.25
    assert first_record["active"] == false
    assert first_record["region"] == %{"code" => "US", "name" => "Region 1"}
    assert List.last(dec["records"])["id"] == 30_000

    assert map_size(dec["index"]) == 10_000
    assert dec["index"]["id_1"] == %{"sku" => "sku_1", "loc" => "rack-b", "qty" => 1}
    assert dec["index"]["id_10000"]["qty"] == rem(10_000, 1000)

    assert length(dec["events"]) == 5_000
    assert Enum.filter(dec["events"], &(&1["type"] == "metric")) |> length() == 1_250
    assert Enum.filter(dec["events"], &(&1["type"] == "deploy")) |> length() == 1_250
    assert Enum.find(dec["events"], &(&1["type"] == "deploy"))["env"] in ["staging", "prod"]

    assert dec["config"]["features"]["beta"]["chat"] == true
    assert dec["config"]["logging"]["sinks"] == ["stdout", "file"]
  end
end
