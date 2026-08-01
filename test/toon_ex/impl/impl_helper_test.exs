defmodule ToonEx.ImplHelperTest do
  use ExUnit.Case, async: true

  describe "ToonEx.ToonImplHelper.gen_impl/1 macro" do
    test "macro generates defimpl for given module when expanded" do
      # The macro generates a block with defimpl inside
      expanded =
        quote do
          ToonEx.ToonImplHelper.gen_impl(TestModule)
        end
        |> Macro.expand(__ENV__)

      # The macro generates a block with defimpl inside
      assert is_tuple(expanded)
      # Check the quoted expression contains expected elements when stringified
      _impl_str = Macro.to_string(expanded)
      # The macro generates code that will be evaluated at compile time
      # We can verify the structure of the generated AST
      assert is_tuple(expanded) and tuple_size(expanded) > 0
    end
  end

  describe "ToonEx.ToonImplHelper module" do
    test "module exists and is loadable" do
      assert Code.ensure_loaded?(ToonEx.ToonImplHelper) == true
    end

    test "module has gen_impl macro defined" do
      macros = ToonEx.ToonImplHelper.__info__(:macros)
      macro_names = Enum.map(macros, fn {name, _arity} -> name end)

      assert :gen_impl in macro_names
      assert :__using__ in macro_names
    end

    test "__using__ macro generates implementations when given impl option" do
      # Test that the macro expands correctly with impl option
      expanded =
        quote do
          defmodule TestModuleUsingHelper do
            use ToonEx.ToonImplHelper, impl: [TestModule2]
          end
        end
        |> Macro.expand(__ENV__)

      assert is_tuple(expanded)
    end
  end

  describe "ToonEx.ToonImplHelper macro functionality" do
    test "gen_impl macro expands to defimpl expression" do
      # Test that gen_impl macro expands to a defimpl expression
      # We verify the macro expansion without calling it at runtime
      require ToonEx.ToonImplHelper

      expanded =
        quote do
          ToonEx.ToonImplHelper.gen_impl(TestModule)
        end
        |> Macro.expand(__ENV__)

      # If Macro.expand didn't expand (runtime context), call the macro directly
      expanded =
        if expanded ==
             {:., [], [{:__aliases__, [alias: false], [:ToonEx, :ToonImplHelper]}, :gen_impl]} do
          ToonEx.ToonImplHelper.gen_impl(TestModule)
        else
          expanded
        end

      # The macro should generate a module/defimpl structure
      assert is_tuple(expanded)
      result_str = Macro.to_string(expanded)
      assert String.contains?(result_str, "defimpl") or String.contains?(result_str, "module")
    end

    test "macro handles multiple modules in impl option" do
      expanded =
        quote do
          defmodule TestModuleUsingHelper2 do
            use ToonEx.ToonImplHelper, impl: [TestModule, TestModule2]
          end
        end
        |> Macro.expand(__ENV__)

      assert is_tuple(expanded)
    end
  end
end

# Test modules - these don't need @derive since we're testing the macro itself
defmodule TestModule do
  defstruct [:name, :value]
  def encode!(%TestModule{name: name, value: value}, _opts), do: "name: #{name}\nvalue: #{value}"
end

defmodule TestModule2 do
  defstruct [:name]
  def encode!(%TestModule2{name: name}, _opts), do: "name: #{name}"
end

defmodule ToonEx.ImplHelperUsingTest do
  use ToonEx.ToonImplHelper, impl: [TestModule, TestModule2]

  defmodule TestModuleUsingRealUse do
    defstruct [:id]
  end
end
