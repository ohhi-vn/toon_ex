defmodule ToonEx.FixturesTest do
  @moduledoc """
  Tests based on official TOON specification fixtures from toon-format/spec.

  This test suite dynamically generates tests from the JSON fixture files,
  ensuring 100% compatibility with the official specification.

  Encoder tests assert the exact string from the spec fixture. The fixture
  JSON is decoded with `Jason.OrderedObject` so key insertion order survives,
  and those objects are converted to `ToonEx.OrderedObject` before encoding,
  letting the encoder reproduce the spec's insertion-ordered output exactly.
  """
  use ExUnit.Case, async: true

  # Load all fixture files
  @encode_fixtures Path.wildcard("spec/tests/fixtures/encode/*.json")
                   |> Enum.map(fn file ->
                     {Path.basename(file, ".json"),
                      File.read!(file) |> Jason.decode!(objects: :ordered_objects)}
                   end)

  @decode_fixtures Path.wildcard("spec/tests/fixtures/decode/*.json")
                   |> Enum.map(fn file ->
                     {Path.basename(file, ".json"), File.read!(file) |> Jason.decode!()}
                   end)

  # Generate encoder tests
  for {category, fixture} <- @encode_fixtures do
    describe "Encode: #{category} - #{fixture["description"]}" do
      for test <- fixture["tests"] do
        @test test
        test test["name"] do
          # Access the input through the ordered fixture (Jason.OrderedObject
          # implements Access) so key order is preserved, then convert to a
          # ToonEx.OrderedObject the encoder understands.
          input = convert_to_ordered_object(@test["input"])

          # Convert the rest of the test object to a plain map for lookups.
          test_map = jason_to_map(@test)
          expected = test_map["expected"]

          # Convert string keys to atoms for options (camelCase -> snake_case)
          options =
            Map.get(test_map, "options", %{})
            |> Enum.map(fn {k, v} ->
              snake_case_key =
                k
                |> Macro.underscore()
                |> String.to_atom()

              {snake_case_key, v}
            end)

          case ToonEx.encode(input, options) do
            {:ok, result} ->
              assert result == expected,
                     """
                     Encoder test failed: #{test_map["name"]}
                     Spec section: #{test_map["specSection"]}

                     Input:
                     #{inspect(input, pretty: true, limit: :infinity)}

                     Expected:
                     #{expected}

                     Got:
                     #{result}
                     """

            {:error, error} ->
              flunk("""
              Unexpected encoding error: #{test_map["name"]}
              Spec section: #{test_map["specSection"]}

              Input: #{inspect(input, pretty: true, limit: :infinity)}
              Error: #{Exception.message(error)}
              """)
          end
        end
      end
    end
  end

  # Generate decoder tests
  for {category, fixture} <- @decode_fixtures do
    describe "Decode: #{category} - #{fixture["description"]}" do
      for test <- fixture["tests"] do
        @test test
        should_error = Map.get(test, "shouldError", false)

        if should_error do
          test "#{test["name"]} (should error)" do
            input = @test["input"]

            options =
              Map.get(@test, "options", %{})
              |> Enum.map(fn {k, v} ->
                {convert_decoder_option_key(k), v}
              end)

            assert_raise ToonEx.DecodeError, fn ->
              ToonEx.decode!(input, options)
            end
          end
        else
          test test["name"] do
            input = @test["input"]
            expected = @test["expected"]

            options =
              Map.get(@test, "options", %{})
              |> Enum.map(fn {k, v} ->
                {convert_decoder_option_key(k), v}
              end)

            case ToonEx.decode(input, options) do
              {:ok, result} ->
                assert result == expected,
                       """
                       Decoder test failed: #{@test["name"]}
                       Spec section: #{@test["specSection"]}

                       Input:
                       #{input}

                       Expected:
                       #{inspect(expected, pretty: true, limit: :infinity)}

                       Got:
                       #{inspect(result, pretty: true, limit: :infinity)}
                       """

              {:error, error} ->
                flunk("""
                Unexpected decoding error: #{@test["name"]}
                Spec section: #{@test["specSection"]}

                Input: #{input}
                Error: #{Exception.message(error)}
                """)
            end
          end
        end
      end
    end
  end

  # Helper: recursively convert Jason.OrderedObject to a plain map (order lost).
  defp jason_to_map(value) when is_map(value) do
    if value.__struct__ == Jason.OrderedObject do
      Map.new(value.values, fn {k, v} -> {k, jason_to_map(v)} end)
    else
      Map.new(value, fn {k, v} -> {k, jason_to_map(v)} end)
    end
  end

  defp jason_to_map(value) when is_list(value), do: Enum.map(value, &jason_to_map/1)
  defp jason_to_map(value), do: value

  # Helper: recursively convert Jason.OrderedObject to ToonEx.OrderedObject,
  # preserving declared key order.
  defp convert_to_ordered_object(value) when is_map(value) do
    if value.__struct__ == Jason.OrderedObject do
      ToonEx.OrderedObject.new(
        Enum.map(value.values, fn {k, v} -> {k, convert_to_ordered_object(v)} end)
      )
    else
      Map.new(value, fn {k, v} -> {k, convert_to_ordered_object(v)} end)
    end
  end

  defp convert_to_ordered_object(value) when is_list(value) do
    Enum.map(value, &convert_to_ordered_object/1)
  end

  defp convert_to_ordered_object(value), do: value

  # Helper to convert decoder option keys from spec format to Elixir format
  defp convert_decoder_option_key("indent"), do: :indent_size
  defp convert_decoder_option_key("indentSize"), do: :indent_size
  defp convert_decoder_option_key(key), do: key |> Macro.underscore() |> String.to_atom()
end
