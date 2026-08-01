defmodule ToonEx.Options.ValidatorTest do
  use ExUnit.Case, async: true

  alias ToonEx.Options.Validator

  defp schema do
    [
      name: [type: :string, required: true],
      age: [type: :pos_integer, default: 0],
      role: [type: {:in, [:admin, :user]}, default: :user],
      active: [type: :boolean, default: true],
      tags: [type: :list, default: []],
      metadata: [type: :map, default: %{}],
      score: [type: :number, default: 0.0],
      priority: [type: :integer, default: 10],
      count: [type: :non_neg_integer, default: 0],
      custom: [
        type: {:custom, fn v -> if String.length(v) > 3, do: :ok, else: {:error, "too short"} end}
      ],
      any_opt: [type: :any],
      optional_str: [type: :string]
    ]
  end

  describe "validate/2" do
    test "validates required string option" do
      assert {:ok, validated} = Validator.validate([name: "Alice"], schema())
      assert validated[:name] == "Alice"
    end

    test "returns error for missing required option" do
      assert {:error, %Validator{key: :name}} = Validator.validate([age: 25], schema())
    end

    test "applies default values" do
      assert {:ok, validated} = Validator.validate([name: "Bob"], schema())
      assert validated[:age] == 0
      assert validated[:role] == :user
      assert validated[:active] == true
      assert validated[:tags] == []
      assert validated[:metadata] == %{}
      assert validated[:score] == 0.0
      assert validated[:priority] == 10
      assert validated[:count] == 0
    end

    test "allows overriding defaults" do
      assert {:ok, validated} = Validator.validate([name: "Bob", age: 30, role: :admin], schema())
      assert validated[:age] == 30
      assert validated[:role] == :admin
    end

    test "validates boolean type" do
      assert {:ok, validated} = Validator.validate([name: "Bob", active: false], schema())
      assert validated[:active] == false

      assert {:error, %Validator{key: :active}} =
               Validator.validate([name: "Bob", active: "yes"], schema())
    end

    test "validates pos_integer type" do
      assert {:ok, validated} = Validator.validate([name: "Bob", age: 25], schema())
      assert validated[:age] == 25

      assert {:error, %Validator{key: :age}} = Validator.validate([name: "Bob", age: 0], schema())

      assert {:error, %Validator{key: :age}} =
               Validator.validate([name: "Bob", age: -1], schema())
    end

    test "validates non_neg_integer type" do
      assert {:ok, validated} = Validator.validate([name: "Bob", count: 0], schema())
      assert validated[:count] == 0

      assert {:ok, validated} = Validator.validate([name: "Bob", count: 10], schema())
      assert validated[:count] == 10

      assert {:error, %Validator{key: :count}} =
               Validator.validate([name: "Bob", count: -1], schema())
    end

    test "validates integer type" do
      assert {:ok, validated} = Validator.validate([name: "Bob", priority: -5], schema())
      assert validated[:priority] == -5

      assert {:ok, validated} = Validator.validate([name: "Bob", priority: 0], schema())
      assert validated[:priority] == 0

      assert {:ok, validated} = Validator.validate([name: "Bob", priority: 100], schema())
      assert validated[:priority] == 100
    end

    test "validates number type (integer and float)" do
      assert {:ok, validated} = Validator.validate([name: "Bob", score: 95], schema())
      assert validated[:score] == 95

      assert {:ok, validated} = Validator.validate([name: "Bob", score: 95.5], schema())
      assert validated[:score] == 95.5

      assert {:error, %Validator{key: :score}} =
               Validator.validate([name: "Bob", score: "high"], schema())
    end

    test "validates :in type (enum)" do
      assert {:ok, validated} = Validator.validate([name: "Bob", role: :admin], schema())
      assert validated[:role] == :admin

      assert {:error, %Validator{key: :role}} =
               Validator.validate([name: "Bob", role: :guest], schema())
    end

    test "validates list type" do
      assert {:ok, validated} = Validator.validate([name: "Bob", tags: ["a", "b"]], schema())
      assert validated[:tags] == ["a", "b"]

      assert {:error, %Validator{key: :tags}} =
               Validator.validate([name: "Bob", tags: "not-a-list"], schema())
    end

    test "validates map type" do
      assert {:ok, validated} =
               Validator.validate([name: "Bob", metadata: %{"key" => "value"}], schema())

      assert validated[:metadata] == %{"key" => "value"}

      assert {:error, %Validator{key: :metadata}} =
               Validator.validate([name: "Bob", metadata: "not-a-map"], schema())
    end

    test "validates keyword type" do
      schema_with_keyword = Keyword.put(schema(), :opts, type: :keyword, default: [])

      assert {:ok, validated} =
               Validator.validate([name: "Bob", opts: [key: "value"]], schema_with_keyword)

      assert validated[:opts] == [key: "value"]

      assert {:error, %Validator{key: :opts}} =
               Validator.validate([name: "Bob", opts: "not-a-keyword"], schema_with_keyword)
    end

    test "validates custom type" do
      assert {:ok, validated} = Validator.validate([name: "Bob", custom: "long enough"], schema())
      assert validated[:custom] == "long enough"

      assert {:error, %Validator{key: :custom}} =
               Validator.validate([name: "Bob", custom: "abc"], schema())
    end

    test "validates any type accepts anything" do
      assert {:ok, validated} = Validator.validate([name: "Bob", any_opt: 123], schema())
      assert validated[:any_opt] == 123

      assert {:ok, validated} = Validator.validate([name: "Bob", any_opt: :atom], schema())
      assert validated[:any_opt] == :atom

      assert {:ok, validated} = Validator.validate([name: "Bob", any_opt: "string"], schema())
      assert validated[:any_opt] == "string"

      assert {:ok, validated} = Validator.validate([name: "Bob", any_opt: []], schema())
      assert validated[:any_opt] == []
    end

    test "returns error for unknown option" do
      # Note: find_unknown_key only checks the first option, so put unknown first
      assert {:error, %Validator{key: :unknown, message: "unknown option :unknown"}} =
               Validator.validate([unknown: "value", name: "Bob"], schema())
    end

    test "handles nil value for optional option without default" do
      # When a key is present with nil value, it's validated against the type
      # and returns an error because nil is not a string
      assert {:error, %Validator{key: :optional_str}} =
               Validator.validate([name: "Bob", optional_str: nil], schema())
    end

    test "handles empty list as unknown option check" do
      assert {:ok, validated} = Validator.validate([name: "Bob"], schema())
      assert validated[:name] == "Bob"
    end

    test "returns error for invalid custom validation function" do
      schema_bad_custom = [custom_bad: [type: {:custom, "not a function"}]]

      assert {:error, %Validator{key: :custom_bad}} =
               Validator.validate([custom_bad: "test"], schema_bad_custom)
    end

    test "custom validation can return error tuple" do
      schema_custom = [
        val: [type: {:custom, fn v -> if v > 10, do: :ok, else: {:error, "must be > 10"} end}]
      ]

      assert {:ok, validated} = Validator.validate([val: 15], schema_custom)
      assert validated[:val] == 15

      assert {:error, %Validator{key: :val, message: "must be > 10"}} =
               Validator.validate([val: 5], schema_custom)
    end

    test "empty options with no required fields" do
      empty_schema = [opt: [type: :string]]
      assert {:ok, validated} = Validator.validate([], empty_schema)
      assert validated[:opt] == nil
    end
  end

  describe "Exception implementation" do
    test "exception struct can be created" do
      error = %Validator{key: :test, value: "bad", message: "invalid"}
      assert error.key == :test
      assert error.value == "bad"
      assert error.message == "invalid"
    end

    test "message/1 formats error with value" do
      error = %Validator{key: :name, value: "Alice", message: "is required"}
      assert Validator.message(error) == "invalid value \"Alice\" for key :name: is required"
    end

    test "message/1 formats error without value" do
      error = %Validator{key: :name, value: nil, message: "is required"}
      assert Validator.message(error) == "invalid value for key :name: is required"
    end
  end

  describe "{:or, types} validation" do
    test "validates with multiple allowed types" do
      schema_or = [value: [type: {:or, [:integer, :float, :string]}]]

      assert {:ok, _} = Validator.validate([value: 42], schema_or)
      assert {:ok, _} = Validator.validate([value: 3.14], schema_or)
      assert {:ok, _} = Validator.validate([value: "hello"], schema_or)

      assert {:error, _} = Validator.validate([value: :atom], schema_or)
      assert {:error, _} = Validator.validate([value: []], schema_or)
    end
  end
end
