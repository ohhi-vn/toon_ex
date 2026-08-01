defmodule ToonEx.Decode.ComplexObjectTest do
  use ExUnit.Case, async: true

  # ── inline arrays (key[N]: v1,v2) ───────────────────────────────────────────

  describe "Phoenix Array" do
    test "decodes mixed objects" do
      expected_data =
        [
          %{
            "data" => [
              %{
                "index" => 0,
                "timestamp" => 259
              },
              %{
                "id" => "abc",
                "timestamp" => 1_257
              }
            ]
          }
        ]

      toon = """
      [1]:
        - data[2]:
          - index: 0
            timestamp: 259
          - id: abc
            timestamp: 1257
      """

      assert expected_data == ToonEx.decode!(toon)
    end

    test "decodes mixed object2" do
      expected_data = [
        "info",
        %{
          "id" => "908d993a-5c16-4bdf-b94d-76e559809eb5",
          "name" => "Test",
          "list" => [
            "019d3c0e-0833-72c4-b53e-04d6b79f3ff3"
          ],
          "status" => %{
            "time" => "2026-04-01T13:33:14.956244Z"
          }
        }
      ]

      toon = """
      [2]:
        - info
        - id: 908d993a-5c16-4bdf-b94d-76e559809eb5
          name: Test
          list[1]: 019d3c0e-0833-72c4-b53e-04d6b79f3ff3
          status:
            time: "2026-04-01T13:33:14.956244Z"
      """

      assert expected_data == ToonEx.decode!(toon)
    end

    test "Complex array 1" do
      string = """
      [5]:
        - "1"
        - "2"
        - "channel:room1"
        - user_location
        - user_id: ""
          packet_id: 988586b4-d0b8-4703-94d3-725d9dffdd60
          token: ""
          device_id: test
          gps_data:
            timestamp: 30522
            lon: -122.03852007
            lat: 37.3325448
            ele: 0
      """

      expected =
        [
          "1",
          "2",
          "channel:room1",
          "user_location",
          %{
            "user_id" => "",
            "packet_id" => "988586b4-d0b8-4703-94d3-725d9dffdd60",
            "token" => "",
            "device_id" => "test",
            "gps_data" => %{
              "timestamp" => 30_522,
              "lon" => -122.03852007,
              "lat" => 37.3325448,
              "ele" => 0
            }
          }
        ]

      result = ToonEx.decode!(string)

      assert expected == result
    end

    test "comlex object 1" do
      string = """
      user_id: ""
      packet_id: 988586b4-d0b8-4703-94d3-725d9dffdd60
      token: ""
      device_id: test
      gps_data:
        empty_field:
        timestamp: 30522
        lon: -122.03852007
        lat: 37.3325448
        ele: 0

      """

      expected =
        %{
          "user_id" => "",
          "packet_id" => "988586b4-d0b8-4703-94d3-725d9dffdd60",
          "token" => "",
          "device_id" => "test",
          "gps_data" => %{
            "empty_field" => %{},
            "timestamp" => 30_522,
            "lon" => -122.03852007,
            "lat" => 37.3325448,
            "ele" => 0
          }
        }

      result = ToonEx.decode!(string)

      assert expected == result
    end

    test "decodes mixed object 3" do
      toon = """
      [2]:
        - "test"
        - async: false
          success: true
          result[3]{name,user_id,username}:
            Layla Gibson,019d3c0e-0997-7e80-9bd3-024865090b15,user_89
            Annabelle Jaskolski,019d3c0e-096e-70ac-bcab-39f6ccc7f77c,user_68
            Mrs. Saige Cassin V,019d3c0e-092e-794b-b233-10c9557bf2a9,user_44
      """

      expected_data = [
        "test",
        %{
          "async" => false,
          "success" => true,
          "result" => [
            %{
              "name" => "Layla Gibson",
              "user_id" => "019d3c0e-0997-7e80-9bd3-024865090b15",
              "username" => "user_89"
            },
            %{
              "name" => "Annabelle Jaskolski",
              "user_id" => "019d3c0e-096e-70ac-bcab-39f6ccc7f77c",
              "username" => "user_68"
            },
            %{
              "name" => "Mrs. Saige Cassin V",
              "user_id" => "019d3c0e-092e-794b-b233-10c9557bf2a9",
              "username" => "user_44"
            }
          ]
        }
      ]

      assert expected_data == ToonEx.decode!(toon)
    end

    test "common object 1" do
      # ↓ indent 6 (was 4) — one extra level inside args:
      toon =
        "[5]:\n" <>
          "  - \"1\"\n" <>
          "  - \"4\"\n" <>
          "  - \"gen_api:019d372d-07f7-7403-852e-018c86f36cb3\"\n" <>
          "  - gen_api\n" <>
          "  - args: \n" <>
          "      device_id: 4bfc7b44-704a-4cbb-a7c3-fdc82352c580\n" <>
          "      request_id: 19e35116-b76b-470b-afc0-d5b9e2ccb69f\n" <>
          "      request_type: get_data\n" <>
          "      service: db"

      assert match?(
               [
                 "1",
                 "4",
                 "gen_api:019d372d-07f7-7403-852e-018c86f36cb3",
                 "gen_api",
                 %{
                   args: %{
                     device_id: "4bfc7b44-704a-4cbb-a7c3-fdc82352c580",
                     request_id: "19e35116-b76b-470b-afc0-d5b9e2ccb69f",
                     request_type: "get_data",
                     service: "db"
                   }
                 }
               ],
               ToonEx.decode!(toon, keys: :atoms)
             )
    end
  end
end
