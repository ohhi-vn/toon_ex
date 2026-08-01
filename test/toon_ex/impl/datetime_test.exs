defmodule ToonEx.Impl.DateTimeTest do
  use ExUnit.Case, async: true

  alias ToonEx.Encoder

  defp dt(iso), do: elem(DateTime.from_iso8601(iso), 1)
  defp date(iso), do: elem(Date.from_iso8601(iso), 1)
  defp ndt(iso), do: elem(NaiveDateTime.from_iso8601(iso), 1)

  describe "ToonEx.Encoder protocol for DateTime" do
    test "encodes DateTime to ISO 8601 string" do
      dt = dt("2024-01-15T10:30:00Z")
      result = Encoder.encode(dt, [])
      assert result == "2024-01-15T10:30:00Z"
    end

    test "encodes DateTime with offset (normalized to UTC)" do
      dt = dt("2024-01-15T10:30:00+02:00")
      result = Encoder.encode(dt, [])
      assert result == "2024-01-15T08:30:00Z"
    end

    test "encodes DateTime with microseconds" do
      dt = dt("2024-01-15T10:30:00.123456Z")
      result = Encoder.encode(dt, [])
      assert result == "2024-01-15T10:30:00.123456Z"
    end
  end

  describe "ToonEx.Encoder protocol for Date" do
    test "encodes Date to ISO 8601 string" do
      d = date("2024-01-15")
      result = Encoder.encode(d, [])
      assert result == "2024-01-15"
    end

    test "encodes Date with year/month/day" do
      d = %Date{year: 2024, month: 12, day: 25}
      result = Encoder.encode(d, [])
      assert result == "2024-12-25"
    end
  end

  describe "ToonEx.Encoder protocol for NaiveDateTime" do
    test "encodes NaiveDateTime to ISO 8601 string" do
      ndt = ndt("2024-01-15T10:30:00")
      result = Encoder.encode(ndt, [])
      assert result == "2024-01-15T10:30:00"
    end

    test "encodes NaiveDateTime with microseconds" do
      ndt = ndt("2024-01-15T10:30:00.123456")
      result = Encoder.encode(ndt, [])
      assert result == "2024-01-15T10:30:00.123456"
    end
  end

  describe "ToonEx.encode!/1 with datetime types (full encoding pipeline)" do
    test "encodes DateTime through public API (quoted due to structure chars)" do
      dt = dt("2024-01-15T10:30:00Z")
      result = ToonEx.encode!(dt)
      # T and : are structure characters, so gets quoted
      assert result == ~s("2024-01-15T10:30:00Z")
    end

    test "encodes Date through public API (no structure chars, not quoted)" do
      d = date("2024-01-15")
      result = ToonEx.encode!(d)
      assert result == "2024-01-15"
    end

    test "encodes NaiveDateTime through public API (quoted due to T and :)" do
      ndt = ndt("2024-01-15T10:30:00")
      result = ToonEx.encode!(ndt)
      assert result == ~s("2024-01-15T10:30:00")
    end
  end

  describe "round-trip encoding" do
    test "DateTime round-trips through encode/decode" do
      original = dt("2024-01-15T10:30:00Z")
      encoded = ToonEx.encode!(original)
      {:ok, decoded} = ToonEx.decode(encoded)
      assert decoded == "2024-01-15T10:30:00Z"
    end

    test "Date round-trips through encode/decode" do
      original = date("2024-01-15")
      encoded = ToonEx.encode!(original)
      {:ok, decoded} = ToonEx.decode(encoded)
      assert decoded == "2024-01-15"
    end

    test "NaiveDateTime round-trips through encode/decode" do
      original = ndt("2024-01-15T10:30:00")
      encoded = ToonEx.encode!(original)
      {:ok, decoded} = ToonEx.decode(encoded)
      assert decoded == "2024-01-15T10:30:00"
    end
  end

  describe "datetime types in nested structures" do
    test "DateTime in map" do
      dt = dt("2024-01-15T10:30:00Z")
      data = %{"event" => "meeting", "time" => dt}
      result = ToonEx.encode!(data)
      assert result =~ "time: \"2024-01-15T10:30:00Z\""
    end

    test "Date in map" do
      d = date("2024-01-15")
      data = %{"date" => d}
      result = ToonEx.encode!(data)
      assert result =~ "date: 2024-01-15"
    end

    test "NaiveDateTime in map" do
      ndt = ndt("2024-01-15T10:30:00")
      data = %{"time" => ndt}
      result = ToonEx.encode!(data)
      assert result =~ "time: \"2024-01-15T10:30:00\""
    end

    test "NaiveDateTime in nested map" do
      ndt = ndt("2024-01-15T10:30:00")
      data = %{"outer" => %{"inner" => ndt}}
      result = ToonEx.encode!(data)
      assert result =~ "inner: \"2024-01-15T10:30:00\""
    end
  end
end
