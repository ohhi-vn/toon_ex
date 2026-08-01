defmodule ToonEx.ComplexDocsTest do
  @moduledoc """
  End-to-end tests for the rich documents in `ToonEx.Fixtures.ComplexDocs`.

  Each document mixes several TOON array/object forms (inline, tabular with
  nested field groups, list, keyed tabular, empty objects, atom values), so
  every test follows the layered pattern of `complex_test.exs`:

    1. encode/1 — structural spot-checks
    2. decode/1 — value-level assertions
    3. roundtrip — encode |> decode == normalize, plus option variants
    4. idempotency — decode → encode → decode is stable
    5. key_folding — folded output + expand_paths roundtrip
  """
  use ExUnit.Case, async: true

  alias ToonEx.Fixtures.ComplexDocs

  @order ComplexDocs.ecommerce_order()
  @catalog ComplexDocs.catalog()
  @sensors ComplexDocs.sensor_batch()
  @log ComplexDocs.event_log()
  @config ComplexDocs.config_tree()

  defp encode!(data, opts \\ []), do: ToonEx.encode!(data, opts)
  defp decode!(toon, opts \\ []), do: ToonEx.decode!(toon, opts)

  defp roundtrip(data, enc_opts, dec_opts) do
    toon = encode!(data, enc_opts)
    {toon, decode!(toon, dec_opts)}
  end

  defp assert_rt(data, enc_opts \\ [], dec_opts \\ []) do
    {_toon, decoded} = roundtrip(data, enc_opts, dec_opts)
    assert decoded == ToonEx.Utils.normalize(data)
  end

  # ── 1. e-commerce order ────────────────────────────────────────────────────

  describe "ecommerce order" do
    test "encodes scalar fields" do
      toon = encode!(@order)
      assert toon =~ "id: ORD-2024-0042"
      assert toon =~ "status: confirmed"
      assert toon =~ "flags[2]: expedited,gift"
    end

    test "encodes tabular items with nested attrs group" do
      toon = encode!(@order)
      assert toon =~ "items[3]{attrs{color,size},name,price,qty,sku}:"
      assert toon =~ "  black,A2,Toon Poster,9.99,2,TN-100"
      assert toon =~ "  white,350ml,Toon Mug,12.5,1,TN-101"
    end

    test "encodes nested customer and address objects" do
      toon = encode!(@order)
      assert toon =~ "customer:"
      assert toon =~ "  address:"
      assert toon =~ "    street: 1 Analytical Way"
      assert toon =~ "  email: ada@example.com"
    end

    test "encodes payment and shipping objects" do
      toon = encode!(@order)
      assert toon =~ "amount: 52.45"
      assert toon =~ "tracking: PP-88231"
      assert toon =~ "eta: 2024-08-05"
    end

    test "encodes empty metadata object" do
      assert encode!(@order) =~ "metadata:"
    end

    test "decodes scalar values" do
      decoded = decode!(encode!(@order))
      assert decoded["id"] == "ORD-2024-0042"
      assert decoded["status"] == "confirmed"
      assert decoded["flags"] == ["expedited", "gift"]
      assert decoded["metadata"] == %{}
    end

    test "decodes nested customer and address" do
      decoded = decode!(encode!(@order))
      customer = decoded["customer"]
      assert customer["name"] == "Ada Lovelace"
      assert customer["email"] == "ada@example.com"
      assert customer["address"]["street"] == "1 Analytical Way"
      assert customer["address"]["postcode"] == "EC1A 1BB"
    end

    test "decodes tabular items with nested attrs" do
      decoded = decode!(encode!(@order))
      items = decoded["items"]
      assert length(items) == 3

      poster = Enum.find(items, &(&1["sku"] == "TN-100"))
      assert poster["name"] == "Toon Poster"
      assert poster["qty"] == 2
      assert poster["price"] == 9.99
      assert poster["attrs"] == %{"size" => "A2", "color" => "black"}

      mug = Enum.find(items, &(&1["sku"] == "TN-101"))
      assert mug["attrs"] == %{"size" => "350ml", "color" => "white"}
    end

    test "decodes payment and shipping" do
      decoded = decode!(encode!(@order))
      assert decoded["payment"]["method"] == "card"
      assert decoded["payment"]["currency"] == "GBP"
      assert decoded["payment"]["amount"] == 52.45
      assert decoded["shipping"]["carrier"] == "PigeonPost"
      assert decoded["shipping"]["tracking"] == "PP-88231"
    end

    test "full roundtrip" do
      assert_rt(@order)
    end

    test "roundtrip with tab delimiter" do
      assert_rt(@order, delimiter: "\t")
    end

    test "roundtrip with pipe delimiter" do
      assert_rt(@order, delimiter: "|")
    end

    test "roundtrip with indent: 4" do
      assert_rt(@order, [indent: 4], indent_size: 4)
    end

    test "keys: :atoms decodes nested values" do
      decoded = decode!(encode!(@order), keys: :atoms)
      assert decoded[:id] == "ORD-2024-0042"
      assert decoded[:customer][:address][:city] == "London"
      # Tabular row keys and nested-group subfields stay string-keyed.
      poster = Enum.find(decoded[:items], &(&1["sku"] == "TN-100"))
      assert poster["attrs"]["color"] == "black"
    end

    test "decode → encode → decode is idempotent" do
      toon1 = encode!(@order)
      decoded1 = decode!(toon1)
      toon2 = encode!(decoded1)
      decoded2 = decode!(toon2)
      assert decoded1 == decoded2
    end
  end

  # ── 2. catalogue (keyed tabular with nested group) ─────────────────────────

  describe "catalogue" do
    test "encodes categories in keyed tabular form with nested meta group" do
      toon = encode!(@catalog)
      assert toon =~ "categories[3:]{display,items,meta{featured,sort}}:"
      assert toon =~ "  books: Books,120,true,1"
      assert toon =~ "  music: Music,84,false,2"
    end

    test "decodes category values" do
      decoded = decode!(encode!(@catalog))
      categories = decoded["categories"]
      assert length(Map.keys(categories)) == 3

      books = categories["books"]
      assert books["display"] == "Books"
      assert books["items"] == 120
      assert books["meta"] == %{"featured" => true, "sort" => 1}
      assert categories["games"]["meta"]["featured"] == true
      assert categories["music"]["meta"]["featured"] == false
    end

    test "full roundtrip" do
      assert_rt(@catalog)
    end

    test "roundtrip with pipe delimiter" do
      assert_rt(@catalog, delimiter: "|")
    end

    test "keys: :atoms decodes keyed tabular entries" do
      decoded = decode!(encode!(@catalog), keys: :atoms)
      assert decoded[:categories]["books"]["display"] == "Books"
      assert decoded[:categories]["books"]["meta"]["sort"] == 1
    end
  end

  # ── 3. sensor batch (large tabular with nested group) ─────────────────────

  describe "sensor batch" do
    test "encodes tabular header with nested reading group" do
      toon = encode!(@sensors)
      assert toon =~ "sensors[300]{id,reading{humidity,temp},room,status}:"
      assert toon =~ "  sensor-1,7,18.1,lab-b,ok"
      assert toon =~ "  sensor-300,"
    end

    test "encodes batch metadata" do
      toon = encode!(@sensors)
      assert toon =~ "batch: B-2024-08-01"
      assert toon =~ "source: edge-node-7"
    end

    test "decodes first sensor row" do
      decoded = decode!(encode!(@sensors))
      assert length(decoded["sensors"]) == 300

      first = hd(decoded["sensors"])
      assert first["id"] == "sensor-1"
      assert first["room"] == "lab-b"
      assert first["reading"] == %{"temp" => 18.1, "humidity" => 7}
      assert first["status"] == "ok"
    end

    test "decodes warn/ok status rotation" do
      decoded = decode!(encode!(@sensors))
      warn = Enum.filter(decoded["sensors"], &(&1["status"] == "warn"))
      assert length(warn) == 75
    end

    test "full roundtrip" do
      assert_rt(@sensors)
    end

    test "roundtrip with tab delimiter" do
      assert_rt(@sensors, delimiter: "\t")
    end

    test "roundtrip with indent: 8" do
      assert_rt(@sensors, [indent: 8], indent_size: 8)
    end

    test "custom-sized batch roundtrips" do
      assert_rt(ComplexDocs.sensor_batch(7))
    end
  end

  # ── 4. event log (large mixed list array) ──────────────────────────────────

  describe "event log" do
    test "encodes in list format" do
      toon = encode!(@log)
      assert toon =~ "[200]:"
      assert toon =~ "type: error"
      assert toon =~ "type: login"
      refute toon =~ "]{"
    end

    test "decodes mixed item shapes" do
      decoded = decode!(encode!(@log))
      assert length(decoded) == 200

      error = Enum.find(decoded, &(&1["type"] == "error"))
      assert error["code"] == 500
      assert error["meta"] == %{"retry" => false}

      login = Enum.find(decoded, &(&1["type"] == "login"))
      assert login["success"] == true

      metric = Enum.find(decoded, &(&1["type"] == "metric"))
      assert is_float(metric["value"])
      assert metric["name"] == "latency_ms"
    end

    test "full roundtrip" do
      assert_rt(@log)
    end

    test "roundtrip with pipe delimiter" do
      assert_rt(@log, delimiter: "|")
    end

    test "decode → encode → decode is idempotent" do
      toon1 = encode!(@log)
      decoded1 = decode!(toon1)
      toon2 = encode!(decoded1)
      decoded2 = decode!(toon2)
      assert decoded1 == decoded2
    end
  end

  # ── 5. config tree (deep configuration) ────────────────────────────────────

  describe "config tree" do
    test "encodes nested objects and inline array" do
      toon = encode!(@config)
      assert toon =~ "database:"
      assert toon =~ "  pool:"
      assert toon =~ "    size: 10"
      assert toon =~ "sinks[2]: stdout,file"
      assert toon =~ ~s(url: "postgres://localhost/toon")
      assert toon =~ ~s(min_version: "1.2")
    end

    test "decodes nested values" do
      decoded = decode!(encode!(@config))
      assert decoded["server"]["host"] == "0.0.0.0"
      assert decoded["server"]["tls"] == %{"enabled" => true, "min_version" => "1.2"}
      assert decoded["database"]["pool"] == %{"size" => 10, "idle_timeout" => 30}
      assert decoded["database"]["read_replicas"] == 2
      assert decoded["features"]["beta"]["chat"] == true
      assert decoded["logging"]["sinks"] == ["stdout", "file"]
    end

    test "full roundtrip" do
      assert_rt(@config)
    end

    test "roundtrip with tab delimiter" do
      assert_rt(@config, delimiter: "\t")
    end
  end

  # ── 6. key_folding on the config tree ──────────────────────────────────────

  describe "key_folding" do
    test "folds single-key chains into dotted paths" do
      toon = encode!(@config, key_folding: :safe)
      assert toon =~ "features.beta:"
      assert toon =~ "  chat: true"
    end

    test "folded output decodes back to the same tree via expand_paths" do
      folded = encode!(@config, key_folding: :safe)
      expanded = decode!(folded, expand_paths: :safe)
      assert expanded == ToonEx.Utils.normalize(@config)
    end

    test "folding a single-key chain down to a leaf" do
      chain = %{"a" => %{"b" => %{"c" => %{"d" => 42}}}}
      assert encode!(chain, key_folding: :safe) == "a.b.c.d: 42"

      folded = encode!(chain, key_folding: :safe)
      assert decode!(folded, expand_paths: :safe) == %{"a" => %{"b" => %{"c" => %{"d" => 42}}}}
    end

    test "flatten_depth caps how deep folding descends" do
      chain = %{"a" => %{"b" => %{"c" => %{"d" => 42}}}}

      assert encode!(chain, key_folding: :safe, flatten_depth: 1) ==
               "a:\n  b:\n    c:\n      d: 42"

      assert encode!(chain, key_folding: :safe, flatten_depth: 2) == "a.b:\n  c:\n    d: 42"
    end

    test "key_folding off leaves nested objects untouched" do
      chain = %{"a" => %{"b" => %{"c" => %{"d" => 42}}}}
      assert encode!(chain) == "a:\n  b:\n    c:\n      d: 42"
    end
  end
end
