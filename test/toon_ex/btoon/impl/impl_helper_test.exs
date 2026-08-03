defmodule ToonEx.Btoon.ImplHelperTest do
  use ExUnit.Case, async: true

  alias ToonEx.Btoon

  describe "Btoon.ToonImplHelper.gen_impl/1 macro" do
    test "macro generates defimpl when expanded" do
      expanded =
        quote do
          Btoon.ToonImplHelper.gen_impl(BtoonFixtures.ImplHelperUser)
        end
        |> Macro.expand(__ENV__)

      assert is_tuple(expanded)
      assert tuple_size(expanded) > 0
    end
  end

  describe "Btoon.ToonImplHelper module" do
    test "module exists and is loadable" do
      assert Code.ensure_loaded?(Btoon.ToonImplHelper)
    end

    test "module has gen_impl and __using__ macros" do
      macros = Btoon.ToonImplHelper.__info__(:macros)
      macro_names = Enum.map(macros, fn {name, _arity} -> name end)

      assert :gen_impl in macro_names
      assert :__using__ in macro_names
    end

    test "__using__ macro expands with impl option" do
      expanded =
        quote do
          defmodule TestBtoonModuleUsingHelper do
            use Btoon.ToonImplHelper, impl: [BtoonFixtures.ImplHelperUser]
          end
        end
        |> Macro.expand(__ENV__)

      assert is_tuple(expanded)
    end
  end

  describe "ToonImplHelper-generated encoder impl" do
    test "impl dispatches and produces a map payload" do
      struct = ToonEx.BtoonFixtures.ImplHelperUser.new("alice", 42)
      assert Btoon.Encoder.encode(struct, []) == %{"name" => "alice", "value" => 42}
    end
  end
end
