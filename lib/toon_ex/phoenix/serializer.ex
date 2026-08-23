defmodule ToonEx.Phoenix.Serializer do
  @moduledoc """
  Satisfies the `PhoenixClient` JSON-parser contract, which requires
  `encode/2`, `encode!/2`, `decode/2`, `decode!/2` and `encode_to_iodata!`.  The optional
  `opts` argument is accepted but intentionally ignored so that this
  module can be dropped in wherever a standard JSON library is expected.

  Updates `endpoint.ex` to use this serializer.

  ```elixir
  socket "/socket", MyAppWeb.ChannelSocket,
      websocket: [
        connect_info: [:peer_data],
        serializer: [{ToonEx.Phoenix.Serializer, "~> 2.0.0"}]
      ],
      longpoll: false
  ```

  ## Binary Frame Support

  In addition to text-based TOON encoding, this serializer supports compact
  binary frames for `Phoenix.Socket.Message`, `Phoenix.Socket.Broadcast`, and
  `Phoenix.Socket.Reply` structs. Binary frames use a length-prefixed binary
  protocol that avoids the overhead of text serialization.

  - `fastlane!/1` — Binary-encoded broadcasts (`Phoenix.Socket.Broadcast` with `{:binary, data}` payload)
  - `encode!/1` — Binary-encoded replies and messages with `{:binary, data}` payloads
  - `decode!/2` — Decodes both text and binary frames (pass `opcode: :text` or `opcode: :binary`)

  Note: This is a workround for avoid add Phoenix library dependency.
  """

  alias Phoenix.Socket.{Broadcast, Message, Reply}

  @lib ToonEx

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
    {:socket_push, :text, data}
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
    Logger.debug(fn -> "custom serializer encoding reply: #{inspect(reply)}" end)

    data = [
      reply.join_ref,
      reply.ref,
      reply.topic,
      "phx_reply",
      %{status: reply.status, response: reply.payload}
    ]

    {:socket_push, :text, @lib.encode_to_iodata!(data)}
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
    Logger.debug(fn -> "custom serializer encoding msg: #{inspect(msg)}" end)

    data = [msg.join_ref, msg.ref, msg.topic, msg.event, msg.payload]

    {:socket_push, :text, @lib.encode_to_iodata!(data)}
  end

  def encode!(%{__struct__: Message, payload: invalid}) do
    raise ArgumentError, "expected payload to be a map, got: #{inspect(invalid)}"
  end

  def decode!(raw_message, opts) do
    case Keyword.fetch(opts, :opcode) do
      {:ok, :text} -> decode_text(raw_message)
      {:ok, :binary} -> decode_binary(raw_message)
    end
  end

  def decode_text(raw_message) do
    Logger.debug(fn -> "custom serializer decoding raw text msg: #{inspect(raw_message)}" end)
    [join_ref, ref, topic, event, payload | _] = @lib.decode!(raw_message)

    %{
      __struct__: Message,
      topic: topic,
      event: event,
      payload: payload,
      ref: ref,
      join_ref: join_ref
    }
  end

  # Matches the exact wire format produced by encode!/1 for
  # %Phoenix.Socket.Message{} with a {:binary, data} payload:
  # <<type, join_ref_size, topic_size, event_size, join_ref, topic, event, data>>
  defp decode_binary(<<
         @push::size(8),
         join_ref_size::size(8),
         topic_size::size(8),
         event_size::size(8),
         join_ref::binary-size(join_ref_size),
         topic::binary-size(topic_size),
         event::binary-size(event_size),
         data::binary
       >>) do
    %{
      __struct__: Message,
      topic: topic,
      event: event,
      payload: {:binary, data},
      ref: nil,
      join_ref: join_ref
    }
  end

  defp decode_binary(<<
         @reply::size(8),
         join_ref_size::size(8),
         ref_size::size(8),
         topic_size::size(8),
         status_size::size(8),
         join_ref::binary-size(join_ref_size),
         ref::binary-size(ref_size),
         topic::binary-size(topic_size),
         status::binary-size(status_size),
         data::binary
       >>) do
    %{
      __struct__: Reply,
      topic: topic,
      ref: ref,
      join_ref: join_ref,
      status: String.to_existing_atom(status),
      payload: {:binary, data}
    }
  end

  defp decode_binary(<<
         @broadcast::size(8),
         topic_size::size(8),
         event_size::size(8),
         topic::binary-size(topic_size),
         event::binary-size(event_size),
         data::binary
       >>) do
    %{
      __struct__: Broadcast,
      topic: topic,
      event: event,
      payload: {:binary, data}
    }
  end

  defp decode_binary(bin) when is_binary(bin) do
    raise ArgumentError,
          "invalid binary frame: expected a Phoenix.Socket.Message, Reply or Broadcast frame, got #{byte_size(bin)} bytes"
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
