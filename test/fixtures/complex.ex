defmodule ToonEx.Fixtures.Complex do
  @moduledoc """
  Realistic, deeply nested structs used by the complex encode/decode test suite.

  Hierarchy:
    Organisation
      └─ [Department]
            └─ head :: Employee
            └─ [Employee]
                  └─ [Project]    (uniform → tabular array)
                  └─ address :: Address
            └─ budget :: Budget
            └─ metadata :: map   (arbitrary string→string tags)
  """

  # ── leaf structs ────────────────────────────────────────────────────────────

  defmodule Address do
    @moduledoc false
    @derive ToonEx.Encoder
    defstruct [:street, :city, :country, :postcode]
  end

  defmodule Project do
    @moduledoc false
    @derive ToonEx.Encoder
    defstruct [:id, :name, :active, :score]
  end

  defmodule Budget do
    @moduledoc "Custom encoder: emits a single 'amount currency' string."
    defstruct [:amount, :currency]
  end

  defimpl ToonEx.Encoder, for: Budget do
    def encode(%{amount: a, currency: c}, _opts),
      do: "#{a} #{c}"
  end

  defmodule Employee do
    @moduledoc false
    @derive {ToonEx.Encoder, except: [:secret]}
    defstruct [:id, :name, :role, :salary, :active, :tags, :address, :projects, :secret]
  end

  defmodule Department do
    @moduledoc false
    @derive ToonEx.Encoder
    defstruct [:id, :name, :head, :employees, :budget, :metadata]
  end

  defmodule Organisation do
    @moduledoc false
    @derive ToonEx.Encoder
    defstruct [:id, :name, :founded, :public, :rating, :departments, :notes]
  end

  # ── sample data builder ─────────────────────────────────────────────────────

  @doc "Returns a fully-populated Organisation struct covering every value type."
  def sample do
    %Organisation{
      id: "org-001",
      name: "Acme Corporation",
      founded: 1987,
      public: true,
      rating: 4.75,
      notes: "Founded in a garage.\nNow global.",
      departments: [
        %Department{
          id: "dept-eng",
          name: "Engineering",
          head: %Employee{
            id: "emp-001",
            name: "Alice Zhao",
            role: "VP Engineering",
            salary: 120_000,
            active: true,
            tags: ["leadership", "backend"],
            secret: "hunter2",
            address: %Address{
              street: "1 Infinite Loop",
              city: "Cupertino",
              country: "US",
              postcode: "95014"
            },
            projects: [
              %Project{id: "p-01", name: "Phoenix", active: true, score: 9.5},
              %Project{id: "p-02", name: "Firebird", active: false, score: 7.0}
            ]
          },
          employees: [
            %Employee{
              id: "emp-002",
              name: "Bob Müller",
              role: "Senior Engineer",
              salary: 95_000,
              active: true,
              tags: ["backend", "databases"],
              secret: "s3cr3t",
              address: %Address{
                street: "42 Hauptstraße",
                city: "Berlin",
                country: "DE",
                postcode: "10115"
              },
              projects: [
                %Project{id: "p-01", name: "Phoenix", active: true, score: 8.2},
                %Project{id: "p-03", name: "Iceberg", active: true, score: 6.5}
              ]
            },
            %Employee{
              id: "emp-003",
              name: "Carol \"CC\" Chen",
              role: "Engineer",
              salary: 82_000,
              active: false,
              tags: [],
              secret: nil,
              address: %Address{
                street: "88 Nanjing Road",
                city: "Shanghai",
                country: "CN",
                postcode: "200001"
              },
              projects: []
            }
          ],
          budget: %Budget{amount: 500_000, currency: "USD"},
          metadata: %{
            "slack_channel" => "#engineering",
            "cost_center" => "CC-42",
            "on_call" => "true"
          }
        },
        %Department{
          id: "dept-ops",
          name: "Operations",
          head: %Employee{
            id: "emp-004",
            name: "Dan O'Brien",
            role: "Head of Ops",
            salary: 105_000,
            active: true,
            tags: ["infrastructure", "cloud"],
            secret: "password123",
            address: %Address{
              street: "1 Hacker Way",
              city: "Menlo Park",
              country: "US",
              postcode: "94025"
            },
            projects: [
              %Project{id: "p-04", name: "Atlas", active: true, score: 9.0}
            ]
          },
          employees: [],
          budget: %Budget{amount: 250_000, currency: "EUR"},
          metadata: %{}
        }
      ]
    }
  end

  @doc "Expected map after normalize + encode + decode (secret fields excluded)."
  def expected_map do
    %{
      "id" => "org-001",
      "name" => "Acme Corporation",
      "founded" => 1987,
      "public" => true,
      "rating" => 4.75,
      "notes" => "Founded in a garage.\nNow global.",
      "departments" => [
        %{
          "id" => "dept-eng",
          "name" => "Engineering",
          "head" => %{
            "id" => "emp-001",
            "name" => "Alice Zhao",
            "role" => "VP Engineering",
            "salary" => 120_000,
            "active" => true,
            "tags" => ["leadership", "backend"],
            "address" => %{
              "street" => "1 Infinite Loop",
              "city" => "Cupertino",
              "country" => "US",
              "postcode" => "95014"
            },
            "projects" => [
              %{"id" => "p-01", "name" => "Phoenix", "active" => true, "score" => 9.5},
              %{"id" => "p-02", "name" => "Firebird", "active" => false, "score" => 7}
            ]
          },
          "employees" => [
            %{
              "id" => "emp-002",
              "name" => "Bob Müller",
              "role" => "Senior Engineer",
              "salary" => 95_000,
              "active" => true,
              "tags" => ["backend", "databases"],
              "address" => %{
                "street" => "42 Hauptstraße",
                "city" => "Berlin",
                "country" => "DE",
                "postcode" => "10115"
              },
              "projects" => [
                %{"id" => "p-01", "name" => "Phoenix", "active" => true, "score" => 8.2},
                %{"id" => "p-03", "name" => "Iceberg", "active" => true, "score" => 6.5}
              ]
            },
            %{
              "id" => "emp-003",
              "name" => "Carol \"CC\" Chen",
              "role" => "Engineer",
              "salary" => 82_000,
              "active" => false,
              "tags" => [],
              "address" => %{
                "street" => "88 Nanjing Road",
                "city" => "Shanghai",
                "country" => "CN",
                "postcode" => "200001"
              },
              "projects" => []
            }
          ],
          "budget" => "500000 USD",
          "metadata" => %{
            "cost_center" => "CC-42",
            "on_call" => "true",
            "slack_channel" => "#engineering"
          }
        },
        %{
          "id" => "dept-ops",
          "name" => "Operations",
          "head" => %{
            "id" => "emp-004",
            "name" => "Dan O'Brien",
            "role" => "Head of Ops",
            "salary" => 105_000,
            "active" => true,
            "tags" => ["infrastructure", "cloud"],
            "address" => %{
              "street" => "1 Hacker Way",
              "city" => "Menlo Park",
              "country" => "US",
              "postcode" => "94025"
            },
            "projects" => [
              %{"id" => "p-04", "name" => "Atlas", "active" => true, "score" => 9}
            ]
          },
          "employees" => [],
          "budget" => "250000 EUR",
          "metadata" => %{}
        }
      ]
    }
  end
end
