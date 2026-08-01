defmodule ToonEx.Fixtures.ComplexDocs do
  @moduledoc """
  Rich, realistic documents used by the complex-docs and large-object
  roundtrip test suites.

  Each builder is deterministic (no randomness) so tests are reproducible.

  The documents are chosen to exercise every TOON array format in one place:

    * `ecommerce_order/0` — inline arrays, tabular arrays with nested field
      groups (§9.3), nested objects, an empty object, and atom values.
    * `catalog/0` — keyed tabular form (§9.5) whose entry values carry a
      nested-uniform group column.
    * `sensor_batch/1` — a large tabular array (default 300 rows) with a
      nested field group and mixed numeric types.
    * `event_log/1` — a large mixed list-format array (§9.4) whose items
      have differing shapes.
    * `config_tree/0` — a deep configuration tree used by the key_folding
      tests.
    * `huge_doc/0` — a ~100MB (encoded) document mixing every format at
      scale. Built at runtime so the compiled module stays small — never
      reference it from a module attribute.
  """

  @doc """
  A single e-commerce order combining every array/object form:
  nested objects, tabular items with a nested `attrs` group, an inline
  string array, an empty object, and an atom value (`status`).
  """
  def ecommerce_order do
    %{
      "id" => "ORD-2024-0042",
      "customer" => %{
        "name" => "Ada Lovelace",
        "email" => "ada@example.com",
        "address" => %{
          "street" => "1 Analytical Way",
          "city" => "London",
          "postcode" => "EC1A 1BB"
        }
      },
      "items" => [
        %{
          "sku" => "TN-100",
          "name" => "Toon Poster",
          "qty" => 2,
          "price" => 9.99,
          "attrs" => %{"size" => "A2", "color" => "black"}
        },
        %{
          "sku" => "TN-101",
          "name" => "Toon Mug",
          "qty" => 1,
          "price" => 12.5,
          "attrs" => %{"size" => "350ml", "color" => "white"}
        },
        %{
          "sku" => "TN-102",
          "name" => "Toon Sticker Pack",
          "qty" => 3,
          "price" => 4.99,
          "attrs" => %{"size" => "10-pack", "color" => "mixed"}
        }
      ],
      "payment" => %{
        "method" => "card",
        "currency" => "GBP",
        "amount" => 52.45,
        "status" => "authorized"
      },
      "shipping" => %{
        "carrier" => "PigeonPost",
        "tracking" => "PP-88231",
        "eta" => "2024-08-05"
      },
      "status" => :confirmed,
      "flags" => ["expedited", "gift"],
      "metadata" => %{}
    }
  end

  @doc """
  A product catalogue whose categories are uniform objects, so the `categories`
  map is encoded in keyed tabular form (§9.5). Each entry value carries a
  nested-uniform `meta` object that collapses into a nested field group.
  """
  def catalog do
    %{
      "categories" => %{
        "books" => %{
          "display" => "Books",
          "items" => 120,
          "meta" => %{"featured" => true, "sort" => 1}
        },
        "music" => %{
          "display" => "Music",
          "items" => 84,
          "meta" => %{"featured" => false, "sort" => 2}
        },
        "games" => %{
          "display" => "Games",
          "items" => 41,
          "meta" => %{"featured" => true, "sort" => 3}
        }
      }
    }
  end

  @doc """
  A deterministic batch of sensor readings. The `sensors` list is uniform
  (every row shares the same keys and primitive values), so it is encoded as
  a tabular array whose `reading` column collapses into a nested field group
  (§9.3). `temp` is a float, `humidity` an integer, `status` a string.
  """
  def sensor_batch(n \\ 300) do
    %{
      "batch" => "B-2024-08-01",
      "source" => "edge-node-7",
      "sensors" =>
        Enum.map(1..n, fn i ->
          %{
            "id" => "sensor-#{i}",
            "room" => Enum.at(["lab-a", "lab-b", "server"], rem(i, 3)),
            "reading" => %{
              "temp" => 18.0 + rem(i, 40) / 10,
              "humidity" => rem(i * 7, 100)
            },
            "status" => if(rem(i, 4) == 0, do: "warn", else: "ok")
          }
        end)
    }
  end

  @doc """
  A large mixed event log. Every item has a different shape, so the array uses
  list format (§9.4). Exercises maps with nested objects, booleans, floats,
  plain strings, and atom-derived values.
  """
  def event_log(n \\ 200) do
    Enum.map(1..n, fn i ->
      case rem(i, 5) do
        0 ->
          %{"type" => "error", "code" => 500, "message" => "boom", "meta" => %{"retry" => false}}

        1 ->
          %{"type" => "login", "user" => "u#{i}", "success" => true}

        2 ->
          %{"type" => "metric", "name" => "latency_ms", "value" => rem(i, 100) + 0.5}

        3 ->
          %{"type" => "note", "text" => "checkpoint #{i}"}

        4 ->
          %{
            "type" => "deploy",
            "sha" => "abc#{i}",
            "env" => Enum.at(["staging", "prod"], rem(i, 2))
          }
      end
    end)
  end

  @doc """
  A deeply nested application configuration. Each inner object carries several
  keys so no single-key folding chain exists here; used for roundtrip and
  decode-only assertions on a realistic config tree.
  """
  def config_tree do
    %{
      "server" => %{
        "host" => "0.0.0.0",
        "port" => 8080,
        "tls" => %{"enabled" => true, "min_version" => "1.2"}
      },
      "database" => %{
        "url" => "postgres://localhost/toon",
        "pool" => %{"size" => 10, "idle_timeout" => 30},
        "read_replicas" => 2
      },
      "features" => %{
        "beta" => %{"chat" => true, "search" => false, "recommendations" => true}
      },
      "logging" => %{
        "level" => "info",
        "sinks" => ["stdout", "file"]
      }
    }
  end

  @doc """
  A ~100MB (encoded) complex document mixing every TOON format at scale:

    * `catalog` — a large flat object of long text values.
    * `records` — a large tabular array (30_000 rows) with a nested `region`
      field group (§9.3) and mixed numeric/boolean cells.
    * `index` — a large keyed-tabular object (10_000 entries, §9.5).
    * `events` — a large mixed list-format array (5_000 items, §9.4).
    * `config` — a small nested configuration tree.

  The document is rebuilt on every call so the compiled module stays small;
  call it from inside a test body, never via a module attribute.
  """
  def huge_doc do
    long_text =
      String.duplicate(
        "The quick brown fox jumps over the lazy dog. TOON keeps data compact and human readable. ",
        8
      )

    catalog =
      Map.new(1..115_000, fn i -> {"sku_#{i}", "#{long_text}SKU#{i}"} end)

    records =
      Enum.map(1..30_000, fn i ->
        %{
          "id" => i,
          "title" => "Record #{i}",
          "body" => long_text,
          "score" => i * 1.25,
          "active" => rem(i, 2) == 0,
          "region" => %{
            "code" => Enum.at(["EU", "US", "AP"], rem(i, 3)),
            "name" => "Region #{rem(i, 3)}"
          }
        }
      end)

    index =
      Map.new(1..10_000, fn i ->
        {"id_#{i}",
         %{
           "sku" => "sku_#{i}",
           "loc" => Enum.at(["rack-a", "rack-b", "rack-c"], rem(i, 3)),
           "qty" => rem(i, 1000)
         }}
      end)

    events =
      Enum.map(1..5_000, fn i ->
        case rem(i, 4) do
          0 -> %{"type" => "err", "code" => 500, "msg" => "boom #{i}"}
          1 -> %{"type" => "hit", "path" => "/api/v1/items", "ms" => rem(i, 500)}
          2 -> %{"type" => "deploy", "sha" => "abc#{i}", "env" => "prod"}
          3 -> %{"type" => "metric", "name" => "cpu", "value" => i / 100.0}
        end
      end)

    %{
      "catalog" => catalog,
      "records" => records,
      "index" => index,
      "events" => events,
      "config" => %{
        "server" => %{"host" => "0.0.0.0", "port" => 8080},
        "features" => %{"beta" => %{"chat" => true}},
        "logging" => %{"level" => "info", "sinks" => ["stdout", "file"]}
      }
    }
  end
end
