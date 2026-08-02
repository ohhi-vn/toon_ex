defmodule ToonEx.Btoon.LargeObjectRoundtripTest do
  @moduledoc """
  Roundtrip tests for large and deeply nested BTOON objects.

  Every roundtrip asserts `decode(encode(x)) == x` (numeric `==`, so whole
  floats that encode as floats still compare equal). The suites also cover
  re-encode idempotency (`encode(decode(encode(x))) == encode(x)`), deep
  nesting (within the decoder's default `max_depth` of 100), and scale paths:
  hash-map keys (>32), tabular arrays, typed arrays, and list arrays.
  """
  use ExUnit.Case, async: true

  defp rt(value, opts) do
    encoded = ToonEx.Btoon.encode!(value, opts)
    decoded = ToonEx.Btoon.decode!(encoded)
    {encoded, decoded, value}
  end

  defp assert_rt(value, opts \\ []) do
    {_enc, decoded, norm} = rt(value, opts)

    assert decoded == norm,
           "Roundtrip failed\nNormalized: #{inspect(norm, limit: 20)}\nDecoded:    #{inspect(decoded, limit: 20)}"
  end

  defp assert_idempotent(value, opts \\ []) do
    e1 = ToonEx.Btoon.encode!(value, opts)
    e2 = ToonEx.Btoon.encode!(ToonEx.Btoon.decode!(e1), opts)
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

    test "75 levels round-trips" do
      deep = Enum.reduce(1..75, %{"leaf" => "x"}, fn i, acc -> %{"level_#{i}" => acc} end)
      assert_rt(deep)
    end

    test "deep nesting with arrays at the leaves round-trips" do
      deep =
        Enum.reduce(1..40, %{"nums" => Enum.to_list(1..5)}, fn i, acc ->
          %{"level_#{i}" => acc}
        end)

      assert_rt(deep)
    end

    test "alternating maps and lists 60 levels round-trips" do
      data =
        Enum.reduce(1..60, "bottom", fn i, acc ->
          if rem(i, 2) == 0, do: %{"m#{i}" => acc}, else: [acc, i]
        end)

      assert_rt(data)
    end

    test "exceeding max_depth raises DecodeError" do
      deep = Enum.reduce(1..150, %{"leaf" => "x"}, fn i, acc -> %{"level_#{i}" => acc} end)
      bin = ToonEx.Btoon.encode!(deep, string_table: :off)

      assert_raise ToonEx.Btoon.DecodeError, fn -> ToonEx.Btoon.decode!(bin) end
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
        "catalog" =>
          Map.new(1..200, fn i ->
            {"sku_#{i}", %{"name" => "Item #{i}", "price" => i * 1.99, "in_stock" => true}}
          end),
        "records" =>
          Enum.map(1..300, fn i ->
            %{
              "id" => i,
              "score" => i / 8.0,
              "active" => rem(i, 2) == 0,
              "region" => %{"code" => Enum.at(["US", "UK", "DE"], rem(i, 3)), "name" => "R#{i}"}
            }
          end),
        "events" =>
          Enum.map(1..200, fn i ->
            case rem(i, 3) do
              0 -> %{"type" => "metric", "value" => i * 0.5}
              1 -> %{"type" => "deploy", "sha" => "abc#{i}", "env" => "prod"}
              2 -> %{"type" => "note", "text" => "checkpoint #{i}"}
            end
          end),
        "config" => %{
          "features" => %{"beta" => %{"chat" => true}},
          "logging" => %{"sinks" => ["stdout", "file"]}
        },
        "stats" => %{"total" => 12_345, "avg" => 7.5, "p99" => 99.99}
      }
    end

    test "full mega document round-trips" do
      assert_rt(mega())
    end

    test "mega document output is large" do
      enc = ToonEx.Btoon.encode!(mega())
      assert byte_size(enc) > 5_000
    end

    test "mega document re-encodes byte-stable" do
      assert_idempotent(mega())
    end

    test "decode → encode → decode on mega document is stable" do
      d1 = ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(mega()))
      d2 = ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(d1))
      assert d1 == d2
    end
  end

  # ── option variants on large documents ─────────────────────────────────────

  describe "options across large documents" do
    test "string_table: :off on 1_000-row tabular" do
      data = %{
        "users" =>
          Enum.map(1..1_000, fn i ->
            %{"id" => i, "name" => "user #{i}", "email" => "u#{i}@example.com"}
          end)
      }

      assert_rt(data, string_table: :off)
    end

    test "typed_arrays: false on large inline array" do
      assert_rt(Enum.to_list(1..1_000), typed_arrays: false)
    end

    test "keys: :atoms on a large document" do
      data = Map.new(1..100, fn i -> {"key_#{i}", i} end)
      decoded = ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(data), keys: :atoms)
      assert decoded[:key_1] == 1
      assert decoded[:key_100] == 100
    end

    test "re-encode after keys: :atoms decode is byte-stable" do
      data = Map.new(1..100, fn i -> {"key_#{i}", i} end)
      e1 = ToonEx.Btoon.encode!(data)
      atom_decoded = ToonEx.Btoon.decode!(e1, keys: :atoms)
      assert ToonEx.Btoon.encode!(atom_decoded) == e1
    end
  end
end
