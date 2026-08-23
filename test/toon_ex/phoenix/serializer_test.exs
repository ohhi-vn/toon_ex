defmodule ToonEx.Phoenix.SerializerTest do
  use ExUnit.Case, async: true

  alias Phoenix.Socket.{Broadcast, Message, Reply}
  alias ToonEx.Phoenix.Serializer

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

  # ── fastlane!/1 ──────────────────────────────────────────────────────────────

  describe "fastlane!/1 with binary payload" do
    test "encodes broadcast with binary payload as binary frame" do
      msg = broadcast(topic: "room:1", event: "new_msg", payload: {:binary, <<"hello">>})
      result = Serializer.fastlane!(msg)

      assert {:socket_push, :binary, bin} = result
      assert is_binary(bin)
    end

    test "binary frame has correct type byte (2 for broadcast)" do
      msg = broadcast(topic: "room:1", event: "new_msg", payload: {:binary, <<"data">>})
      {:socket_push, :binary, bin} = Serializer.fastlane!(msg)

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
    test "encodes broadcast with map payload as text frame" do
      msg = broadcast(topic: "room:1", event: "new_msg", payload: %{"text" => "hello"})
      result = Serializer.fastlane!(msg)

      assert {:socket_push, :text, _data} = result
    end

    test "text frame contains encoded TOON data" do
      msg = broadcast(topic: "room:1", event: "new_msg", payload: %{"text" => "hello"})
      {:socket_push, :text, data} = Serializer.fastlane!(msg)

      decoded = ToonEx.decode!(IO.iodata_to_binary(data))
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

  # ── encode!/1 ────────────────────────────────────────────────────────────────

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

      result = Serializer.encode!(reply)

      assert {:socket_push, :binary, _bin} = result
    end

    test "binary frame has correct type byte (1 for reply)" do
      reply =
        reply(
          topic: "room:1",
          join_ref: "jr",
          ref: "r1",
          status: "ok",
          payload: {:binary, <<"data">>}
        )

      {:socket_push, :binary, bin} = Serializer.encode!(reply)

      assert <<1::size(8), _::binary>> = bin
    end

    test "binary frame contains all reply fields" do
      reply =
        reply(
          topic: "room:1",
          join_ref: "jr",
          ref: "r1",
          status: "ok",
          payload: {:binary, <<"data">>}
        )

      {:socket_push, :binary, bin} = Serializer.encode!(reply)

      <<1::size(8), join_ref_size::size(8), ref_size::size(8), topic_size::size(8),
        status_size::size(8), join_ref::binary-size(join_ref_size), ref::binary-size(ref_size),
        topic::binary-size(topic_size), status::binary-size(status_size), data::binary>> = bin

      assert join_ref == "jr"
      assert ref == "r1"
      assert topic == "room:1"
      assert status == "ok"
      assert data == "data"
    end
  end

  describe "encode!/1 with Reply map payload" do
    test "encodes reply with map payload as text frame" do
      reply =
        reply(
          topic: "room:1",
          join_ref: "jr",
          ref: "r1",
          status: "ok",
          payload: %{"text" => "hello"}
        )

      result = Serializer.encode!(reply)

      assert {:socket_push, :text, _data} = result
    end

    test "text frame contains encoded TOON with phx_reply wrapper" do
      reply =
        reply(
          topic: "room:1",
          join_ref: "jr",
          ref: "r1",
          status: "ok",
          payload: %{"text" => "hello"}
        )

      {:socket_push, :text, data} = Serializer.encode!(reply)

      decoded = ToonEx.decode!(IO.iodata_to_binary(data))
      [_join_ref, _ref, _topic, "phx_reply", inner | _] = decoded

      assert inner["status"] == "ok"
      assert inner["response"] == %{"text" => "hello"}
    end
  end

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

      result = Serializer.encode!(msg)

      assert {:socket_push, :binary, _bin} = result
    end

    test "binary frame has correct type byte (0 for push)" do
      msg =
        message(
          topic: "room:1",
          event: "new_msg",
          join_ref: "jr",
          ref: "r1",
          payload: {:binary, <<"data">>}
        )

      {:socket_push, :binary, bin} = Serializer.encode!(msg)

      assert <<0::size(8), _::binary>> = bin
    end

    test "binary frame contains message fields" do
      msg =
        message(
          topic: "room:1",
          event: "new_msg",
          join_ref: "jr",
          ref: "r1",
          payload: {:binary, <<"data">>}
        )

      {:socket_push, :binary, bin} = Serializer.encode!(msg)

      # Binary push format: push(0), sizes, join_ref, topic, event, data.
      <<0::size(8), join_ref_size::size(8), topic_size::size(8), event_size::size(8),
        join_ref::binary-size(join_ref_size), topic::binary-size(topic_size),
        event::binary-size(event_size), data::binary>> = bin

      assert join_ref == "jr"
      assert topic == "room:1"
      assert event == "new_msg"
      assert data == "data"
    end
  end

  describe "encode!/1 with Message map payload" do
    test "encodes message with map payload as text frame" do
      msg =
        message(
          topic: "room:1",
          event: "new_msg",
          join_ref: "jr",
          ref: "r1",
          payload: %{"text" => "hello"}
        )

      result = Serializer.encode!(msg)

      assert {:socket_push, :text, _data} = result
    end

    test "text frame contains encoded TOON" do
      msg =
        message(
          topic: "room:1",
          event: "new_msg",
          join_ref: "jr",
          ref: "r1",
          payload: %{"text" => "hello"}
        )

      {:socket_push, :text, data} = Serializer.encode!(msg)

      decoded = ToonEx.decode!(IO.iodata_to_binary(data))
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

  describe "decode!/2 with text opcode" do
    test "decodes text frame to Message struct" do
      msg =
        message(
          topic: "room:1",
          event: "new_msg",
          join_ref: "jr",
          ref: "r1",
          payload: %{"text" => "hello"}
        )

      {:socket_push, :text, data} = Serializer.encode!(msg)

      decoded = Serializer.decode!(IO.iodata_to_binary(data), opcode: :text)

      assert decoded.topic == "room:1"
      assert decoded.event == "new_msg"
      assert decoded.join_ref == "jr"
      assert decoded.ref == "r1"
      assert decoded.payload == %{"text" => "hello"}
    end
  end

  describe "decode!/2 with binary opcode" do
    test "round-trips a binary reply frame" do
      reply =
        reply(
          topic: "room:1",
          join_ref: "jr",
          ref: "r1",
          status: "ok",
          payload: {:binary, <<"data">>}
        )

      {:socket_push, :binary, bin} = Serializer.encode!(reply)
      decoded = Serializer.decode!(bin, opcode: :binary)

      assert decoded.__struct__ == Phoenix.Socket.Reply
      assert decoded.topic == "room:1"
      assert decoded.join_ref == "jr"
      assert decoded.ref == "r1"
      assert decoded.status == :ok
      assert decoded.payload == {:binary, <<"data">>}
    end

    test "decodes binary push frame - format matches what encode! produces" do
      msg =
        message(
          topic: "room:1",
          event: "new_msg",
          join_ref: "jr",
          ref: "r1",
          payload: {:binary, <<"data">>}
        )

      {:socket_push, :binary, bin} = Serializer.encode!(msg)
      decoded = Serializer.decode!(bin, opcode: :binary)

      # encode!/1 does not serialize the ref for binary push frames
      assert decoded.__struct__ == Phoenix.Socket.Message
      assert decoded.topic == "room:1"
      assert decoded.event == "new_msg"
      assert decoded.join_ref == "jr"
      assert decoded.ref == nil
      assert decoded.payload == {:binary, <<"data">>}
    end

    test "round-trips a binary broadcast frame" do
      broadcast =
        broadcast(topic: "room:1", event: "new_msg", payload: {:binary, <<"data">>})

      {:socket_push, :binary, bin} = Serializer.fastlane!(broadcast)
      decoded = Serializer.decode!(bin, opcode: :binary)

      assert decoded.__struct__ == Phoenix.Socket.Broadcast
      assert decoded.topic == "room:1"
      assert decoded.event == "new_msg"
      assert decoded.payload == {:binary, <<"data">>}
    end

    test "raises ArgumentError on malformed binary frames" do
      assert_raise ArgumentError, fn ->
        Serializer.decode!(<<255, 1, 2, 3>>, opcode: :binary)
      end
    end
  end

  describe "decode!/2 with missing opcode" do
    test "raises CaseClauseError when opcode is not provided" do
      assert_raise CaseClauseError, fn ->
        Serializer.decode!("data", [])
      end
    end
  end

  # ── byte_size!/3 (via large field validation) ───────────────────────────────

  describe "byte_size!/3 validation" do
    test "raises when topic exceeds 255 bytes" do
      long_topic = String.duplicate("a", 256)
      msg = broadcast(topic: long_topic, event: "e", payload: {:binary, <<>>})

      assert_raise ArgumentError, ~r/unable to convert topic to binary/, fn ->
        Serializer.fastlane!(msg)
      end
    end

    test "raises when event exceeds 255 bytes" do
      long_event = String.duplicate("b", 256)
      msg = broadcast(topic: "t", event: long_event, payload: {:binary, <<>>})

      assert_raise ArgumentError, ~r/unable to convert event to binary/, fn ->
        Serializer.fastlane!(msg)
      end
    end

    test "raises when join_ref exceeds 255 bytes" do
      long_join_ref = String.duplicate("j", 256)

      msg =
        message(
          topic: "t",
          event: "e",
          join_ref: long_join_ref,
          ref: "r",
          payload: {:binary, <<>>}
        )

      assert_raise ArgumentError, ~r/unable to convert join_ref to binary/, fn ->
        Serializer.encode!(msg)
      end
    end

    test "raises when ref exceeds 255 bytes in reply encoding" do
      long_ref = String.duplicate("r", 256)

      reply =
        reply(topic: "t", join_ref: "j", ref: long_ref, status: "ok", payload: {:binary, <<>>})

      assert_raise ArgumentError, ~r/unable to convert ref to binary/, fn ->
        Serializer.encode!(reply)
      end
    end
  end

  # ── Text frame round-trip ────────────────────────────────────────────────────

  describe "text frame round-trip" do
    test "message round-trips through text encode/decode" do
      original =
        message(
          topic: "room:lobby",
          event: "update",
          join_ref: "jr",
          ref: "ref1",
          payload: %{"data" => "value"}
        )

      {:socket_push, :text, data} = Serializer.encode!(original)
      decoded = Serializer.decode!(IO.iodata_to_binary(data), opcode: :text)

      assert decoded.topic == "room:lobby"
      assert decoded.event == "update"
      assert decoded.join_ref == "jr"
      assert decoded.ref == "ref1"
      assert decoded.payload == %{"data" => "value"}
    end

    test "broadcast round-trips through text encode/decode" do
      original = broadcast(topic: "room:1", event: "new_msg", payload: %{"text" => "hello"})
      {:socket_push, :text, data} = Serializer.fastlane!(original)
      decoded = Serializer.decode!(IO.iodata_to_binary(data), opcode: :text)

      assert decoded.topic == "room:1"
      assert decoded.event == "new_msg"
      assert decoded.payload == %{"text" => "hello"}
    end

    test "reply round-trips through text encode/decode" do
      original =
        reply(
          topic: "room:1",
          join_ref: "jr",
          ref: "r1",
          status: "ok",
          payload: %{"response" => "ok"}
        )

      {:socket_push, :text, data} = Serializer.encode!(original)
      decoded = Serializer.decode!(IO.iodata_to_binary(data), opcode: :text)

      assert decoded.topic == "room:1"
      assert decoded.event == "phx_reply"
      assert decoded.join_ref == "jr"
      assert decoded.ref == "r1"
      assert decoded.payload["status"] == "ok"
      assert decoded.payload["response"] == %{"response" => "ok"}
    end
  end
end
