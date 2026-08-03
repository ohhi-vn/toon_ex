# BTOON — Binary TOON

> **Binary transport format for the TOON data model**
>
> Version: v1.0-draft (supersedes Plan & Requirements v0.3)
> Status: Draft
> Keywords: MUST / MUST NOT / SHOULD / SHOULD NOT / MAY in the RFC 2119 sense.

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Design Goals](#2-design-goals)
3. [Non-Goals](#3-non-goals)
4. [Terminology](#4-terminology)
5. [Data Model](#5-data-model)
6. [Byte Order and Conventions](#6-byte-order-and-conventions)
7. [Envelope](#7-envelope)
8. [Value Encoding](#8-value-encoding)
9. [Primitive Types](#9-primitive-types)
10. [Composite Types](#10-composite-types)
11. [String Dictionaries](#11-string-dictionaries)
12. [Element Types](#12-element-types)
13. [Typed Arrays](#13-typed-arrays)
14. [Object Tables (Column Mode)](#14-object-tables-column-mode)
15. [Schema Mode](#15-schema-mode)
16. [Alignment and Padding](#16-alignment-and-padding)
17. [Determinism](#17-determinism)
18. [Encoder Rules](#18-encoder-rules)
19. [Decoder Rules](#19-decoder-rules)
20. [Change Tracking](#20-change-tracking)
21. [Transport](#21-transport)
22. [Versioning and Compatibility](#22-versioning-and-compatibility)
23. [Extension Types](#23-extension-types)
24. [Security Considerations](#24-security-considerations)
25. [Conformance](#25-conformance)
26. [Test Vectors](#26-test-vectors)
27. [Reference API](#27-reference-api)
28. [Performance Targets](#28-performance-targets)
29. [Implementation Roadmap](#29-implementation-roadmap)
30. [Open Questions](#30-open-questions)

---

## 1. Introduction

BTOON is a compact, deterministic, high-performance binary encoding of the
TOON data model — the same relationship BSON has to JSON. It is designed for
machine-to-machine communication where CPU cost matters more than wire size.

BTOON is **not** intended to replace TOON. TOON remains the canonical logical
format that application code works with; BTOON is another encoding of the same
model:

```
TOON   → human readable, LLM friendly
BTOON  → machine readable, high-performance transport
```

It is used for WebSocket communication, Phoenix Channels, RPC, streaming, IoT,
telemetry, multiplayer games, and distributed systems.

The reference implementation is written in Elixir (`lib/btoon/` in this
repository) and follows this specification exactly. Where this document and the
implementation disagree, the implementation is authoritative until this document
is updated.

## 2. Design Goals

- **G1 — Lossless compatibility.** Anything representable in TOON/JSON MUST
  round-trip through BTOON unchanged.
- **G2 — Minimize CPU cost.** Branch count, allocation count, and copy count of
  encode/decode take priority over byte count whenever they conflict.
- **G3 — Zero-copy decode.** Decoders SHOULD expose binary and numeric payloads
  without copying whenever the host runtime supports shared immutable byte
  slices (BEAM sub-binaries, JS TypedArray views, Rust `&[u8]`, Go `[]byte`,
  C++ `std::span`).
- **G4 — Deterministic.** Every value has exactly one legal byte encoding.
- **G5 — Schema-preferred.** Schema mode is the recommended default for any
  channel expected to carry more than a handful of messages; the dynamic/tagged
  path remains available for ad-hoc or first-contact messages.
- **G6 — Extensible.** Applications MAY define custom types without breaking old
  decoders.
- **G7 — Streaming friendly.** Encoders SHOULD emit iodata / scatter-gather
  output; decoders SHOULD support incremental parsing.
- **G8 — Language independent.** The wire format makes no assumptions about a
  specific runtime. Runtime-specific optimizations belong in language
  implementation guides, not in this specification.

## 3. Non-Goals

BTOON is **NOT** intended to:

- Replace TOON, JSON, or be human editable.
- Serialize arbitrary language objects (no class metadata).
- Support XML, executable code, or object graphs with cycles.
- Be byte-optimal at the expense of CPU. Size is a tracked, secondary metric
  (see [§28](#28-performance-targets)) — never chosen over a CPU win.
- Be a replacement for Protobuf/FlatBuffers/Cap'n Proto in statically-typed,
  codegen-heavy systems.
- Be (initially) a storage/at-rest format — scope is transport only.

## 4. Terminology

- **Envelope** — the fixed header plus optional string table and schema that
  precede every message body.
- **Body** — the encoded value(s) that follow the envelope.
- **Tag** — a one-byte type selector that precedes a value.
- **SmallInt** — an inline integer encoded directly in the lead byte.
- **StringRef** — an integer reference into the combined string dictionary
  (session entries first, per-message entries second).
- **Element type** — a fixed-width numeric type used by TypedArray, ObjectTable
  columns, and Schema fields.
- **Hot path** — schema mode plus typed arrays/columns: fixed-width,
  branch-free, alignment-guaranteed decoding.
- **Cold path** — dynamic tagged encoding for ad-hoc or one-off messages.

## 5. Data Model

The data model mirrors TOON/JSON.

**Primitive types**

| Type    | Notes                                    |
| ------- | ---------------------------------------- |
| Null    | `nil`                                    |
| Boolean | `true` / `false`                         |
| Integer | arbitrary precision, encoded int32/int64 |
| Float   | IEEE-754, float32/float64                |
| String  | UTF-8                                    |
| Binary  | raw bytes (distinct from String)         |

**Composite types**

| Type   | Notes                          |
| ------ | ------------------------------ |
| Array  | heterogeneous list of values   |
| Object | unordered map of key→value     |
| TypedArray | homogeneous numeric buffer (tag `0x0C`) |
| ObjectTable | columnar table of numeric columns (tag `0x0D`) |

Binary, TypedArray, and ObjectTable are not representable in JSON/TOON without
annotations; in BTOON they are first-class values distinguished by explicit
tags.

## 6. Byte Order and Conventions

- **All multi-byte integers are little-endian, always.** No negotiation, no
  per-message flag. This removes a conditional byte-swap from every multi-byte
  read and matches virtually every real deployment target (x86/ARM, browsers).
- **All lengths and counts are fixed-width unsigned 32-bit little-endian
  integers.** Varints are forbidden. A varint makes every field's offset depend
  on parsing everything before it — the opposite of predictable, alignable
  access.
- **Signed integers** are two's-complement little-endian.
- **Floats** are IEEE-754 binary32/binary64 little-endian.
- Strings and binaries are not base64-encoded; raw bytes are transferred.

## 7. Envelope

Every BTOON message begins with a fixed 8-byte header followed by optional
sections and the body.

```
+----------------+------------------+
| Magic "BTON"   | 4 bytes          |
+----------------+------------------+
| Version        | 1 byte           |
+----------------+------------------+
| Flags          | 1 byte           |
+----------------+------------------+
| Reserved       | 2 bytes, zero    |
+----------------+------------------+
| String Table   | variable, zero-padded to a multiple of 8
+----------------+------------------+
| Schema         | variable, only when the schema flag is set
+----------------+------------------+
| Body           | variable, begins 8-byte aligned
+----------------+------------------+
```

### 7.1 Magic

The 4 bytes `42 54 4F 4E` (ASCII `"BTON"`).

Decoder MUST reject messages with unrecognized magic bytes.

### 7.2 Version

One byte. This document specifies version `01`.

### 7.3 Flags

One byte.

| Bit | Mask  | Meaning                                  |
| --- | ----- | ---------------------------------------- |
| 0   | `0x01` | reserved                                |
| 1   | `0x02` | schema included (embedded schema present)|
| 2   | `0x04` | string table present                    |
| 3   | `0x08` | session dictionary active               |
| 4   | `0x10` | no per-message string table (all strings via session dict or inline) |
| 5   | `0x20` | schema ID is UInt16 (2 bytes) instead of UInt32 |
| 6–7 | —     | reserved                                |

Decoder MUST ignore unrecognized/reserved flag bits.

### 7.4 Reserved

Two bytes, MUST be zero. Reserved for future expansion.

### 7.5 String Table

Present only when flag bit 2 (`0x04`) is set.

```
+------------------+
| Count            | UInt32
+------------------+
| Length[0]        | UInt32
| UTF-8 bytes[0]   |
+------------------+
| ...              |
+------------------+
```

The table is zero-padded at its end to a multiple of 8 bytes (see
[§16](#16-alignment-and-padding)).

Strings are added to the table in first-encounter order during encoding. Ref ids
for table entries are assigned after all session dictionary entries (see
[§11](#11-string-dictionaries)).

### 7.5.1 No Per-Message String Table (Flag 0x10)

When flag bit 4 (`0x10`) is set, the per-message string table is **absent**.
All strings MUST be encoded as either:
- StringRef referencing the session dictionary (flag 0x08 must also be set), or
- Inline String (tag 0x07) when not in the session dictionary.

This flag is intended for connections with a negotiated session dictionary where
the application knows all strings will be in the dictionary or are one-off.
It eliminates the string table build, alignment padding, and flag byte overhead.

The no-string-table flag (0x10) and string table flag (0x04) are mutually
exclusive. Encoder MUST NOT set both.

### 7.6 Embedded Schema

Present only when flag bit 1 (`0x02`) is set. Layout:

```
+------------------+
| Schema ID        | UInt32
+------------------+
| Name Length      | UInt32
| Name (UTF-8)     |
+------------------+
| Field Count      | UInt32
+------------------+
| Field 0: Name Len| UInt32
|          Name    |
|          ElemTyp | 1 byte
+------------------+
| ...              |
+------------------+
```

See [§15](#15-schema-mode) for the body layout that follows.

### 7.6.1 Schema ID Size (Flag 0x20)

When flag bit 5 (`0x20`) is set, the embedded schema's `SchemaID` field is encoded as **UInt16** (2 bytes) instead of UInt32 (4 bytes). This saves 2 bytes per message for deployments with fewer than 65,536 schemas.

The schema ID size flag (0x20) only affects the embedded schema block in the envelope; the schema-mode body (which begins with `SchemaID`) always uses the size matching this flag.

### 7.7 Body

The body begins 8-byte aligned. It is either a single tagged value (dynamic
mode) or a schema body ([§15](#15-schema-mode)).

## 8. Value Encoding

Every value begins with a one-byte tag, except SmallInt which encodes the value
entirely within the lead byte.

### 8.1 Type Tags

| Tag      | Type          | Notes                       |
| -------- | ------------- | --------------------------- |
| `0x00`   | Null          |                             |
| `0x01`   | False         |                             |
| `0x02`   | True          |                             |
| `0x03`   | Int32         | 4-byte signed               |
| `0x04`   | Int64         | 8-byte signed               |
| `0x05`   | Float32       | IEEE-754 binary32           |
| `0x06`   | Float64       | IEEE-754 binary64           |
| `0x07`   | String        | length-prefixed UTF-8       |
| `0x08`   | Binary        | length-prefixed raw bytes   |
| `0x09`   | Array         | count + items               |
| `0x0A`   | Object        | count + key/value pairs     |
| `0x0B`   | StringRef     | integer id into the dictionary |
| `0x0C`   | TypedArray    | element type + count + buffer |
| `0x0D`   | ObjectTable   | row count + columns         |
| `0x0E–0x1F` | reserved   | for future explicit tags    |

There are no explicit Int8/Int16 tags. Small values use SmallInt
([§8.2](#82-smallint)); larger integers use Int32/Int64. This shrinks the
dispatch table and removes the encoder's "smallest fit" search at a byte cost
that is acceptable under G2.

### 8.2 SmallInt

An inline integer in the range **−32..95** is encoded as a single bare byte in
`0x20..0x9F`:

```
value = byte − 64
```

| Value | Byte     |
| ----- | -------- |
| −32   | `0x20`   |
| 0     | `0x40`   |
| 42    | `0x6A`   |
| 95    | `0x9F`   |

No tag or payload follows. This is the cheapest possible encoding: one read,
one branch, no second byte to fetch.

Encoder MUST use SmallInt for any integer in −32..95 and MUST NOT use Int32 or
Int64 for values in that range (see [§17](#17-determinism)).

### 8.3 Dispatch

Dispatch is one range check on the lead byte:

```
0x00–0x1F  → explicit tag (§8.1)
0x20–0x9F  → SmallInt, value = byte − 64
0xA0–0xFF  → reserved
```

## 9. Primitive Types

### 9.1 Null

```
0x00
```

### 9.2 Booleans

```
0x01          # false
0x02          # true
```

### 9.3 Integers

Integers outside the SmallInt range are tag + fixed-width two's-complement
little-endian:

```
0x03  value::32-little-signed      # Int32, range −2^31..2^31−1
0x04  value::64-little-signed      # Int64
```

The encoder chooses the narrowest of SmallInt / Int32 / Int64 that holds the
value. Values beyond Int64 range MUST NOT be encoded as numbers.

### 9.4 Floats

```
0x05  value::32-little-float       # Float32
0x06  value::64-little-float       # Float64
```

Encoder MUST use Float32 only when the double survives the binary32 round-trip
exactly (lossless); otherwise Float64. This keeps encoding deterministic
([§17](#17-determinism)).

### 9.5 String

```
0x07  Length::UInt32  UTF-8 bytes
```

Strings remain UTF-8. Length is in bytes, not code points. Decoders SHOULD defer
UTF-8 decode until the value is actually accessed.

### 9.6 StringRef

```
0x0B  id                    # id is SmallInt/Int32/Int64
```

Refers to an entry in the combined dictionary (session entries first, then
per-message table entries, [§11](#11-string-dictionaries)). A reference outside
the combined dictionary is a decode error.

### 9.7 Binary

```
0x08  Length::UInt32  Raw bytes
```

Raw bytes are transferred directly, never base64. Distinct from String so opaque
blobs are not required to be valid UTF-8.

## 10. Composite Types

### 10.1 Arrays

```
0x09  Count::UInt32  Item  Item  ...
```

Items are encoded values ([§8](#8-value-encoding)), each tagged. Sequential
layout, no padding between items. Note: a homogeneous numeric array MAY be
encoded as a TypedArray instead ([§13](#13-typed-arrays)).

### 10.2 Objects

```
0x0A  Count::UInt32  (Key, Value)  (Key, Value)  ...
```

Keys MUST be a String ([§9.5](#95-string)) or StringRef ([§9.6](#96-stringref));
bare SmallInt keys are not permitted. Encoder MUST emit keys in sorted order
(determinism, [§17](#17-determinism)). Decoders SHOULD keep keys as refs
internally and only stringify them when accessed.

## 11. String Dictionaries

String repetition is the largest source of wasted bytes in real payloads
(field names repeated on every message). BTOON has two layers of string
deduplication, combined into a single ref id space.

### 11.1 Session Dictionary

A session dictionary is negotiated once per connection (see
[§21](#21-transport)). Once established, its entries are never transmitted
again; messages reference them by integer id via StringRef, avoiding repeat
UTF-8 transmission and decode.

The encoder flags the envelope with bit 3 (`0x08`) when a non-empty session
dictionary is in use, so the decoder knows the id space is offset.

### 11.2 Per-Message String Table

The per-message string table ([§7.5](#75-string-table)) is the fallback
mechanism, used before a session dictionary exists (first message) or for
genuinely one-off messages. Strings are added in first-encounter order and
referenced via StringRef.

### 11.3 Ref ID Space

One combined id space:

```
ids 0..n−1        → session dictionary entries (in dictionary order)
ids n..n+m−1      → per-message string table entries (in table order)
```

where `n` is the size of the session dictionary. The encoder MUST assign table
entry ids starting at `n`; the decoder MUST resolve ids against session entries
first, then table entries. A per-message table is never a rebuild of the session
dictionary — it layers on top.

## 12. Element Types

Element type selectors are shared by TypedArray buffers, ObjectTable columns,
and Schema fields.

| Selector | Type    | Size | Notes                     |
| -------- | ------- | ---- | ------------------------- |
| `0x00`   | int8    | 1    |                           |
| `0x01`   | uint8   | 1    |                           |
| `0x02`   | int16   | 2    |                           |
| `0x03`   | uint16  | 2    |                           |
| `0x04`   | int32   | 4    |                           |
| `0x05`   | uint32  | 4    |                           |
| `0x06`   | int64   | 8    |                           |
| `0x07`   | float32 | 4    | IEEE-754 binary32         |
| `0x08`   | float64 | 8    | IEEE-754 binary64         |
| `0x09`   | null    | 0    | schema fields only        |
| `0x0A`   | bool    | 1    | schema fields only        |
| `0x0B`   | string  | var  | schema fields only        |
| `0x0C`   | binary  | var  | schema fields only        |
| `0x0D`   | array   | var  | schema fields only        |
| `0x0E`   | object  | var  | schema fields only        |
| `0x0F`   | uint64  | 8    |                           |

TypedArray buffers allow only the numeric types (`0x00–0x08`). ObjectTable
columns allow only the numeric types (`0x00–0x08`, including `0x0F` uint64).
Schema fields may use any selector.

## 13. Typed Arrays

A TypedArray is a contiguous, homogeneous numeric buffer — the binary form of a
`Float32Array` / `Int32Array` etc.

```
0x0C  ElementType::1  Count::UInt32  PadLen::1  Padding  RawBuffer
```

- `Count` is the number of elements. The raw buffer length MUST equal
  `Count × element_size(ElementType)`.
- `Padding` is `PadLen` zero bytes (0–7) that align `RawBuffer` to the element
  size ([§16](#16-alignment-and-padding)).
- `RawBuffer` is the raw little-endian buffer, decoded in bulk — no per-element
  loop, no per-element tags.

Encoder MUST use a TypedArray for any homogeneous numeric array (all integers or
all floats), picking the narrowest lossless element type ([§17](#17-determinism)).
Decoders SHOULD expose the raw buffer as a zero-copy view whenever the host
language supports it (JS TypedArray, Rust `&[u8]` + cast, Go `[]byte`).
Otherwise they MAY materialize a list of numbers.

## 14. Object Tables (Column Mode)

An ObjectTable is the columnar form of an array of objects with identical,
homogeneous numeric fields. This is the highest-leverage mechanism for
"100 players" style workloads: decoding is N column reads, not N×M per-value
parses.

```
0x0D  RowCount::UInt32  ColumnCount::UInt32  Column  Column  ...
```

Each column:

```
Name (String|StringRef)  ElementType::1  PadLen::1  Padding  RawBuffer
```

- `Name` is the field name as a String or StringRef.
- **When the session dictionary flag (0x08) is set, column names MUST be encoded as StringRef.** This avoids repeating column names that are already in the session dictionary.
- `RawBuffer` holds exactly `RowCount` elements of the column's element type,
  little-endian, aligned per [§16](#16-alignment-and-padding).
- Column data is decoded in bulk; rows are reconstructed by striding across
  columns.

Encoder MUST emit a column for every field; all columns share the same row
count. Decoders MUST reject tables with non-numeric column element types.

## 15. Schema Mode

When peers share a schema — a named record with typed, ordered fields — the
encoder omits keys and type tags entirely, emitting only ordered fixed-width
values. This is the fastest possible decode: no tag, no branch, effectively a
struct-cast over the wire bytes.

### 15.1 Schema definition

A schema has an id, a name, and an ordered list of fields, each with a name and
an element type ([§12](#12-element-types)). The element types allowed in schema
fields are the numeric types plus the composite selectors `null`, `bool`,
`string`, `binary`, `array`, and `object`.

The schema is either embedded in the envelope ([§7.6](#76-embedded-schema),
schema flag set) or negotiated out of band and supplied by the application. When
the schema flag is set, the embedded schema is authoritative.

### 15.2 Body layout

```
SchemaID::UInt32|UInt16  FieldValue  FieldValue  ...
```

The `SchemaID` size is determined by the envelope flag 0x20 (see [§7.6.1](#761-schema-id-size-flag-0x20)): UInt16 when the flag is set, otherwise UInt32.

Field values are encoded strictly per the schema, in field order, with no tags
and no keys:

| Field type         | Encoding                                    |
| ------------------ | ------------------------------------------- |
| int8…uint64        | fixed-width little-endian (size per §12)    |
| float32 / float64  | fixed-width IEEE-754 little-endian          |
| null               | zero bytes; value is `nil`                  |
| bool               | 1 byte: `0` false, `1` true                 |
| string             | String or StringRef                         |
| binary             | Binary ([§9.7](#97-binary))                 |
| array / object     | full tagged value ([§8](#8-value-encoding)) |

Schema mode is the recommended default for any hot path (GPS, telemetry, game
state, high-frequency channel traffic). It composes with [§16](#16-alignment-and-padding)
so uniform schema payloads are also viewable as contiguous buffers.

The decoder reads values strictly according to the schema. A missing or
wrong-typed value, or an integer outside a field's declared width, is an error.

## 16. Alignment and Padding

Contiguous numeric payloads MUST begin at an address aligned to their element
size. Alignment is what makes true zero-copy decode possible at all: many
runtimes require views over native buffers to be element-aligned (for example,
JS `new Float64Array(buffer, byteOffset, length)` throws unless `byteOffset` is
a multiple of the element size; several hardware platforms prefer aligned
loads).

The rules:

- The header is exactly 8 bytes, so anything padded to a multiple of 8 after it
  stays 8-byte aligned.
- The String Table MUST be zero-padded at its end to a multiple of 8 bytes.
- Every TypedArray raw buffer MUST be preceded by `PadLen` (0–7) zero bytes so
  it begins aligned to its element size.
- Every ObjectTable column raw buffer MUST be preceded by 0–7 zero bytes (via
  its `PadLen` byte) so it begins aligned to its element size.
- The Body MUST begin 8-byte aligned.

Padding bytes are zero. Implementations MUST emit the padding even if their
runtime does not require it — it is part of the wire format and at most 7 bytes
per typed section.

## 17. Determinism

Every input maps to exactly one byte sequence. The following rules are MUST:

- Integers in −32..95 use SmallInt; outside that range the narrowest of
  Int32/Int64 is used. No other choice is legal.
- Floats use Float32 only when lossless, else Float64.
- Object keys are emitted in sorted order.
- Per-message string table entries are added in first-encounter order.
- Homogeneous numeric arrays use the narrowest lossless element type.
- Homogeneous object arrays use a columnar ObjectTable with columns in sorted
  key order (when object tables are enabled).
- Little-endian byte order throughout.

Two encoders MUST produce identical bytes for the same input; one encoder MUST
produce identical bytes across runs.

## 18. Encoder Rules

- Encoder MUST reject values not representable in the data model
  ([§5](#5-data-model)), including integers outside Int64 range.
- Encoder MUST use SmallInt for −32..95 and MUST NOT use Int32/Int64 there.
- Encoder MUST use Float32 only when lossless.
- Encoder MUST use StringRef for strings present in the session dictionary and
  for strings already added to the per-message table.
- Encoder MUST use a TypedArray for homogeneous numeric arrays and an
  ObjectTable for homogeneous object arrays (both MAY be disabled by
  application option, in which case the general Array encoding is used).
- **Encoder MUST encode ObjectTable column names as StringRef when the session
  dictionary flag (0x08) is set.** This avoids repeating column names already
  present in the session dictionary.
- Encoder MUST set the envelope flags to match what it actually emitted
  (string table, schema, session dictionary, no per-message table, schema ID size).
- **When the session dictionary flag (0x08) is set and the encoder will not emit
  any per-message string table entries, the encoder SHOULD set the no per-message
  table flag (0x10) to eliminate the table overhead.**
- Encoder MUST emit alignment padding per [§16](#16-alignment-and-padding).
- Encoder SHOULD write iodata / scatter-gather output rather than
  concatenating into a single buffer, to avoid copies.
- Encoder MUST emit the reserved header bytes as zero.

## 19. Decoder Rules

- Decoder MUST reject messages with unrecognized magic bytes.
- Decoder MUST reject unsupported versions.
- Decoder MUST ignore unrecognized/reserved flag bits.
- Decoder MUST reject truncated data, unknown tags, invalid element type
  selectors, StringRefs out of range, non-numeric ObjectTable columns, and
  schema values that violate the schema.
- Decoder MUST impose configurable limits: maximum nesting depth, maximum
  string/binary size, and maximum container counts (see
  [§24](#24-security-considerations)).
- Decoder MUST NOT convert binary payloads to lists as an intermediate step.
- Decoder SHOULD build maps directly from decoded sub-binaries.
- Decoder SHOULD defer string decode and object-key stringification until
  accessed.
- Decoder SHOULD expose contiguous numeric buffers as zero-copy views where the
  host language supports it.

## 20. Change Tracking

Two mechanisms reduce transmission for repeated state updates. Both are
optional; neither is required for core conformance.

### 20.1 Entity-level change-sets (recommended default)

The encoder decides per entity "changed since last frame or not" (often already
tracked by the application as a dirty flag) and either includes the entity's
full record this frame or omits it. The decoder overwrites its last-known-record
cache for included entities. This stays branch-free and allocation-free on
decode, and included entities can still use the bulk decode path
([§13](#13-typed-arrays), [§14](#14-object-tables-column-mode)).

### 20.2 Field-level delta (opt-in)

The encoder diffs old vs. new state and the decoder maintains per-entity state
and applies partial patches. This is inherently branchy, stateful, and
incompatible with bulk decode, so it is opt-in and off by default. Kept for
genuinely bandwidth-constrained links.

## 21. Transport

BTOON is transport-independent. Messages MAY be carried over TCP, UDP, QUIC,
WebSocket, files, shared memory, or named pipes. The same encoding is used
everywhere; only framing (message boundaries) differs.

For stream-oriented transports (TCP, WebSocket) the message boundary is either
the BTOON frame itself (WebSocket binary frames) or an application-level length
prefix supplied by the transport. BTOON does not define a length prefix of its
own.

### 21.1 Session Dictionary Negotiation

For connections that persist (WebSocket, TCP), peers SHOULD negotiate a session
dictionary once at handshake. A dictionary may be:

- a fixed dictionary referenced by hash, known to both sides; or
- a dictionary transmitted once and then referenced by id.

After the handshake, no field names are transmitted; the encoder sets flag bit 3
(`0x08`) on every message using the dictionary. See [§11](#11-string-dictionaries).

### 21.2 Schema Negotiation

Schemas may be embedded per message ([§7.6](#76-embedded-schema)), transmitted
once and reused by id, or compiled into both endpoints. The reference
implementation always embeds the schema on schema-mode messages and also accepts
an out-of-band schema through decode options.

## 22. Versioning and Compatibility

- The version byte identifies the wire format generation. Decoders MUST reject
  versions they do not support.
- Reserved tag ranges (`0x0E–0x1F`, `0xA0–0xFF`) MAY be assigned by future
  versions; decoders MUST treat unknown tags as errors, not as skippable data,
  because skipping requires knowing each value's length.
- Reserved flag bits MUST be ignored.
- Extension types ([§23](#23-extension-types)) are the forward-compatible
  escape hatch: unknown extension tags are registered, so a decoder that does
  not know a specific extension can be told its length and skip it.
- Future versions remain backward compatible at the decoder level: an older
  decoder MUST reject (never misparse) a newer version.

## 23. Extension Types

Applications MAY register custom types without breaking old decoders. The
extension registry reserves the tag range `0xF0–0xFF`:

| Range        | Purpose                                     |
| ------------ | ------------------------------------------- |
| `0xF0–0xF7`  | Experimental / vendor-specific              |
| `0xF8–0xFB`  | Official (registered with the maintainers)  |
| `0xFC–0xFF`  | Private / application-local                 |

A registered extension defines its own payload layout and length encoding so
decoders can skip it. Suggested candidate extensions: UUID, timestamp, decimal
(Decimal128), GeoPoint, IPv6, and user-defined types. No extension tags are
defined by this document.

## 24. Security Considerations

Decoders MUST validate untrusted input defensively:

- **Maximum packet size** — decoders SHOULD enforce a configurable limit.
- **Maximum nesting depth** — decoders SHOULD enforce a configurable recursion
  limit (the reference decoder defaults to 100).
- **Maximum string/binary size** — a length field can claim gigabytes; decoders
  MUST NOT allocate based on an untrusted length without a limit check.
- **Maximum container counts** — array/object counts can claim enormous sizes;
  decoders MUST validate counts against available input.
- **Integer overflow** — all length/offset arithmetic MUST be overflow-safe.
- **Invalid alignment** — padding counts MUST be validated (0–7); decoders MUST
  NOT read past the end of the buffer.
- **Malicious dictionaries** — session dictionaries and string tables can
  contain huge entries; the same size limits apply.
- **Ref exhaustion** — StringRef ids MUST be bounds-checked against the
  combined dictionary.

## 25. Conformance

### 25.1 Compliance levels

- **Level 0 — Core decoder**: primitives, SmallInt, strings, binaries, arrays,
  objects, string table. Rejects malformed input per [§19](#19-decoder-rules).
- **Level 1 — Encoder**: produces deterministic bytes per
  [§17](#17-determinism) and [§18](#18-encoder-rules).
- **Level 2 — Streaming**: iodata output and incremental parsing.
- **Level 3 — Schema**: schema mode ([§15](#15-schema-mode)).
- **Level 4 — Realtime**: TypedArray, ObjectTable, alignment, change-sets.

An implementation claiming conformance at level N MUST satisfy all lower
levels. Embedded devices MAY implement only Level 0.

### 25.2 Conformance suite

Every official release MUST pass the shared test vectors
([§26](#26-test-vectors)) and cross-language interop tests: payloads encoded by
one implementation MUST decode identically in every other implementation.

## 26. Test Vectors

All examples are little-endian, shown as hex bytes. Envelope = `42 54 4F 4E` +
version + flags + reserved.

### 26.1 Primitives

| Value                    | Bytes                                             |
| ------------------------ | ------------------------------------------------- |
| `null`                   | `42 54 4F 4E 01 00 00 00 00`                     |
| `false`                  | `42 54 4F 4E 01 00 00 00 01`                     |
| `true`                   | `42 54 4F 4E 01 00 00 00 02`                     |
| `-32` (SmallInt)         | `42 54 4F 4E 01 00 00 00 20`                     |
| `0` (SmallInt)           | `42 54 4F 4E 01 00 00 00 40`                     |
| `42` (SmallInt)          | `42 54 4F 4E 01 00 00 00 6A`                     |
| `95` (SmallInt)          | `42 54 4F 4E 01 00 00 00 9F`                     |
| `96` (Int32)             | `42 54 4F 4E 01 00 00 00 03 60 00 00 00`         |
| `-33` (Int32)            | `42 54 4F 4E 01 00 00 00 03 DF FF FF FF`         |
| `2_147_483_648` (Int64)  | `42 54 4F 4E 01 00 00 00 04 00 00 00 80 00 00 00 00` |
| `1.5` (Float32)          | `42 54 4F 4E 01 00 00 00 05 00 00 C0 3F`         |
| `1.1` (Float64)          | `42 54 4F 4E 01 00 00 00 06 9A 99 99 99 99 99 F1 3F` |
| `Binary(1,2,3)`          | `42 54 4F 4E 01 00 00 00 08 03 00 00 00 01 02 03` |

### 26.2 SmallInt boundaries

The values −32, −1, 0, 95 use SmallInt; 96 and −33 MUST NOT. `96` encodes as
`03 60 00 00 00` (Int32); `-33` as `03 DF FF FF FF` (Int32).

### 26.3 Strings

`"hello"` with the default per-message string table: table flag `0x04`, one
entry, padded to 8, then a StringRef `0`.

```
42 54 4F 4E 01 04 00 00
01 00 00 00                       count = 1
05 00 00 00 68 65 6C 6C 6F        "hello" (5 bytes)
00 00 00                          pad to 8 (21 → 24)
0B 40                             StringRef 0
```

`"hello"` with the string table disabled:

```
42 54 4F 4E 01 00 00 00
07 05 00 00 00 68 65 6C 6C 6F     String, length 5, bytes
```

### 26.4 TypedArray

`[1, 2, 3]` as int8 TypedArray:

```
42 54 4F 4E 01 00 00 00
0C 00 03 00 00 00 00 01 02 03
```

| Offset | Bytes              | Meaning                       |
| ------ | ------------------ | ----------------------------- |
| 8      | `0C`               | TypedArray tag `0x0C`         |
| 9      | `00`               | element type int8 (`0x00`)    |
| 10–13  | `03 00 00 00`      | count = 3                     |
| 14     | `00`               | pad length = 0                |
| 15–17  | `01 02 03`         | buffer (3 × int8)             |

### 26.5 Object

`{"age": 30, "name": "Alice"}` — table flag, three table entries, then object
with StringRef keys and values:

```
42 54 4F 4E 01 04 00 00            header
03 00 00 00                        count = 3
03 00 00 00 61 67 65               "age"
04 00 00 00 6E 61 6D 65            "name"
05 00 00 00 41 6C 69 63 65         "Alice"
00 00 00 00                        pad to 8 (36 → 40)
0A 02 00 00 00                     Object, 2 fields
0B 40 5E                           key "age" (ref 0), value 30 (SmallInt)
0B 41 0B 42                        key "name" (ref 1), value "Alice" (ref 2)
```

## 27. Reference API

The reference implementation (`BTOON` in this repository) exposes:

```elixir
BTOON.encode!(data, opts)     # -> binary
BTOON.encode(data, opts)      # -> {:ok, binary} | {:error, EncodeError}
BTOON.decode!(binary, opts)   # -> value
BTOON.decode(binary, opts)    # -> {:ok, value} | {:error, DecodeError}
```

Wrapper types:

- `BTOON.Binary` — raw binary value (tag `0x08`), to disambiguate from String.
- `BTOON.TypedArray` — typed numeric buffer (tag `0x0C`).
- `BTOON.ObjectTable` — columnar numeric table (tag `0x0D`).
- `BTOON.Dictionary` — session string dictionary.
- `BTOON.Schema` — named, typed record schema.

Encoding options: `:dictionary`, `:string_table` (`:auto` | `:off`),
`:no_string_table` (boolean), `:schema`, `:schema_id_uint16` (boolean),
`:typed_arrays` (boolean), `:object_tables` (boolean).

Decoding options: `:dictionary`, `:schema`, `:keys` (`:strings` | `:atoms` |
`:atoms!`), `:typed_arrays` (`:lists` | `:views`), `:max_depth`,
`:max_string_size`, `:max_binary_size`, `:max_container_count`.

## 28. Performance Targets

These are design targets, not measured results (see
[§29](#29-implementation-roadmap) Phase 6).

**Encoding**

- Faster than JSON encoding; comparable to MessagePack.
- Zero-allocation hot path via iodata / scatter-gather writes.

**Decoding**

- Faster than JSON decoding.
- Zero-copy strings, binaries, and numeric buffers.
- Hot path (schema + typed arrays/columns): zero heap allocation beyond the
  returned view/struct, zero per-element branching for homogeneous payloads.
- Cold path (dynamic/tagged): at most one branch per value for dispatch, with
  allocation only for strings/keys actually accessed.

**Memory**

- Encoder: streaming, iodata, scatter/gather writes.
- Decoder: no temporary buffers, shared binary references, incremental parsing.

**Wire size** (secondary, informational)

- Typical structured message: 30–50% smaller than TOON.
- Numeric-heavy (GPS, telemetry): 50–70% smaller.
- Incremental updates (dictionary + change-sets): 80–95% smaller.

## 29. Implementation Roadmap

| Phase | Focus                                     | Exit criteria                                        |
| ----- | ----------------------------------------- | ---------------------------------------------------- |
| 0     | Spec freeze                               | Tag table, alignment, fixed little-endian; test vectors incl. SmallInt and alignment |
| 1     | Core codec (cold path)                    | Primitives, per-message string table, objects, arrays; Elixir + JS round-trip |
| 2     | Schema + typed arrays + columns (hot path)| Benchmarked for CPU (ops/sec, allocations), not just size |
| 3     | Session dictionary                        | Handshake negotiation, versioning, desync handling   |
| 4     | Entity-level change-sets                  | Last-full-record cache, resync strategy              |
| 5     | Field-level delta (opt-in)                | Only if Phase 4 profiling shows it is insufficient   |
| 6     | Hardening                                 | Fuzzed decoder, cross-platform conformance, real CPU benchmarks |
| 7     | Rollout                                   | Feature-flagged, gradual cutover, production monitoring |

Testing & validation: per-type encode/decode unit tests including SmallInt
boundaries (−32, −1, 0, 95, 96, −33); alignment regression tests constructing
views over real encoded payloads across varied preceding content; CPU
benchmarks (ops/sec, allocations per decode, hot vs. cold vs. TOON/JSON
baseline); fuzz testing against malformed/truncated input; cross-language
interop.

## 30. Open Questions

- **Object field-order preservation.** Objects are unordered by design; whether
  to add an ordered-object variant remains open.
- **Change-set / delta-frame addressing.** Entity IDs, sequence numbers, and
  resync strategy are not yet specified for [§20](#20-change-tracking).
- **Session dictionary versioning.** Reconnect, versioning, and desync recovery
  are not yet specified.
- **Extension registry mechanics.** The tag ranges are reserved
  ([§23](#23-extension-types)) but no registration process is defined.

Resolved in v0.3 / this revision: SmallInt (was ambiguous), endianness (fixed
little-endian), compression (removed from scope, defer to transport-level
permessage-deflate), TypedArray/ObjectTable dispatch (explicit tags), element
type enum, and the exact padding mechanism.

---

## Appendix A: Design Rationale

The following table records the reasoning for each v0.2 → v0.3 decision.

| Mechanism                              | CPU cost driver                                             | Verdict                                                        | Rationale |
| -------------------------------------- | ----------------------------------------------------------- | -------------------------------------------------------------- | --------- |
| SmallInt inline (§8.2)                 | 1 branch per scalar                                         | Keep                                                           | 1 byte / 1 read / 1 branch vs. tag-byte + payload-byte (2 reads) |
| Int8/Int16 explicit tags               | Extra dispatch cases; encoder "smallest fit" search         | Remove, fold into Int32                                       | Fewer tags = smaller dispatch; removes a CPU-only search for a byte-only benefit |
| TypedArray/ObjectTable dispatch        | No tag existed; decoder could not detect the fast path      | Add explicit tags `0x0C`/`0x0D`                               | They were described as distinct structures but never wired into dispatch |
| Per-message string table               | Hash-based dedup pass every message                         | Demote to fallback                                            | Building a table for a 4-field GPS message can cost more than it saves |
| Session dictionary                     | One-time negotiation, amortized                             | Elevate to default                                            | String refs become integer lookups; avoids repeat UTF-8 decode |
| Typed arrays                           | Removes per-element tag branch entirely                     | MUST, not SHOULD                                              | Enables a true bulk/loop-free read                           |
| Column mode (ObjectTable)              | Same, per field                                             | MUST fixed-width                                              | Batch-decode a whole column instead of N×M per-row parses   |
| Field-level delta                      | Encoder diffs, decoder patches state                        | Demote: opt-in, off by default                                | Branchy, stateful, defeats zero-copy                          |
| Schema mode                            | Removes all per-value tags/branches                         | Recommended default for hot paths                             | Fastest possible decode — sequential fixed-offset reads       |
| Compression                            | Decompression cost every message                            | Remove from scope                                             | App-level compression trades CPU for bytes; defer to transport |
| Endianness                             | Conditional byte-swap per multi-byte read if negotiable     | Fixed little-endian, no negotiation                           | Removes a branch from every numeric read                       |
| Length prefixes                        | (implicit)                                                  | Fixed-width only, never varint                                | Varints make every offset depend on prior parsing             |
| Alignment                              | Determines whether zero-copy views are possible at all      | Padding scheme (§16)                                          | Without it, zero-copy was never achievable                    |
| Object key resolution                  | Eager StringRef→string costs a lookup even if never read    | Decoders SHOULD keep keys lazy                               | Same lazy principle as string values                          |

### A.1 Why CPU first, bytes second

Byte count is a good proxy for bandwidth but a poor proxy for CPU. On the hot
path, branches and allocations dominate; a format that shaves 20% of bytes at
the cost of 2× the decode work is a net loss. BTOON therefore optimizes for the
fewest branches, allocations, and copies per value, and accepts slightly larger
payloads where that is the price of the win.

### A.2 Why fixed-width lengths

A fixed 4-byte length makes every value's offset computable from a constant,
which is what makes alignment guarantees and typed-array views possible at all.
Varints minimize bytes but make offsets data-dependent.

### A.3 Why no Int8/Int16 tags

SmallInt already covers −32..95 in a single byte with a single read, which is
cheaper than a tagged Int8 (two reads). An Int8/Int16 tag only helps values
outside the SmallInt range, where the byte savings are too small to justify the
extra dispatch cases and the encoder's "smallest fit" search.

### A.4 Why alignment is a MUST

Several runtimes require contiguous views over native buffers to be
element-aligned (JS TypedArray constructors throw otherwise; many CPUs prefer
aligned loads). Padding is at most 7 bytes per typed section — a small,
explicit trade for guaranteed zero-copy decode across every implementation.

### A.5 Why fixed little-endian

Little-endian matches virtually every real deployment target (x86/ARM,
browsers). Negotiation would add a branch to every multi-byte read for no
practical benefit.

## Appendix B: Working Examples

### B.1 Session dictionary

With a session dictionary `["player", "position", "velocity"]`, the message
`{"player": 1, "position": [1.0, 2.0]}`:

- Header flags: `0x08` (session dictionary active).
- `player` → StringRef `0`.
- `position` → StringRef `1`.
- `[1.0, 2.0]` → TypedArray, float32 element type, buffer
  `00 00 80 3F 00 00 00 40`.

### B.2 Schema mode

Schema `100 "Player"` with fields `id int32`, `x float32`, `y float32`,
`hp uint16`:

- Envelope flags: `0x02` (schema) | `0x04` (string table, when names/tables are
  present).
- Embedded schema block: id `100`, name `"Player"`, 4 fields.
- Body: `SchemaID::UInt32` = `100`, then `id::int32`, `x::float32`,
  `y::float32`, `hp::uint16` — no tags, no keys.

### B.3 ObjectTable

Rows `[{"x": 1, "y": 2.5}, {"x": 3, "y": 4.5}]`:

- Tag `0x0D`, row count `2`, column count `2`.
- Column `x`: name ref, element type `0x00` (int8), buffer `01 03`.
- Column `y`: name ref, element type `0x07` (float32), buffer
  `00 00 20 40 00 00 90 40`.

---

*BTOON — Binary TOON. Version 1.0-draft. See also the reference implementation
in `lib/btoon/` and the existing TOON text codec in `lib/toon_ex/`.*
