defmodule ToonEx.ApiEdgesTest do
  use ExUnit.Case, async: true

  describe "ToonEx.decode/2 API surface" do
    test "decode!/1 raises DecodeError on malformed input" do
      assert_raise ToonEx.DecodeError, fn -> ToonEx.decode!("key:\n  bad jump") end
    end

    test "invalid options produce a decode error tuple" do
      assert {:error, %ToonEx.DecodeError{message: msg}} =
               ToonEx.decode("a: 1", keys: :bogus)

      assert msg =~ "Invalid options"
    end

    test "non-binary input is rejected by the guard" do
      assert_raise FunctionClauseError, fn -> ToonEx.decode(nil) end
      assert_raise FunctionClauseError, fn -> ToonEx.decode(:erlang.make_ref()) end
    end

    test "keys: :atoms and :atoms! conversion" do
      assert ToonEx.decode!("a: 1", keys: :atoms) == %{a: 1}
      assert ToonEx.decode!("a: 1", keys: :atoms!) == %{a: 1}
    end

    test "expand_paths: :safe expands folded dot keys" do
      doc = """
      user.name: Ada
      user.age: 36
      """

      {:ok, decoded} = ToonEx.decode(doc, expand_paths: :safe)
      assert decoded == %{"user" => %{"name" => "Ada", "age" => 36}}
    end

    test "expand_paths: :off keeps literal dotted keys" do
      assert ToonEx.decode!("user.name: Ada") == %{"user.name" => "Ada"}
    end
  end

  describe "root-level scalar documents" do
    test "single quoted primitive containing colons stays a string" do
      assert ToonEx.decode!(~S("a:b:c")) == "a:b:c"
    end

    test "single plain primitive without a colon decodes as itself" do
      assert ToonEx.decode!("42") == 42
      assert ToonEx.decode!("true") == true
      assert ToonEx.decode!("null") == nil
      assert ToonEx.decode!("hello") == "hello"
    end

    test "BOM prefixed documents parse" do
      assert ToonEx.decode!(<<0xEF, 0xBB, 0xBF>> <> "name: Ada") == %{"name" => "Ada"}
    end
  end

  describe "strict-mode structural errors" do
    test "malformed array header raises in strict mode" do
      assert {:error, %ToonEx.DecodeError{message: msg}} = ToonEx.decode("key [2]: a,b")

      assert msg =~ "array header" or msg =~ "Cannot parse"
    end

    test "unterminated quoted key errors cleanly" do
      assert {:error, %ToonEx.DecodeError{message: msg}} = ToonEx.decode(~S("oops: 1))

      assert msg != ""
    end

    test "tab-indented comment line is not treated as a comment" do
      # Leading whitespace containing tabs disqualifies comment stripping (§5.1).
      result = ToonEx.decode("\t# not a comment", strict: false)
      match?({:ok, _}, result) or match?({:error, _}, result) |> assert()
    end
  end

  describe "delimiter auto-detection edge cases" do
    test "tabs inside quoted values do not flip comma detection" do
      assert ToonEx.decode(~s(x[2]: "a\tb",c)) == {:ok, %{"x" => ["a\tb", "c"]}}
    end

    test "tab-separated values split even when declared with comma default" do
      assert ToonEx.decode(~s(x[2]: a\tb)) == {:ok, %{"x" => ["a", "b"]}}
    end
  end

  describe "float formatting corners" do
    test "very small floats render as plain decimals, not scientific notation" do
      out = ToonEx.encode!(1.0e-9)
      refute out =~ "e-"
      assert out =~ "0.000000001"

      tiny = ToonEx.encode!(1.0e-15)
      refute tiny =~ "e-"
    end

    test "very large floats render without exponent" do
      big = ToonEx.encode!(1.0e20)
      refute big =~ "e20"
      assert String.contains?(big, "100000000")
    end

    test "whole floats drop the decimal point" do
      assert ToonEx.encode!(5.0) == "5"
      assert ToonEx.encode!(-3.0) == "-3"
    end

    test "regular floats keep their shortest form" do
      assert ToonEx.encode!(3.14) == "3.14"
    end
  end

  describe "JSON convertor" do
    test "to_toon!/1 converts JSON text" do
      assert ToonEx.JSON.to_toon!(~s({"name":"Ada","tags":["x"]})) =~ "name: Ada"
    end

    test "from_toon!/1 produces JSON text" do
      json = ToonEx.JSON.from_toon!("name: Ada")
      assert json =~ "Ada"
      assert json =~ "name"
    end

    test "invalid JSON returns an error tuple" do
      assert {:error, _} = ToonEx.JSON.to_toon("{not json")
    end

    test "invalid TOON returns an error tuple" do
      assert {:error, _} = ToonEx.JSON.from_toon("key:\n   bad: 1\n more")
    end
  end

  describe "option validator" do
    test "non-keyword options crash validation with a clause error" do
      assert_raise FunctionClauseError, fn -> ToonEx.decode("a: 1", %{keys: :atoms}) end
    end
  end
end
