defmodule ToonEx.Decode.PrimitivesTest do
  use ExUnit.Case, async: true

  # ── null ────────────────────────────────────────────────────────────────────

  describe "null" do
    test "root null" do
      assert {:ok, nil} = ToonEx.decode("null")
    end

    test "null as map value" do
      assert {:ok, %{"x" => nil}} = ToonEx.decode("x: null")
    end

    test "null in inline array" do
      assert {:ok, %{"a" => [nil, nil]}} = ToonEx.decode("a[2]: null,null")
    end

    test "null is case-sensitive — 'Null' is a string" do
      assert {:ok, %{"x" => "Null"}} = ToonEx.decode("x: Null")
    end

    test "null is case-sensitive — 'NULL' is a string" do
      assert {:ok, %{"x" => "NULL"}} = ToonEx.decode("x: NULL")
    end
  end

  # ── booleans ────────────────────────────────────────────────────────────────

  describe "booleans" do
    test "true as map value" do
      assert {:ok, %{"x" => true}} = ToonEx.decode("x: true")
    end

    test "false as map value" do
      assert {:ok, %{"x" => false}} = ToonEx.decode("x: false")
    end

    test "root true" do
      assert {:ok, true} = ToonEx.decode("true")
    end

    test "root false" do
      assert {:ok, false} = ToonEx.decode("false")
    end

    test "True is a string (case-sensitive)" do
      assert {:ok, %{"x" => "True"}} = ToonEx.decode("x: True")
    end

    test "TRUE is a string" do
      assert {:ok, %{"x" => "TRUE"}} = ToonEx.decode("x: TRUE")
    end

    test "booleans in inline array" do
      assert {:ok, %{"flags" => [true, false, true]}} = ToonEx.decode("flags[3]: true,false,true")
    end
  end

  # ── integers ────────────────────────────────────────────────────────────────

  describe "integers" do
    test "zero" do
      assert {:ok, %{"n" => 0}} = ToonEx.decode("n: 0")
    end

    test "positive integer" do
      assert {:ok, %{"n" => 42}} = ToonEx.decode("n: 42")
    end

    test "negative integer" do
      assert {:ok, %{"n" => -17}} = ToonEx.decode("n: -17")
    end

    test "large integer" do
      assert {:ok, %{"n" => 1_000_000}} = ToonEx.decode("n: 1000000")
    end

    test "negative zero is integer 0" do
      assert {:ok, %{"n" => 0}} = ToonEx.decode("n: -0")
    end

    test "leading zero makes it a string" do
      assert {:ok, %{"n" => "05"}} = ToonEx.decode("n: 05")
    end

    test "leading zeros with minus makes it a string" do
      assert {:ok, %{"n" => "-007"}} = ToonEx.decode("n: -007")
    end

    test "single zero is integer, not string" do
      {:ok, result} = ToonEx.decode("n: 0")
      assert result["n"] === 0
      assert is_integer(result["n"])
    end

    test "root integer" do
      assert {:ok, 99} = ToonEx.decode("99")
    end
  end

  # ── floats ──────────────────────────────────────────────────────────────────

  describe "floats" do
    test "basic float" do
      assert {:ok, %{"x" => 3.14}} = ToonEx.decode("x: 3.14")
    end

    test "negative float" do
      assert {:ok, %{"x" => -2.5}} = ToonEx.decode("x: -2.5")
    end

    test "float with trailing zero decodes as integer (whole floats have no decimal)" do
      # TOON encodes 1.0 as "1" (no decimal point for whole-number floats).
      # "1" decodes back as integer 1, not float 1.0.
      assert {:ok, %{"x" => 1}} = ToonEx.decode("x: 1.0")
      {:ok, r} = ToonEx.decode("x: 1.0")
      assert is_integer(r["x"])
    end

    test "scientific notation lowercase e" do
      assert {:ok, %{"x" => 1_000_000}} = ToonEx.decode("x: 1e6")
    end

    test "scientific notation uppercase E" do
      assert {:ok, %{"x" => 1_000_000}} = ToonEx.decode("x: 1E6")
    end

    test "scientific notation with positive exponent sign" do
      assert {:ok, %{"x" => 1_000}} = ToonEx.decode("x: 1E+03")
    end

    test "scientific notation with negative exponent" do
      {:ok, result} = ToonEx.decode("x: 2.5e-2")
      assert_in_delta result["x"], 0.025, 1.0e-15
    end

    test "root float" do
      assert {:ok, 1.5} = ToonEx.decode("1.5")
    end
  end

  # ── strings ─────────────────────────────────────────────────────────────────

  describe "unquoted strings" do
    test "simple word" do
      assert {:ok, %{"name" => "Alice"}} = ToonEx.decode("name: Alice")
    end

    test "string with hyphen" do
      assert {:ok, %{"slug" => "hello-world"}} = ToonEx.decode("slug: hello-world")
    end

    test "string with dot" do
      assert {:ok, %{"v" => "1.2.3"}} = ToonEx.decode("v: 1.2.3")
    end

    test "root string" do
      assert {:ok, "hello"} = ToonEx.decode("hello")
    end
  end

  describe "quoted strings" do
    test "empty quoted string" do
      assert {:ok, %{"s" => ""}} = ToonEx.decode(~s(s: ""))
    end

    test "quoted string with spaces" do
      assert {:ok, %{"s" => "hello world"}} = ToonEx.decode(~s(s: "hello world"))
    end

    test "escape: backslash" do
      assert {:ok, %{"s" => "\\"}} = ToonEx.decode(~s(s: "\\\\"))
    end

    test "escape: double-quote" do
      assert {:ok, %{"s" => "\""}} = ToonEx.decode(~s(s: "\\""))
    end

    test "escape: newline \\n" do
      assert {:ok, %{"s" => "\n"}} = ToonEx.decode(~s(s: "\\n"))
    end

    test "escape: carriage return \\r" do
      assert {:ok, %{"s" => "\r"}} = ToonEx.decode(~s(s: "\\r"))
    end

    test "escape: tab \\t" do
      assert {:ok, %{"s" => "\t"}} = ToonEx.decode(~s(s: "\\t"))
    end

    test "multiple escapes in one string" do
      assert {:ok, %{"s" => "a\nb\tc"}} = ToonEx.decode(~s(s: "a\\nb\\tc"))
    end

    test "invalid escape sequence raises" do
      assert_raise ToonEx.DecodeError, fn -> ToonEx.decode!(~s(s: "\\q")) end
    end

    test "unterminated quoted string raises" do
      assert_raise ToonEx.DecodeError, fn -> ToonEx.decode!(~s(s: "no end)) end
    end

    test "quoted string that looks like null is a string" do
      assert {:ok, %{"s" => "null"}} = ToonEx.decode(~s(s: "null"))
    end

    test "quoted string that looks like true is a string" do
      assert {:ok, %{"s" => "true"}} = ToonEx.decode(~s(s: "true"))
    end

    test "quoted string that looks like an integer is a string" do
      assert {:ok, %{"s" => "42"}} = ToonEx.decode(~s(s: "42"))
    end

    test "quoted string preserving leading/trailing spaces" do
      assert {:ok, %{"s" => " padded "}} = ToonEx.decode(~s(s: " padded "))
    end

    test "quoted string with escaped backslash" do
      assert {:ok, %{"s" => "back\\slash"}} = ToonEx.decode(~S(s: "back\\slash"))
    end

    test "quoted string with unicode escape" do
      assert {:ok, %{"s" => "helloAworld"}} = ToonEx.decode(~S(s: "hello\u0041world"))
    end

    test "quoted string with newline escape" do
      assert {:ok, %{"s" => "line1\nline2"}} = ToonEx.decode(~S(s: "line1\nline2"))
    end

    test "quoted string with tab escape" do
      assert {:ok, %{"s" => "col1\tcol2"}} = ToonEx.decode(~S(s: "col1\tcol2"))
    end

    test "quoted string with carriage return escape" do
      assert {:ok, %{"s" => "line1\rline2"}} = ToonEx.decode(~S(s: "line1\rline2"))
    end

    test "quoted string with escaped quote" do
      assert {:ok, %{"s" => "say \"hi\""}} = ToonEx.decode(~S(s: "say \"hi\""))
    end

    test "empty quoted string value" do
      assert {:ok, %{"s" => ""}} = ToonEx.decode(~s(s: ""))
    end
  end

  # ── float edge cases ─────────────────────────────────────────────────────────

  describe "float edge cases" do
    test "very small float" do
      assert {:ok, %{"x" => 0.000001}} = ToonEx.decode("x: 0.000001")
    end

    test "very large float" do
      assert {:ok, %{"x" => 10_000_000_000}} = ToonEx.decode("x: 10000000000.0")
    end

    test "negative float" do
      assert {:ok, %{"x" => -3.14}} = ToonEx.decode("x: -3.14")
    end

    test "float with many decimal places" do
      assert {:ok, %{"x" => 3.14159265358979}} = ToonEx.decode("x: 3.14159265358979")
    end

    test "zero float" do
      assert {:ok, %{"x" => 0}} = ToonEx.decode("x: 0.0")
    end
  end

  # ── integer edge cases ───────────────────────────────────────────────────────

  describe "integer edge cases" do
    test "zero" do
      assert {:ok, %{"x" => 0}} = ToonEx.decode("x: 0")
    end

    test "negative integer" do
      assert {:ok, %{"x" => -42}} = ToonEx.decode("x: -42")
    end

    test "very large integer" do
      assert {:ok, %{"x" => 999_999_999_999}} = ToonEx.decode("x: 999999999999")
    end

    test "very small negative integer" do
      assert {:ok, %{"x" => -999_999_999_999}} = ToonEx.decode("x: -999999999999")
    end
  end
end
