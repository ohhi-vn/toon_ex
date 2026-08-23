defmodule ToonEx.Btoon.Phoenix.Serializer do
  @moduledoc """
  Satisfies the `PhoenixClient` JSON-parser contract, which requires
  `encode/2`, `encode!/2`, `decode/2`, `decode!/2` and `encode_to_iodata!`.  The
  optional `opts` argument is accepted but intentionally ignored so that this
  module can be dropped in wherever a standard JSON library is expected.

  This is the BTOON binary variant of `ToonEx.Phoenix.Serializer`. Instead of
  emitting TOON text frames, messages/replies/broadcasts with map payloads are
  encoded with the compact BTOON binary format, while `{:binary, data}` payloads
  use the same dedicated length-prefixed binary frame protocol.

  ## Binary Frame Support

  Binary frames use a length-prefixed binary protocol inherited from the TOON
  serializer, so the same binary fast-path framing is supported. Map payloads
  are BTOON-encoded rather than TOON-text-encoded.

  ## Text (BTOON) Frames

  Map payloads are serialized with `Btoon.encode_to_iodata!/1` (BTOON binary),
  and `decode!/2` with `opcode: :binary` decodes them back as required by
  Phoenix WebSockets. The `:btoon` opcode is also accepted for direct use in
  applications and tests.

  This serializer is BTOON-only: incoming `:text` frames must carry a BTOON
  payload starting with the `"BTON"` magic. Anything else raises `ArgumentError`.
  Use `ToonEx.Phoenix.Serializer` for TOON text frames.

  Note: This is a workaround to avoid adding a Phoenix library dependency.
  """

  alias Phoenix.Socket.{Broadcast, Message, Reply}

  @lib ToonEx.Btoon

  @push 0
  @reply 1
  @broadcast 2

  require Logger

  def fastlane!(%{__struct__: Broadcast, payload: {:binary, data}} = msg) do
    topic_size = byte_size!(msg.topic, :topic, 255)
    event_size = byte_size!(msg.event, :event, 255)

    bin = <<
      @broadcast::size(8),
      topic_size::size(8),
      event_size::size(8),
      msg.topic::binary-size(topic_size),
      msg.event::binary-size(event_size),
      data::binary
    >>

    {:socket_push, :binary, bin}
  end

  def fastlane!(%{__struct__: Broadcast, payload: %{}} = msg) do
    data = @lib.encode_to_iodata!([nil, nil, msg.topic, msg.event, msg.payload])
    {:socket_push, :binary, data}
  end

  def fastlane!(%{__struct__: Broadcast, payload: invalid}) do
    raise ArgumentError, "expected broadcasted payload to be a map, got: #{inspect(invalid)}"
  end

  def encode!(%{__struct__: Reply, payload: {:binary, data}} = reply) do
    status = to_string(reply.status)
    join_ref = to_string(reply.join_ref)
    ref = to_string(reply.ref)
    join_ref_size = byte_size!(join_ref, :join_ref, 255)
    ref_size = byte_size!(ref, :ref, 255)
    topic_size = byte_size!(reply.topic, :topic, 255)
    status_size = byte_size!(status, :status, 255)

    bin = <<
      @reply::size(8),
      join_ref_size::size(8),
      ref_size::size(8),
      topic_size::size(8),
      status_size::size(8),
      join_ref::binary-size(join_ref_size),
      ref::binary-size(ref_size),
      reply.topic::binary-size(topic_size),
      status::binary-size(status_size),
      data::binary
    >>

    {:socket_push, :binary, bin}
  end

  def encode!(%{__struct__: Reply} = reply) do
    Logger.debug(fn -> "custom btoon serializer encoding reply: #{inspect(reply)}" end)

    data = [
      reply.join_ref,
      reply.ref,
      reply.topic,
      "phx_reply",
      %{status: reply.status, response: reply.payload}
    ]

    {:socket_push, :binary, @lib.encode_to_iodata!(data)}
  end

  def encode!(%{__struct__: Message, payload: {:binary, data}} = msg) do
    join_ref = to_string(msg.join_ref)
    join_ref_size = byte_size!(join_ref, :join_ref, 255)
    topic_size = byte_size!(msg.topic, :topic, 255)
    event_size = byte_size!(msg.event, :event, 255)

    bin = <<
      @push::size(8),
      join_ref_size::size(8),
      topic_size::size(8),
      event_size::size(8),
      join_ref::binary-size(join_ref_size),
      msg.topic::binary-size(topic_size),
      msg.event::binary-size(event_size),
      data::binary
    >>

    {:socket_push, :binary, bin}
  end

  def encode!(%{__struct__: Message, payload: %{}} = msg) do
    Logger.debug(fn -> "custom btoon serializer encoding msg: #{inspect(msg)}" end)

    data = [msg.join_ref, msg.ref, msg.topic, msg.event, msg.payload]

    {:socket_push, :binary, @lib.encode_to_iodata!(data)}
  end

  def encode!(%{__struct__: Message, payload: invalid}) do
    raise ArgumentError, "expected payload to be a map, got: #{inspect(invalid)}"
  end

  def decode!(raw_message, opts) do
    case Keyword.fetch(opts, :opcode) do
      {:ok, :text} -> decode_text(raw_message)
      {:ok, :btoon} -> decode_btoon(raw_message)
      {:ok, :binary} -> decode_binary(raw_message)
    end
  end

  def decode_text(<<"BTON", _rest::binary>> = raw_message), do: decode_btoon(raw_message)

  def decode_text(raw_message) do
    raise ArgumentError,
          "expected a BTOON frame starting with the \"BTON\" magic, got: #{inspect(raw_message)}"
  end

  def decode_btoon(raw_message) do
    Logger.debug(fn -> "custom btoon serializer decoding raw msg: #{inspect(raw_message)}" end)
    [join_ref, ref, topic, event, payload | _] = @lib.decode!(raw_message)
    message(join_ref, ref, topic, event, payload)
  end

  defp message(join_ref, ref, topic, event, payload) do
    %{
      __struct__: Message,
      topic: topic,
      event: event,
      payload: payload,
      ref: ref,
      join_ref: join_ref
    }
  end

  defp decode_binary(
         <<
           "BTON",
           _rest::binary
         >> = raw_message
       ) do
    decode_btoon(raw_message)
  end

  defp decode_binary(<<
         @push::size(8),
         join_ref_size::size(8),
         ref_size::size(8),
         topic_size::size(8),
         event_size::size(8),
         join_ref::binary-size(join_ref_size),
         ref::binary-size(ref_size),
         topic::binary-size(topic_size),
         event::binary-size(event_size),
         data::binary
       >>) do
    %{
      __struct__: Message,
      topic: topic,
      event: event,
      payload: {:binary, data},
      ref: ref,
      join_ref: join_ref
    }
  end

  defp byte_size!(bin, kind, max) do
    case byte_size(bin) do
      size when size <= max ->
        size

      oversized ->
        raise ArgumentError, """
        unable to convert #{kind} to binary.

            #{inspect(bin)}

        must be less than or equal to #{max} bytes, but is #{oversized} bytes.
        """
    end
  end
end
