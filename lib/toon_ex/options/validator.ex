defmodule ToonEx.Options.Validator do
  @moduledoc """
  Pure Elixir options validator to replace NimbleOptions.

  Provides schema-based validation with support for common types,
  default values, and custom validation rules.
  """

  @type schema_option :: {atom(), option_config()}
  @type option_config :: keyword()
  @type validation_result :: {:ok, keyword()} | {:error, t()}

  @type t :: %__MODULE__{
          key: atom(),
          value: term(),
          message: String.t()
        }

  defstruct [:key, :value, :message, __exception__: true]

  @behaviour Exception

  @impl Exception
  def exception(opts) do
    struct!(__MODULE__, opts)
  end

  @doc """
  Validates options against a schema.

  ## Schema Configuration

  Each option in the schema supports:
    * `:type` - Type specification (see supported types below)
    * `:default` - Default value if option is not provided
    * `:required` - Whether the option is required (default: false)
    * `:doc` - Documentation string (ignored during validation)

  ## Supported Types

    * `:any` - Any value
    * `:boolean` - `true` or `false`
    * `:atom` - Any atom
    * `:string` - Binary string
    * `:integer` - Any integer
    * `:pos_integer` - Positive integer (> 0)
    * `:non_neg_integer` - Non-negative integer (>= 0)
    * `:float` - Float number
    * `:number` - Integer or float
    * `:keyword` - Keyword list
    * `:list` - List
    * `:map` - Map
    * `{:in, values}` - Value must be in the given list
    * `{:or, types}` - Value must match one of the given types
    * `{:custom, fun}` - Custom validation function

  ## Examples

      schema = [
        name: [type: :string, required: true],
        age: [type: :pos_integer, default: 0],
        role: [type: {:in, [:admin, :user]}, default: :user]
      ]

      ToonEx.Options.Validator.validate([name: "Alice"], schema)
      # => {:ok, [name: "Alice", age: 0, role: :user]}

      ToonEx.Options.Validator.validate([age: -1], schema)
      # => {:error, %ToonEx.Options.Validator{key: :name, ...}}
  """
  @spec validate(keyword(), [schema_option()]) :: validation_result()
  def validate(opts, schema) when is_list(opts) and is_list(schema) do
    schema_keys = Keyword.keys(schema) |> MapSet.new()
    validate(opts, schema, schema_keys)
  end

  @spec validate(keyword(), [schema_option()], MapSet.t()) :: validation_result()
  def validate(opts, schema, schema_keys) when is_list(opts) and is_list(schema) do
    opts_map = Map.new(opts)

    # Check for unknown options
    case find_unknown_key(opts, schema_keys) do
      {:unknown, key, value} ->
        {:error, error(key, value, "unknown option #{inspect(key)}")}

      :ok ->
        result =
          Enum.reduce_while(schema, {:ok, []}, fn {key, config}, {:ok, acc} ->
            case validate_option(key, config, opts_map) do
              {:ok, value} -> {:cont, {:ok, [{key, value} | acc]}}
              {:error, error} -> {:halt, {:error, error}}
            end
          end)

        case result do
          {:ok, validated} -> {:ok, Enum.reverse(validated)}
          {:error, _} = error -> error
        end
    end
  end

  defp find_unknown_key([], _schema_keys), do: :ok

  defp find_unknown_key([{key, value} | _rest], schema_keys) do
    if MapSet.member?(schema_keys, key) do
      find_unknown_key([], schema_keys)
    else
      {:unknown, key, value}
    end
  end

  defp validate_option(key, config, opts_map) do
    type = Keyword.get(config, :type, :any)
    default = Keyword.get(config, :default, :__undefined__)
    required = Keyword.get(config, :required, false)

    case Map.fetch(opts_map, key) do
      {:ok, value} ->
        validate_type(key, value, type)

      :error ->
        if default != :__undefined__ do
          {:ok, default}
        else
          if required do
            {:error, error(key, nil, "is required")}
          else
            {:ok, nil}
          end
        end
    end
  end

  defp validate_type(_key, value, :any), do: {:ok, value}
  defp validate_type(_key, value, :boolean) when is_boolean(value), do: {:ok, value}
  defp validate_type(_key, value, :atom) when is_atom(value), do: {:ok, value}
  defp validate_type(_key, value, :string) when is_binary(value), do: {:ok, value}
  defp validate_type(_key, value, :integer) when is_integer(value), do: {:ok, value}

  defp validate_type(_key, value, :pos_integer) when is_integer(value) and value > 0,
    do: {:ok, value}

  defp validate_type(_key, value, :non_neg_integer) when is_integer(value) and value >= 0,
    do: {:ok, value}

  defp validate_type(_key, value, :float) when is_float(value), do: {:ok, value}
  defp validate_type(_key, value, :number) when is_number(value), do: {:ok, value}

  defp validate_type(key, value, :keyword) do
    if is_list(value) and Keyword.keyword?(value),
      do: {:ok, value},
      else: {:error, error(key, value, "expected keyword list")}
  end

  defp validate_type(_key, value, :list) when is_list(value), do: {:ok, value}
  defp validate_type(_key, value, :map) when is_map(value), do: {:ok, value}
  defp validate_type(_key, nil, nil), do: {:ok, nil}

  defp validate_type(key, value, {:in, valid_values}) do
    if value in valid_values do
      {:ok, value}
    else
      {:error,
       error(key, value, "must be one of: #{inspect(valid_values)}, got: #{inspect(value)}")}
    end
  end

  defp validate_type(key, value, {:or, types}) do
    Enum.find_value(
      types,
      {:error, error(key, value, "doesn't match any of the allowed types")},
      fn type ->
        case validate_type(key, value, type) do
          {:ok, _} -> {:ok, value}
          _ -> nil
        end
      end
    )
  end

  defp validate_type(key, value, {:custom, fun}) when is_function(fun, 1) do
    case fun.(value) do
      :ok -> {:ok, value}
      {:error, message} -> {:error, error(key, value, message)}
    end
  end

  defp validate_type(key, value, type) do
    {:error, error(key, value, "expected type #{inspect(type)}, got: #{inspect(value)}")}
  end

  defp error(key, value, message) do
    %__MODULE__{
      key: key,
      value: value,
      message: message
    }
  end

  @doc """
  Returns a human-readable error message.
  """
  @impl true
  def message(%__MODULE__{key: key, value: value, message: msg}) do
    if value == nil do
      "invalid value for key #{inspect(key)}: #{msg}"
    else
      "invalid value #{inspect(value)} for key #{inspect(key)}: #{msg}"
    end
  end
end
