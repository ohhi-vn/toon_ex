defmodule ToonEx.Btoon.EncoderAnyTest do
  use ExUnit.Case, async: true

  alias ToonEx.Btoon
  alias ToonEx.BtoonFixtures.{DerivedAll, ImplHelperUser}

  describe "fallback Any implementation" do
    test "structs without an implementation raise Protocol.UndefinedError" do
      assert_raise ToonEx.Btoon.EncodeError,
                   ~r/must be explicitly implemented/,
                   fn ->
                     Btoon.encode!(%ToonEx.Fixtures.StructWithoutEncoder{id: 1, value: "x"})
                   end

      # Calling the protocol directly surfaces the raw Protocol.UndefinedError.
      assert_raise Protocol.UndefinedError, fn ->
        ToonEx.Btoon.Encoder.encode(%ToonEx.Fixtures.StructWithoutEncoder{}, [])
      end
    end

    test "non-struct terms without implementations raise" do
      assert_raise Protocol.UndefinedError, fn ->
        Btoon.Encoder.encode(:erlang.make_ref(), [])
      end

      assert_raise Protocol.UndefinedError, fn ->
        Btoon.Encoder.encode(self(), [])
      end
    end
  end

  describe "derived encoders cover all option shapes" do
    test "except: keeps every field not listed" do
      struct = %ToonEx.BtoonFixtures.DerivedExcept{name: "n", secret: "s3cr3t", role: "admin"}

      decoded = Btoon.decode!(Btoon.encode!(struct))
      assert decoded == %{"name" => "n", "role" => "admin"}
      refute Map.has_key?(decoded, "secret")
    end

    test "derived struct values recurse through normal BTOON dispatch" do
      inner = %DerivedAll{a: 1, b: "two"}

      decoded = Btoon.decode!(Btoon.encode!(%{"wrap" => inner, "list" => [inner]}))

      assert decoded["wrap"] == %{"a" => 1, "b" => "two"}
      assert decoded["list"] == [%{"a" => 1, "b" => "two"}]
    end

    test "manual defimpl participates identically" do
      user = ImplHelperUser.new("ada", 36)

      assert Btoon.decode!(Btoon.encode!(user)) == %{"name" => "ada", "value" => 36}
    end
  end
end
