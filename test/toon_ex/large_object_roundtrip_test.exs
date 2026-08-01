defmodule ToonEx.LargeObjectRoundtripTest do
  @moduledoc """
  Roundtrip tests for large and deeply nested objects.

  Every roundtrip asserts `decode(encode(x)) == normalize(x)` (numeric `==`,
  so whole floats that encode as integers still compare equal). The suites
  also cover re-encode idempotency (`encode(decode(encode(x))) == encode(x)`),
  option variants (delimiters, indents), and decode-only spot checks.

  Sizes are chosen to exercise the hash-map (>32 keys), tabular/keyed-tabular
  (§9.3/§9.5) and list-array (§9.4) code paths at scale without slowing the
  suite down.
  """
  use ExUnit.Case, async: true

  alias ToonEx.Fixtures.ComplexDocs
  alias ToonEx.OrderedObject

  defp rt(value, opts \\ []) do
    encoded = ToonEx.encode!(value, opts)

    decode_opts =
      opts
      |> Keyword.take([:keys, :expand_paths])
      |> Keyword.put(:indent_size, Keyword.get(opts, :indent, 2))

    decoded = ToonEx.decode!(encoded, decode_opts)
    {encoded, decoded, ToonEx.Utils.normalize(value)}
  end

  defp assert_rt(value, opts \\ []) do
    {_enc, decoded, norm} = rt(value, opts)

    assert decoded == norm,
           "Roundtrip failed\nNormalized: #{inspect(norm, limit: 20)}\nDecoded:    #{inspect(decoded, limit: 20)}"
  end

  defp assert_idempotent(value, opts \\ []) do
    e1 = ToonEx.encode!(value, opts)
    e2 = ToonEx.encode!(ToonEx.decode!(e1), opts)
    assert e1 == e2, "Re-encode is not byte-stable"
  end

  # ── large flat maps ────────────────────────────────────────────────────────

  describe "large flat maps" do
    test "1_000-key map round-trips" do
      data = Map.new(1..1_000, fn i -> {"key_#{i}", i} end)
      assert_rt(data)
    end

    test "2_000-key map round-trips" do
      data = Map.new(1..2_000, fn i -> {"key_#{i}", i} end)
      assert_rt(data)
    end

    test "2_000-key map with mixed value types round-trips" do
      data =
        Map.new(1..2_000, fn i ->
          {
            "key_#{i}",
            %{
              "n" => i,
              "f" => i / 4.0,
              "s" => "value #{i}",
              "b" => rem(i, 2) == 0,
              "nul" => nil
            }
          }
        end)

      assert_rt(data)
    end

    test "nested sections of sub-keys round-trip (20 × 100)" do
      data =
        Map.new(1..20, fn s ->
          {"section_#{s}", Map.new(1..100, fn k -> {"key_#{k}", "val_#{s}_#{k}"} end)}
        end)

      assert_rt(data)
    end

    test "large map re-encodes byte-stable" do
      data = Map.new(1..2_000, fn i -> {"key_#{i}", i} end)
      assert_idempotent(data)
    end
  end

  # ── deep nesting ───────────────────────────────────────────────────────────

  describe "deep nesting" do
    test "50 levels round-trips" do
      deep = Enum.reduce(1..50, %{"leaf" => "x"}, fn i, acc -> %{"level_#{i}" => acc} end)
      assert_rt(deep)
    end

    test "100 levels round-trips" do
      deep = Enum.reduce(1..100, %{"leaf" => "x"}, fn i, acc -> %{"level_#{i}" => acc} end)
      assert_rt(deep)
    end

    test "150 levels round-trips" do
      deep = Enum.reduce(1..150, %{"leaf" => "x"}, fn i, acc -> %{"level_#{i}" => acc} end)
      assert_rt(deep)
    end

    test "deep nesting with arrays at the leaves round-trips" do
      deep =
        Enum.reduce(1..60, %{"nums" => Enum.to_list(1..5)}, fn i, acc ->
          %{"level_#{i}" => acc}
        end)

      assert_rt(deep)
    end

    test "alternating maps and lists 100 levels round-trips" do
      data =
        Enum.reduce(1..100, "bottom", fn i, acc ->
          if rem(i, 2) == 0, do: %{"m#{i}" => acc}, else: [acc, i]
        end)

      assert_rt(data)
    end
  end

  # ── large tabular arrays ───────────────────────────────────────────────────

  describe "large tabular arrays" do
    test "1_000 rows with a nested group round-trip" do
      data = %{
        "orders" =>
          Enum.map(1..1_000, fn i ->
            %{
              "id" => i,
              "customer" => %{
                "name" => "Cust #{i}",
                "country" => Enum.at(["DK", "US", "UK", "DE"], rem(i, 4))
              },
              "total" => i * 1.5
            }
          end)
      }

      assert_rt(data)
    end

    test "5_000 primitive rows round-trip" do
      data = %{
        "users" =>
          Enum.map(1..5_000, fn i ->
            %{"id" => i, "name" => "u#{i}", "active" => rem(i, 2) == 0}
          end)
      }

      assert_rt(data)
    end

    test "1_000 rows with keys requiring quotes round-trip" do
      data = %{
        "rows" =>
          Enum.map(1..1_000, fn i ->
            %{"order:id" => i, "full name" => "user #{i}"}
          end)
      }

      {enc, decoded, norm} = rt(data)
      assert decoded == norm
      assert enc =~ ~s({"full name","order:id"}:)
    end

    test "tabulated strings that look like literals/numbers round-trip" do
      data = %{
        "rows" => [
          %{"id" => 1, "status" => "true", "code" => "42", "tag" => "#a", "text" => "a,b"},
          %{"id" => 2, "status" => "false", "code" => "007", "tag" => "b", "text" => "plain"}
        ]
      }

      {enc, decoded, norm} = rt(data)
      assert decoded == norm
      assert enc =~ ~s("42",1,"true","#a","a,b")
    end

    test "1_000-row tabular array at the root round-trips" do
      data = Enum.map(1..1_000, fn i -> %{"id" => i, "name" => "item_#{i}"} end)
      assert_rt(data)
    end

    test "large tabular array re-encodes byte-stable" do
      data = %{
        "orders" =>
          Enum.map(1..1_000, fn i ->
            %{"id" => i, "total" => i * 1.5}
          end)
      }

      assert_idempotent(data)
    end
  end

  # ── large keyed tabular objects ────────────────────────────────────────────

  describe "large keyed tabular objects" do
    test "300 entries round-trip" do
      data = %{
        "users" =>
          Map.new(1..300, fn i ->
            {"u#{i}", %{"name" => "User #{i}", "age" => 20 + rem(i, 60)}}
          end)
      }

      assert_rt(data)
    end

    test "300 entries with a nested group round-trip" do
      data = %{
        "servers" =>
          Map.new(1..300, fn i ->
            {
              "srv-#{i}",
              %{
                "host" => "host#{i}.example.com",
                "limits" => %{"cpu" => "2", "mem" => "#{rem(i, 8) + 1}Gi"},
                "zone" => Enum.at(["a", "b", "c"], rem(i, 3))
              }
            }
          end)
      }

      {enc, decoded, norm} = rt(data)
      assert decoded == norm
      assert enc =~ "servers[300:]{host,limits{cpu,mem},zone}:"
    end

    test "500 entries with entry keys requiring quotes round-trip" do
      data = %{
        "users" =>
          Map.new(1..500, fn i ->
            {"user #{i}", %{"name" => "U#{i}", "active" => rem(i, 2) == 0}}
          end)
      }

      assert_rt(data)
    end

    test "root keyed tabular object round-trips" do
      data =
        Map.new(1..100, fn i ->
          {"item_#{i}", %{"value" => i, "label" => "L#{i}"}}
        end)

      {enc, decoded, norm} = rt(data)
      assert decoded == norm
      assert enc =~ "[100:]{label,value}:"
    end
  end

  # ── large list arrays ──────────────────────────────────────────────────────

  describe "large list arrays" do
    test "500 mixed-shape items round-trip" do
      items =
        Enum.map(1..500, fn i ->
          case rem(i, 5) do
            0 -> %{"type" => "error", "code" => 500, "meta" => %{"retry" => false}}
            1 -> %{"type" => "login", "user" => "u#{i}", "success" => true}
            2 -> %{"type" => "metric", "value" => rem(i, 100) + 0.5}
            3 -> %{"type" => "note", "text" => "checkpoint #{i}"}
            4 -> %{"type" => "deploy", "sha" => "abc#{i}", "env" => "prod"}
          end
        end)

      assert_rt(items)
    end

    test "300 items each containing nested objects and arrays round-trip" do
      items =
        Enum.map(1..300, fn i ->
          %{
            "id" => i,
            "profile" => %{"name" => "User #{i}", "roles" => ["admin", "viewer"]},
            "points" => [i, i * 2, i * 3],
            "active" => rem(i, 2) == 0
          }
        end)

      assert_rt(items)
    end

    test "500 mixed items re-encodes byte-stable" do
      items = ComplexDocs.event_log(500)
      assert_idempotent(items)
    end
  end

  # ── large inline arrays ────────────────────────────────────────────────────

  describe "large inline arrays" do
    test "10_000 integers round-trip" do
      assert_rt(Enum.to_list(1..10_000))
    end

    test "5_000 strings with special characters round-trip" do
      strings = Enum.map(1..5_000, fn i -> "item #{i}: [a,b]#c\\d" end)
      assert_rt(strings)
    end

    test "3_000 mixed primitives round-trip" do
      data =
        Enum.map(1..3_000, fn i ->
          case rem(i, 4) do
            0 -> i
            1 -> i * 1.5
            2 -> "s#{i}"
            3 -> rem(i, 2) == 0
          end
        end)

      assert_rt(data)
    end
  end

  # ── mega document (everything combined) ────────────────────────────────────

  describe "mega document" do
    defp mega do
      %{
        "order" => ComplexDocs.ecommerce_order(),
        "catalog" => ComplexDocs.catalog(),
        "sensors" => ComplexDocs.sensor_batch(800),
        "events" => ComplexDocs.event_log(300),
        "config" => ComplexDocs.config_tree(),
        "stats" => %{"total" => 12_345, "avg" => 7.5, "p99" => 99.99}
      }
    end

    test "full mega document round-trips" do
      assert_rt(mega())
    end

    test "mega document output is large" do
      enc = ToonEx.encode!(mega())
      assert byte_size(enc) > 30_000
    end

    test "mega document re-encodes byte-stable" do
      assert_idempotent(mega())
    end

    test "decode → encode → decode on mega document is stable" do
      d1 = ToonEx.decode!(ToonEx.encode!(mega()))
      d2 = ToonEx.decode!(ToonEx.encode!(d1))
      assert d1 == d2
    end
  end

  # ── option variants on large documents ─────────────────────────────────────

  describe "options across large documents" do
    test "tab delimiter on 1_000-row tabular" do
      data = %{
        "users" =>
          Enum.map(1..1_000, fn i ->
            %{"id" => i, "name" => "user #{i}", "email" => "u#{i}@example.com"}
          end)
      }

      assert_rt(data, delimiter: "\t")
    end

    test "pipe delimiter on large keyed tabular" do
      data = %{
        "servers" =>
          Map.new(1..200, fn i ->
            {"srv-#{i}", %{"host" => "h#{i}.example.com", "port" => 8000 + i}}
          end)
      }

      assert_rt(data, delimiter: "|")
    end

    test "indent: 4 on deep nesting" do
      deep = Enum.reduce(1..60, %{"leaf" => 1}, fn i, acc -> %{"l#{i}" => acc} end)
      assert_rt(deep, indent: 4)
    end

    test "keys: :atoms on a large document" do
      data = Map.new(1..100, fn i -> {"key_#{i}", i} end)
      decoded = ToonEx.decode!(ToonEx.encode!(data), keys: :atoms)
      assert decoded[:key_1] == 1
      assert decoded[:key_100] == 100
    end
  end

  # ── OrderedObject at scale ─────────────────────────────────────────────────

  describe "OrderedObject at scale" do
    test "50-key ordered object preserves declared order" do
      pairs = Enum.map(1..50, fn i -> {"key_#{i}", i} end)
      obj = OrderedObject.new(pairs)
      enc = ToonEx.encode!(obj)
      lines = String.split(enc, "\n")
      assert hd(lines) == "key_1: 1"
      assert List.last(lines) == "key_50: 50"
    end

    test "large ordered object round-trips to a plain map" do
      pairs = Enum.map(1..50, fn i -> {"key_#{i}", i} end)
      obj = OrderedObject.new(pairs)
      decoded = ToonEx.decode!(ToonEx.encode!(obj))
      assert decoded == Map.new(pairs)
    end

    test "ordered tabular array with many rows preserves row order" do
      rows =
        Enum.map(1..50, fn i ->
          OrderedObject.new([{"name", "u#{i}"}, {"age", i}])
        end)

      enc = ToonEx.encode!(%{"users" => rows})
      assert enc =~ "users[50]{name,age}:"
      decoded = ToonEx.decode!(enc)
      assert hd(decoded["users"])["name"] == "u1"
      assert List.last(decoded["users"])["name"] == "u50"
    end
  end
end
