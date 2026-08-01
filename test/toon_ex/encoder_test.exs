defmodule ToonEx.EncoderTest.DerivedNoOpts do
  @moduledoc false
  @derive ToonEx.Encoder
  defstruct [:a, :b, :c]
end

defmodule ToonEx.EncoderTest.DerivedOnly do
  @moduledoc false
  @derive {ToonEx.Encoder, only: [:a]}
  defstruct [:a, :b, :c]
end

defmodule ToonEx.EncoderTest.DerivedExcept do
  @moduledoc false
  @derive {ToonEx.Encoder, except: [:secret]}
  defstruct [:a, :secret, :c]
end

defmodule ToonEx.EncoderTest do
  use ExUnit.Case, async: true

  alias ToonEx.Fixtures.{
    CustomDate,
    Person,
    StructWithoutEncoder,
    UserWithExcept,
    UserWithOnly
  }

  describe "ToonEx.Encoder for Atom" do
    test "encodes nil" do
      assert ToonEx.Encoder.encode(nil, []) == "null"
    end

    test "encodes true" do
      assert ToonEx.Encoder.encode(true, []) == "true"
    end

    test "encodes false" do
      assert ToonEx.Encoder.encode(false, []) == "false"
    end

    test "encodes regular atom as string" do
      assert ToonEx.Encoder.encode(:hello, []) == "hello"
    end
  end

  describe "ToonEx.Encoder for BitString" do
    test "encodes simple string unchanged" do
      assert ToonEx.Encoder.encode("hello", []) == "hello"
    end

    test "encodes string containing delimiter as iodata with quotes" do
      result = ToonEx.Encoder.encode("a,b", delimiter: ",")
      assert IO.iodata_to_binary(result) == "\"a,b\""
    end

    test "encodes empty string" do
      result = ToonEx.Encoder.encode("", [])
      assert IO.iodata_to_binary(result) == "\"\""
    end

    test "encodes string with tab delimiter" do
      # Tab in string triggers quoting because tab is a delimiter
      result = ToonEx.Encoder.encode("hello\tworld", delimiter: "\t")
      assert IO.iodata_to_binary(result) == "\"hello\\tworld\""
    end

    test "encodes string with pipe delimiter" do
      result = ToonEx.Encoder.encode("hello|world", delimiter: "|")
      assert IO.iodata_to_binary(result) == "\"hello|world\""
    end

    test "encodes string without delimiter does not quote" do
      assert ToonEx.Encoder.encode("hello world", []) == "hello world"
    end
  end

  describe "ToonEx.Encoder for Integer" do
    test "encodes positive integer" do
      assert ToonEx.Encoder.encode(42, []) == "42"
    end

    test "encodes negative integer" do
      assert ToonEx.Encoder.encode(-42, []) == "-42"
    end

    test "encodes zero" do
      assert ToonEx.Encoder.encode(0, []) == "0"
    end
  end

  describe "ToonEx.Encoder for Float" do
    test "encodes float" do
      result = ToonEx.Encoder.encode(3.14, [])
      assert result == "3.14"
    end

    test "encodes negative float" do
      result = ToonEx.Encoder.encode(-3.14, [])
      assert result == "-3.14"
    end
  end

  describe "ToonEx.Encoder for List" do
    test "encodes list via ToonEx.Encode" do
      result = ToonEx.Encoder.encode([1, 2, 3], [])
      assert result == "[3]: 1,2,3"
    end

    test "encodes empty list" do
      result = ToonEx.Encoder.encode([], [])
      assert result == "[0]:"
    end

    test "encodes list with custom delimiter" do
      result = ToonEx.Encoder.encode([1, 2, 3], delimiter: "\t")
      assert result == "[3\t]: 1\t2\t3"
    end

    test "encodes list of strings" do
      result = ToonEx.Encoder.encode(["a", "b", "c"], [])
      assert result == "[3]: a,b,c"
    end

    test "encodes list of booleans" do
      result = ToonEx.Encoder.encode([true, false, true], [])
      assert result == "[3]: true,false,true"
    end

    test "encodes nested lists" do
      result = ToonEx.Encoder.encode([1, [2, 3]], [])
      assert result =~ "[2]: 2,3"
    end

    test "encodes list with length_marker" do
      result = ToonEx.Encoder.encode([1, 2, 3], length_marker: "#")
      assert result == "[#3]: 1,2,3"
    end

    test "encodes list with indent option" do
      result = ToonEx.Encoder.encode([1, 2], indent: 4)
      assert result == "[2]: 1,2"
    end
  end

  describe "ToonEx.Encoder for Map" do
    test "encodes map with atom keys (converted to strings)" do
      result = ToonEx.Encoder.encode(%{name: "Alice"}, [])
      assert result == "name: Alice"
    end

    test "encodes empty map" do
      result = ToonEx.Encoder.encode(%{}, [])
      assert result == ""
    end

    test "encodes map with string keys" do
      result = ToonEx.Encoder.encode(%{"name" => "Bob"}, [])
      assert result == "name: Bob"
    end

    test "encodes nested map" do
      result = ToonEx.Encoder.encode(%{user: %{name: "Charlie"}}, [])
      assert result =~ "name: Charlie"
    end

    test "encodes map with integer values" do
      result = ToonEx.Encoder.encode(%{count: 42}, [])
      assert result == "count: 42"
    end

    test "encodes map with boolean values" do
      result = ToonEx.Encoder.encode(%{active: true}, [])
      assert result == "active: true"
    end

    test "encodes map with nil value" do
      result = ToonEx.Encoder.encode(%{missing: nil}, [])
      assert result == "missing: null"
    end

    test "encodes map with float values" do
      result = ToonEx.Encoder.encode(%{pi: 3.14}, [])
      assert result == "pi: 3.14"
    end

    test "encodes map with list values" do
      result = ToonEx.Encoder.encode(%{tags: ["a", "b"]}, [])
      assert result =~ "tags[2]: a,b"
    end
  end

  describe "ToonEx.Encoder @derive with except option" do
    test "excludes specified fields from encoding" do
      user = %UserWithExcept{name: "Alice", email: "a@b.com", password: "secret"}
      encoded_map = ToonEx.Encoder.encode(user, [])

      assert Map.has_key?(encoded_map, "name") == true
      assert Map.has_key?(encoded_map, "email") == true
      assert Map.has_key?(encoded_map, "password") == false
    end
  end

  describe "ToonEx.Encoder @derive with only option" do
    test "includes only specified fields" do
      user = %UserWithOnly{name: "Alice", email: "a@b.com", password: "secret"}
      encoded_map = ToonEx.Encoder.encode(user, [])

      assert Map.has_key?(encoded_map, "name") == true
      assert Map.has_key?(encoded_map, "email") == false
      assert Map.has_key?(encoded_map, "password") == false
    end
  end

  describe "ToonEx.Encoder @derive with no options" do
    test "includes all fields except __struct__" do
      person = %Person{name: "Bob", age: 25}
      encoded_map = ToonEx.Encoder.encode(person, [])

      assert encoded_map == %{"name" => "Bob", "age" => 25}
    end
  end

  describe "ToonEx.Encoder explicit implementation" do
    test "uses custom encode function" do
      date = %CustomDate{year: 2024, month: 1, day: 15}
      result = date |> ToonEx.Encoder.encode([]) |> IO.iodata_to_binary()

      assert result == "2024-01-15"
    end
  end

  describe "ToonEx.Encoder for unimplemented types" do
    test "raises Protocol.UndefinedError for struct without implementation" do
      struct = %StructWithoutEncoder{id: 1, value: "test"}

      assert_raise Protocol.UndefinedError,
                   ~r/protocol ToonEx.Encoder not implemented for/,
                   fn ->
                     ToonEx.Encoder.encode(struct, [])
                   end
    end

    test "raises Protocol.UndefinedError for tuple" do
      assert_raise Protocol.UndefinedError, fn ->
        ToonEx.Encoder.encode({1, 2, 3}, [])
      end
    end

    test "raises Protocol.UndefinedError for pid" do
      assert_raise Protocol.UndefinedError, fn ->
        ToonEx.Encoder.encode(self(), [])
      end
    end
  end

  describe "ToonEx.Utils.normalize/1 with structs" do
    test "dispatches to explicit ToonEx.Encoder implementation" do
      date = %CustomDate{year: 2024, month: 1, day: 15}
      assert ToonEx.Utils.normalize(date) == "2024-01-15"
    end

    test "dispatches to @derive ToonEx.Encoder" do
      user = %UserWithExcept{name: "Bob", email: "bob@test.com", password: "secret"}
      assert ToonEx.Utils.normalize(user) == %{"name" => "Bob", "email" => "bob@test.com"}
    end
  end

  # These tests verify the public API accepts structs and atom-keyed maps.
  # The Encoder protocol handles normalization, so the type specs must accept term().
  describe "ToonEx.encode!/1 accepts structs (Dialyzer compatibility)" do
    test "encodes struct with @derive ToonEx.Encoder" do
      person = %Person{name: "Alice", age: 30}
      result = ToonEx.encode!(person)

      assert result =~ "name: Alice"
      assert result =~ "age: 30"
    end

    test "encodes struct with explicit Encoder implementation" do
      date = %CustomDate{year: 2024, month: 6, day: 15}
      result = ToonEx.encode!(date)

      assert result == "2024-06-15"
    end
  end

  describe "ToonEx.encode!/1 accepts maps with atom keys (Dialyzer compatibility)" do
    test "encodes map with atom keys" do
      data = %{name: "Bob", active: true}
      result = ToonEx.encode!(data)

      assert result =~ "name: Bob"
      assert result =~ "active: true"
    end

    test "encodes nested map with atom keys" do
      data = %{user: %{name: "Charlie", age: 25}}
      result = ToonEx.encode!(data)

      assert result =~ "name: Charlie"
    end
  end

  # ── Error handling ───────────────────────────────────────────────────────────

  describe "error handling" do
    test "encode/1 returns {:error, _} for struct without encoder" do
      struct = %StructWithoutEncoder{value: 42}
      assert {:error, _} = ToonEx.encode(struct)
    end

    test "encode!/1 raises for struct without encoder" do
      struct = %StructWithoutEncoder{value: 42}

      assert_raise ToonEx.EncodeError, fn ->
        ToonEx.encode!(struct)
      end
    end
  end

  # ── Fragment encoding ────────────────────────────────────────────────────────

  describe "Fragment encoding" do
    test "encodes fragment through Encoder protocol" do
      fragment = ToonEx.Fragment.new("name: Alice")
      result = ToonEx.Encoder.encode(fragment, [])
      assert IO.iodata_to_binary(result) == "name: Alice"
    end

    test "encodes fragment with custom delimiter" do
      fragment = ToonEx.Fragment.new("a,b,c")
      result = ToonEx.Encoder.encode(fragment, delimiter: ",")
      assert IO.iodata_to_binary(result) == "a,b,c"
    end
  end

  describe "ToonEx.Encoder derive with test-local structs" do
    test "derives with no options at compile time" do
      struct = %ToonEx.EncoderTest.DerivedNoOpts{a: 1, b: 2, c: 3}
      assert struct.__struct__ == ToonEx.EncoderTest.DerivedNoOpts
      assert Map.delete(struct, :__struct__) == %{a: 1, b: 2, c: 3}
    end

    test "derives with only option at compile time" do
      struct = %ToonEx.EncoderTest.DerivedOnly{a: 1, b: 2, c: 3}
      assert struct.__struct__ == ToonEx.EncoderTest.DerivedOnly
      assert struct.b == 2
      assert struct.c == 3
    end

    test "derives with except option at compile time" do
      struct = %ToonEx.EncoderTest.DerivedExcept{a: 1, secret: "x", c: 3}
      assert struct.__struct__ == ToonEx.EncoderTest.DerivedExcept
      assert struct.secret == "x"
      assert struct.c == 3
    end
  end
end
