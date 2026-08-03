defmodule ToonEx.Btoon.Phoenix.SerializerTest do
  use ExUnit.Case, async: true

  alias Phoenix.Socket.{Broadcast, Message, Reply}
  alias ToonEx.Btoon
  alias ToonEx.Btoon.Phoenix.Serializer

  # ── Helper: create mock Phoenix structs (Phoenix is not a test dependency) ──

  def message(attrs) do
    Map.put(Map.new(attrs), :__struct__, Message)
  end

  def broadcast(attrs) do
    Map.put(Map.new(attrs), :__struct__, Broadcast)
  end

  def reply(attrs) do
    Map.put(Map.new(attrs), :__struct__, Reply)
  end

  # ── fastlane!/1 with binary payload ──────────────────────────────────────────

  describe "fastlane!/1 with binary payload" do
    test "encodes broadcast with binary payload as binary frame" do
      msg = broadcast(topic: "room:1", event: "new_msg", payload: {:binary, <<"hello">>})
      assert {:socket_push, :binary, bin} = Serializer.fastlane!(msg)
      assert is_binary(bin)
      assert <<2::size(8), _::binary>> = bin
    end

    test "binary frame contains topic and event" do
      msg = broadcast(topic: "room:1", event: "new_msg", payload: {:binary, <<"data">>})
      {:socket_push, :binary, bin} = Serializer.fastlane!(msg)

      <<2::size(8), topic_size::size(8), event_size::size(8), topic::binary-size(topic_size),
        event::binary-size(event_size), data::binary>> = bin

      assert topic == "room:1"
      assert event == "new_msg"
      assert data == "data"
    end
  end

  describe "fastlane!/1 with map payload" do
    test "encodes broadcast with map payload as BTOON binary frame" do
      msg = broadcast(topic: "room:1", event: "new_msg", payload: %{"text" => "hello"})
      assert {:socket_push, :binary, _data} = Serializer.fastlane!(msg)
    end

    test "binary frame decodes as BTOON data" do
      msg = broadcast(topic: "room:1", event: "new_msg", payload: %{"text" => "hello"})
      {:socket_push, :binary, data} = Serializer.fastlane!(msg)

      decoded = Btoon.decode!(IO.iodata_to_binary(data))
      [nil, nil, topic, event, payload | _] = decoded

      assert topic == "room:1"
      assert event == "new_msg"
      assert payload == %{"text" => "hello"}
    end
  end

  describe "fastlane!/1 with invalid payload" do
    test "raises ArgumentError for non-binary, non-map payload" do
      msg = broadcast(topic: "room:1", event: "new_msg", payload: "invalid")

      assert_raise ArgumentError, ~r/expected broadcasted payload to be a map/, fn ->
        Serializer.fastlane!(msg)
      end
    end
  end

  # ── encode!/1 with Reply ─────────────────────────────────────────────────────

  describe "encode!/1 with Reply binary payload" do
    test "encodes reply with binary payload as binary frame" do
      reply =
        reply(
          topic: "room:1",
          join_ref: "jr",
          ref: "r1",
          status: "ok",
          payload: {:binary, <<"data">>}
        )

      assert {:socket_push, :binary, bin} = Serializer.encode!(reply)
      assert <<1::size(8), _::binary>> = bin
    end
  end

  describe "encode!/1 with Reply map payload" do
    test "encodes reply with map payload as BTOON binary frame" do
      reply =
        reply(
          topic: "room:1",
          join_ref: "jr",
          ref: "r1",
          status: "ok",
          payload: %{"text" => "hello"}
        )

      assert {:socket_push, :binary, _data} = Serializer.encode!(reply)
    end

    test "BTOON frame contains phx_reply wrapper" do
      reply =
        reply(
          topic: "room:1",
          join_ref: "jr",
          ref: "r1",
          status: "ok",
          payload: %{"text" => "hello"}
        )

      {:socket_push, :binary, data} = Serializer.encode!(reply)

      decoded = Btoon.decode!(IO.iodata_to_binary(data))
      [_join_ref, _ref, _topic, "phx_reply", inner | _] = decoded

      assert inner["status"] == "ok"
      assert inner["response"] == %{"text" => "hello"}
    end
  end

  # ── encode!/1 with Message ───────────────────────────────────────────────────

  describe "encode!/1 with Message binary payload" do
    test "encodes message with binary payload as binary frame" do
      msg =
        message(
          topic: "room:1",
          event: "new_msg",
          join_ref: "jr",
          ref: "r1",
          payload: {:binary, <<"data">>}
        )

      assert {:socket_push, :binary, bin} = Serializer.encode!(msg)
      assert <<0::size(8), _::binary>> = bin
    end
  end

  describe "encode!/1 with Message map payload" do
    test "encodes message with map payload as BTOON binary frame" do
      msg =
        message(
          topic: "room:1",
          event: "new_msg",
          join_ref: "jr",
          ref: "r1",
          payload: %{"text" => "hello"}
        )

      assert {:socket_push, :binary, _data} = Serializer.encode!(msg)
    end

    test "BTOON frame decodes to message data" do
      msg =
        message(
          topic: "room:1",
          event: "new_msg",
          join_ref: "jr",
          ref: "r1",
          payload: %{"text" => "hello"}
        )

      {:socket_push, :binary, data} = Serializer.encode!(msg)

      decoded = Btoon.decode!(IO.iodata_to_binary(data))
      [join_ref, ref, topic, event, payload | _] = decoded

      assert join_ref == "jr"
      assert ref == "r1"
      assert topic == "room:1"
      assert event == "new_msg"
      assert payload == %{"text" => "hello"}
    end
  end

  describe "encode!/1 with invalid Message payload" do
    test "raises ArgumentError for non-binary, non-map payload" do
      msg = message(topic: "room:1", event: "new_msg", join_ref: "jr", ref: "r1", payload: 42)

      assert_raise ArgumentError, ~r/expected payload to be a map/, fn ->
        Serializer.encode!(msg)
      end
    end
  end

  # ── decode!/2 ────────────────────────────────────────────────────────────────

  describe "decode!/2 with btoon opcode" do
    test "decodes BTOON frame to Message struct" do
      msg =
        message(
          topic: "room:1",
          event: "new_msg",
          join_ref: "jr",
          ref: "r1",
          payload: %{"text" => "hello"}
        )

      {:socket_push, :binary, data} = Serializer.encode!(msg)
      decoded = Serializer.decode!(IO.iodata_to_binary(data), opcode: :btoon)

      assert decoded.topic == "room:1"
      assert decoded.event == "new_msg"
      assert decoded.join_ref == "jr"
      assert decoded.ref == "r1"
      assert decoded.payload == %{"text" => "hello"}
    end
  end

  describe "decode!/2 with binary opcode" do
    test "binary push frame format does not match decode_binary expected layout" do
      msg =
        message(
          topic: "room:1",
          event: "new_msg",
          join_ref: "jr",
          ref: "r1",
          payload: {:binary, <<"data">>}
        )

      {:socket_push, :binary, bin} = Serializer.encode!(msg)

      # Same documented format mismatch as the TOON serializer: encode! writes
      # push(0), join_ref_size, topic_size, event_size, join_ref, topic, event, data
      # whereas decode_binary expects join_ref_size, ref_size, topic_size, event_size...
      assert_raise FunctionClauseError, fn ->
        Serializer.decode!(bin, opcode: :binary)
      end
    end
  end

  describe "decode!/2 with missing opcode" do
    test "raises CaseClauseError when opcode is not provided" do
      assert_raise CaseClauseError, fn -> Serializer.decode!("data", []) end
    end
  end

  # ── BTOON text/binary round-trip ─────────────────────────────────────────────

  describe "BTOON frame round-trip" do
    test "message round-trips through BTOON encode/decode" do
      original =
        message(
          topic: "room:lobby",
          event: "update",
          join_ref: "jr",
          ref: "ref1",
          payload: %{"data" => "value"}
        )

      {:socket_push, :binary, data} = Serializer.encode!(original)
      decoded = Serializer.decode!(IO.iodata_to_binary(data), opcode: :btoon)

      assert decoded.topic == "room:lobby"
      assert decoded.event == "update"
      assert decoded.join_ref == "jr"
      assert decoded.ref == "ref1"
      assert decoded.payload == %{"data" => "value"}
    end

    test "broadcast round-trips through BTOON encode/decode" do
      original = broadcast(topic: "room:1", event: "new_msg", payload: %{"text" => "hello"})
      {:socket_push, :binary, data} = Serializer.fastlane!(original)
      decoded = Serializer.decode!(IO.iodata_to_binary(data), opcode: :btoon)

      assert decoded.topic == "room:1"
      assert decoded.event == "new_msg"
      assert decoded.payload == %{"text" => "hello"}
    end
  end
end
