# ToonEx

[![Hex.pm](https://img.shields.io/hexpm/v/toon_ex.svg)](https://hex.pm/packages/toon_ex)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/toon_ex)
[![License: MIT](https://img.shields.io/badge/license-MIT-fef3c0?labelColor=1b1b1f)](./LICENSE)

High-performance TOON (Token-Oriented Object Notation) encoder/decoder for Elixir with Phoenix Channels support.

TOON is a compact, human-readable data format optimized for LLM token efficiency.

## Features

- 🎯 **Token Efficient**: 30-60% fewer tokens for LLMs than JSON
- 📖 **Human Readable**: Indentation-based structure like YAML
- ✅ **Spec Compliant**: Tested against official TOON v4.1.0 specification
- 🔌 **Phoenix Channels**: Built-in serializer with binary frame support
- 🛠️ **JSON Converter**: Bidirectional JSON ↔ TOON conversion
- 🔧 **Extensible**: Custom encoding via `ToonEx.Encoder` protocol
- ⚡ **High Performance**: Zero-copy iodata encoding, binary pattern-matching decoder

## Installation

Add `toon_ex` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:toon_ex, "~> 1.2"}
  ]
end
```

## Quick Start

### Encoding

```elixir
# Nested object
ToonEx.encode!(%{"user" => %{"name" => "Bob"}})
# => "user:\n  name: Bob"

# Arrays
ToonEx.encode!(["elixir", "toon"])
# => "[2]: elixir,toon"
```

### Decoding

```elixir
ToonEx.decode!("name: Alice\nage: 30")
# => %{"name" => "Alice", "age" => 30}

ToonEx.decode!("tags[2]: a,b")
# => %{"tags" => ["a", "b"]}
```

### Phoenix Channels

```elixir
# In your endpoint configuration
config :my_app, MyApp.Endpoint,
  websocket: [
    serializer: [{ToonEx.Phoenix.Serializer, "~> 2.0.0"}]
  ]
```

Or (if not using Phoenix for LiveView/Restful Apis)

```elixir
config :phoenix, :json_library, ToonEx
```

The serializer supports both text and binary frame encoding for Phoenix Channels.
Binary frames use a compact binary protocol for `Phoenix.Socket.Message`, `Phoenix.Socket.Broadcast`,
and `Phoenix.Socket.Reply` structs, reducing payload size for high-frequency channels.
Use `fastlane!/1` for binary-encoded broadcasts and `encode!/1` for binary-encoded replies.

See `ToonEx.Phoenix.Serializer` for details.

## API Reference

### Core Functions

- `ToonEx.encode/2` - Encode data to TOON string (returns `{:ok, string} | {:error, error}`)
- `ToonEx.encode!/2` - Encode data to TOON string (raises on error)
- `ToonEx.decode/2` - Decode TOON string to data (returns `{:ok, data} | {:error, error}`)
- `ToonEx.decode!/2` - Decode TOON string to data (raises on error)

## Modules

- **ToonEx** - Main API
- **ToonEx.Encode** - Encoder implementation
- **ToonEx.Decode** - Decoder implementation
- **ToonEx.JSON** - JSON ↔ TOON converter
- **ToonEx.Encoder** - Protocol for custom struct encoding
- **ToonEx.Phoenix.Serializer** - Phoenix Channels serializer

## Specification

This implementation follows [TOON Specification v4.1.0](https://github.com/toon-format/spec/blob/main/SPEC.md) and is tested against official fixtures.

## Testing

```bash
# Run all tests
mix test

# Run with coverage
mix coveralls

# Code quality checks
mix quality
```

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

MIT License - see [LICENSE](LICENSE).
