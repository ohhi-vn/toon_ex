defmodule ToonEx.Btoon.Impl.DateTimeTest do
  use ExUnit.Case, async: true

  alias ToonEx.Btoon
  alias ToonEx.Btoon.Encoder

  defp dt(iso), do: elem(DateTime.from_iso8601(iso), 1)
  defp date(iso), do: elem(Date.from_iso8601(iso), 1)
  defp ndt(iso), do: elem(NaiveDateTime.from_iso8601(iso), 1)

  describe "Btoon.Encoder protocol for DateTime" do
    test "encodes DateTime to ISO 8601 string" do
      dt = dt("2024-01-15T10:30:00Z")
      assert Encoder.encode(dt, []) == "2024-01-15T10:30:00Z"
    end

    test "encodes DateTime with offset (normalized to UTC)" do
      dt = dt("2024-01-15T10:30:00+02:00")
      assert Encoder.encode(dt, []) == "2024-01-15T08:30:00Z"
    end
  end

  describe "Btoon.Encoder protocol for Date" do
    test "encodes Date to ISO 8601 string" do
      d = date("2024-01-15")
      assert Encoder.encode(d, []) == "2024-01-15"
    end
  end

  describe "Btoon.Encoder protocol for NaiveDateTime" do
    test "encodes NaiveDateTime to ISO 8601 string" do
      ndt = ndt("2024-01-15T10:30:00")
      assert Encoder.encode(ndt, []) == "2024-01-15T10:30:00"
    end
  end

  describe "BTOON round-trip encoding" do
    test "DateTime round-trips through encode/decode" do
      original = dt("2024-01-15T10:30:00Z")
      bin = Btoon.encode!(original)
      assert Btoon.decode!(bin) == "2024-01-15T10:30:00Z"
    end

    test "Date round-trips through encode/decode" do
      original = date("2024-01-15")
      bin = Btoon.encode!(original)
      assert Btoon.decode!(bin) == "2024-01-15"
    end

    test "NaiveDateTime round-trips through encode/decode" do
      original = ndt("2024-01-15T10:30:00")
      bin = Btoon.encode!(original)
      assert Btoon.decode!(bin) == "2024-01-15T10:30:00"
    end
  end

  describe "datetime types in nested structures" do
    test "DateTime in map" do
      dt = dt("2024-01-15T10:30:00Z")
      data = %{"event" => "meeting", "time" => dt}
      decoded = Btoon.decode!(Btoon.encode!(data))
      assert decoded == %{"event" => "meeting", "time" => "2024-01-15T10:30:00Z"}
    end

    test "Date in map" do
      d = date("2024-01-15")
      data = %{"date" => d}
      decoded = Btoon.decode!(Btoon.encode!(data))
      assert decoded == %{"date" => "2024-01-15"}
    end

    test "NaiveDateTime in nested map" do
      ndt = ndt("2024-01-15T10:30:00")
      data = %{"outer" => %{"time" => ndt}}
      decoded = Btoon.decode!(Btoon.encode!(data))
      assert decoded == %{"outer" => %{"time" => "2024-01-15T10:30:00"}}
    end
  end
end
