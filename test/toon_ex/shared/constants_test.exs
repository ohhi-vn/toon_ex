defmodule ToonEx.Shared.ConstantsTest do
  use ExUnit.Case, async: true

  alias ToonEx.Constants

  describe "ToonEx.Constants accessor functions" do
    test "list_item_marker returns '-'" do
      assert Constants.list_item_marker() == "-"
    end

    test "list_item_prefix returns '- '" do
      assert Constants.list_item_prefix() == "- "
    end

    test "colon returns ':'" do
      assert Constants.colon() == ":"
    end

    test "comma returns ','" do
      assert Constants.comma() == ","
    end

    test "space returns ' '" do
      assert Constants.space() == " "
    end

    test "pipe returns '|'" do
      assert Constants.pipe() == "|"
    end

    test "tab returns '\\t'" do
      assert Constants.tab() == "\t"
    end

    test "newline returns '\\n'" do
      assert Constants.newline() == "\n"
    end

    test "open_bracket returns '['" do
      assert Constants.open_bracket() == "["
    end

    test "close_bracket returns ']'" do
      assert Constants.close_bracket() == "]"
    end

    test "open_brace returns '{'" do
      assert Constants.open_brace() == "{"
    end

    test "close_brace returns '}'" do
      assert Constants.close_brace() == "}"
    end

    test "open_paren returns '('" do
      assert Constants.open_paren() == "("
    end

    test "close_paren returns ')'" do
      assert Constants.close_paren() == ")"
    end

    test "double_quote returns '\"'" do
      assert Constants.double_quote() == "\""
    end

    test "backslash returns '\\\\'" do
      assert Constants.backslash() == "\\"
    end

    test "null_literal returns 'null'" do
      assert Constants.null_literal() == "null"
    end

    test "true_literal returns 'true'" do
      assert Constants.true_literal() == "true"
    end

    test "false_literal returns 'false'" do
      assert Constants.false_literal() == "false"
    end

    test "escape_sequences returns expected map" do
      escape = Constants.escape_sequences()
      assert escape["\\"] == "\\\\"
      assert escape["\""] == "\\\""
      assert escape["\n"] == "\\n"
      assert escape["\r"] == "\\r"
      assert escape["\t"] == "\\t"
    end

    test "unescape_sequences returns expected map" do
      unescape = Constants.unescape_sequences()
      assert unescape["\\\\"] == "\\"
      assert unescape["\\\""] == "\""
      assert unescape["\\n"] == "\n"
      assert unescape["\\r"] == "\r"
      assert unescape["\\t"] == "\t"
    end

    test "delimiters returns expected map" do
      delims = Constants.delimiters()
      assert delims[:comma] == ","
      assert delims[:tab] == "\t"
      assert delims[:pipe] == "|"
    end

    test "default_delimiter returns ','" do
      assert Constants.default_delimiter() == ","
    end

    test "default_indent returns 2" do
      assert Constants.default_indent() == 2
    end

    test "valid_delimiters returns [',', '\\t', '|']" do
      assert Constants.valid_delimiters() == [",", "\t", "|"]
    end

    test "valid_delimiter? returns true for valid delimiters" do
      assert Constants.valid_delimiter?(",") == true
      assert Constants.valid_delimiter?("\t") == true
      assert Constants.valid_delimiter?("|") == true
    end

    test "valid_delimiter? returns false for invalid delimiters" do
      assert Constants.valid_delimiter?(";") == false
      assert Constants.valid_delimiter?(" ") == false
      assert Constants.valid_delimiter?("") == false
    end

    test "structure_chars returns expected list" do
      chars = Constants.structure_chars()
      assert ":" in chars
      assert "[" in chars
      assert "]" in chars
      assert "{" in chars
      assert "}" in chars
      assert "(" in chars
      assert ")" in chars
      assert "\"" in chars
      assert "\\" in chars
      assert length(chars) == 9
    end

    test "control_chars returns expected list" do
      chars = Constants.control_chars()
      assert "\n" in chars
      assert "\r" in chars
      assert "\t" in chars
      assert "\b" in chars
      assert "\f" in chars
      assert length(chars) == 5
    end
  end
end
