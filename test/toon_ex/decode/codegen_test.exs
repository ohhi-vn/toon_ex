defmodule ToonEx.Decode.CodegenTest do
  use ExUnit.Case, async: true

  import ToonEx.Decode.Codegen

  describe "ToonEx.Decode.Codegen.jump_table/2" do
    test "builds jump table from ranges with default" do
      ranges = [
        {?a..?z, :lower},
        {?A..?Z, :upper}
      ]
      default = :other

      table = jump_table(ranges, default)

      assert List.keyfind(table, ?a, 0) != nil
      assert List.keyfind(table, ?Z, 0) != nil
    end
  end

  describe "ToonEx.Decode.Codegen.jump_table/3" do
    test "builds jump table with explicit max" do
      ranges = [
        {0..9, :digit}
      ]
      default = :other
      max = 255

      table = jump_table(ranges, default, max)

      assert is_list(table)
      assert length(table) >= 255
    end
  end

  describe "ToonEx.Decode.Codegen.bytecase/2 macro" do
    test "generates case on binary first byte with charlist" do
      result = quote do
        bytecase "hello" do
          _ in ~c'0123456789', rest ->
            {:number, rest}
          _ in ~c'"', rest ->
            {:string, rest}
          _, rest ->
            {:other, rest}
        end
      end

      assert Macro.expand(result, __ENV__) != nil
    end

    test "generates case with multiple byte ranges using charlists" do
      result = quote do
        bytecase <<1, 2, 3>> do
          _ in ~c'0123456789', rest ->
            {:digit, rest}
          _ in ~c'ABCDEFGHIJKLMNOPQRSTUVWXYZ', rest ->
            {:upper, rest}
          _ in ~c'abcdefghijklmnopqrstuvwxyz', rest ->
            {:lower, rest}
          _, rest ->
            {:other, rest}
        end
      end

      assert Macro.expand(result, __ENV__) != nil
    end

    test "generates case with single byte literal" do
      result = quote do
        bytecase "test" do
          _ in ~c'"', rest ->
            {:quote, rest}
          _, rest ->
            {:other, rest}
        end
      end

      assert Macro.expand(result, __ENV__) != nil
    end
  end

  describe "ToonEx.Decode.Codegen.bytecase/3 macro with max" do
    test "generates case with explicit max byte" do
      result = quote do
        bytecase "test", 200 do
          _ in ~c'0123456789', rest ->
            {:digit, rest}
          _, rest ->
            {:other, rest}
        end
      end

      assert Macro.expand(result, __ENV__) != nil
    end
  end
end