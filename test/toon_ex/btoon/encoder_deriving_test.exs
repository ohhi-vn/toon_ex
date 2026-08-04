defmodule ToonEx.Btoon.EncoderDerivingTest do
  use ExUnit.Case, async: true

  alias ToonEx.Btoon
  alias ToonEx.BtoonFixtures.{ComplexStruct, DerivedAll, DerivedExcept, DerivedUser}

  describe "derived BTOON encoders" do
    test "only: encodes selected fields" do
      user = %DerivedUser{id: 1, name: "Alice", email: "a@example.com", password_hash: "hash"}

      assert Btoon.decode!(Btoon.encode!(user)) == %{
               "name" => "Alice",
               "email" => "a@example.com"
             }
    end

    test "except: omits listed fields" do
      s = %DerivedExcept{name: "N", secret: "s3cret", role: "admin"}

      assert Btoon.decode!(Btoon.encode!(s)) == %{
               "name" => "N",
               "role" => "admin"
             }
    end

    test "no options encodes all fields" do
      s = %DerivedAll{a: 1, b: "two"}

      assert Btoon.decode!(Btoon.encode!(s)) == %{"a" => 1, "b" => "two"}
    end

    test "derived struct nested inside a map" do
      user = %DerivedUser{id: 1, name: "Alice", email: "a@example.com", password_hash: "h"}
      data = %{"user" => user, "role" => "admin"}

      assert Btoon.decode!(Btoon.encode!(data)) == %{
               "user" => %{"name" => "Alice", "email" => "a@example.com"},
               "role" => "admin"
             }
    end

    test "encodes a complex struct with nested structs and collections" do
      owner = %DerivedUser{name: "Alice", email: "a@example.com"}
      members = [%DerivedAll{a: 1, b: "one"}, %DerivedAll{a: 2, b: "two"}]

      value = %ComplexStruct{
        id: 42,
        owner: owner,
        members: members,
        metadata: %{"region" => "eu-west", "retries" => 3},
        active: true,
        created_at: ~U[2026-01-02 03:04:05Z]
      }

      assert Btoon.decode!(Btoon.encode!(value)) == %{
               "id" => 42,
               "owner" => %{"name" => "Alice", "email" => "a@example.com"},
               "members" => [%{"a" => 1, "b" => "one"}, %{"a" => 2, "b" => "two"}],
               "metadata" => %{"region" => "eu-west", "retries" => 3},
               "active" => true,
               "created_at" => "2026-01-02T03:04:05Z"
             }
    end
  end
end
