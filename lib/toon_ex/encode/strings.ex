defmodule ToonEx.Encode.Strings do
  @moduledoc """
  String encoding utilities for TOON format.

  Handles quote detection, escaping, and key validation.

  ## Performance

  Uses Jason-style chunk-based escaping with `binary_part/3`. Instead of
  copying every byte into a new binary, this approach:

  1. Scans the input for bytes that need escaping
  2. Uses `binary_part/3` to reference safe chunks without copying
  3. Builds an iodata list with chunk references and escape sequences

  This significantly reduces allocations for strings with few escape characters.
  The `binary_part/3` call is O(1) — it creates a sub-binary reference rather
  than copying the underlying data. Only when `IO.iodata_to_binary/1` is called
  at the top level does the final contiguous binary get allocated.
  """

  # Performance: Inline hot functions to reduce function call overhead
  @compile {:inline,
            safe_unquoted?: 2,
            safe_key?: 1,
            do_safe_key_first?: 1,
            do_safe_key_rest?: 1,
            needs_quoting_basic?: 1,
            has_leading_or_trailing_space?: 1,
            starts_with_hyphen?: 1,
            literal?: 1,
            contains_delimiter?: 2}

  @doc """
  Encodes a string value, adding quotes if necessary.

  Returns iodata that can be converted to a string with `IO.iodata_to_binary/1`.

  ## Examples

      iex> ToonEx.Encode.Strings.encode_string("hello") |> IO.iodata_to_binary()
      "hello"

      iex> ToonEx.Encode.Strings.encode_string("") |> IO.iodata_to_binary()
      ~s("")

      iex> ToonEx.Encode.Strings.encode_string("hello world") |> IO.iodata_to_binary()
      "hello world"

      iex> ToonEx.Encode.Strings.encode_string("line1\\nline2") |> IO.iodata_to_binary()
      ~s("line1\\\\nline2")
  """
  @spec encode_string(String.t(), String.t()) :: iodata()
  def encode_string(string, delimiter \\ ",") when is_binary(string) do
    if safe_unquoted?(string, delimiter) do
      string
    else
      [?", escape_string(string), ?"]
    end
  end

  @doc """
  Encodes a key, adding quotes if necessary.

  Keys have stricter requirements than values:
  - Must match /^[A-Z_][\\w.]*$/i (alphanumeric, underscore, dot)
  - Numbers-only keys must be quoted
  - Keys with special characters must be quoted

  Returns iodata that can be converted to a string with `IO.iodata_to_binary/1`.

  ## Examples

      iex> ToonEx.Encode.Strings.encode_key("name") |> IO.iodata_to_binary()
      "name"

      iex> ToonEx.Encode.Strings.encode_key("user_name") |> IO.iodata_to_binary()
      "user_name"

      iex> ToonEx.Encode.Strings.encode_key("user.name") |> IO.iodata_to_binary()
      "user.name"

      iex> ToonEx.Encode.Strings.encode_key("user name") |> IO.iodata_to_binary()
      ~s("user name")

      iex> ToonEx.Encode.Strings.encode_key("123") |> IO.iodata_to_binary()
      ~s("123")
  """
  @spec encode_key(String.t()) :: iodata()
  def encode_key(key) when is_binary(key) do
    if safe_key?(key) do
      key
    else
      [?", escape_string(key), ?"]
    end
  end

  @doc """
  Escapes special characters in a string using chunk-based approach.

  Instead of copying every byte into a new binary, this uses `binary_part/3`
  to reference safe chunks of the original string without copying. Only the
  escape sequences are newly allocated.

  ## How it works

  The algorithm uses two mutually recursive functions:

  1. `escape_string/4` — main loop that scans for bytes needing escaping
  2. `escape_string_chunk/5` — accumulates consecutive safe bytes into a chunk

  When a safe byte is encountered, we enter chunk mode and keep extending the
  chunk length. When we hit a byte that needs escaping, we flush the accumulated
  chunk via `binary_part(original, skip, len)` (O(1) reference), append the
  escape sequence, and continue scanning.

  ## Examples

      iex> ToonEx.Encode.Strings.escape_string("hello") |> IO.iodata_to_binary()
      "hello"

      iex> ToonEx.Encode.Strings.escape_string("line1\\nline2") |> IO.iodata_to_binary()
      "line1\\\\nline2"

      iex> result = ToonEx.Encode.Strings.escape_string(~s(say "hello"))
      iex> IO.iodata_to_binary(result) |> String.contains?(~s(\\"))
      true

      iex> ToonEx.Encode.Strings.escape_string("") |> IO.iodata_to_binary()
      ""
  """
  @spec escape_string(String.t()) :: iodata()
  def escape_string(data) when is_binary(data) do
    escape_string(data, [], data, 0)
  end

  # ── Main escape loop ────────────────────────────────────────────────────────
  # Scans for bytes that need escaping. When a safe byte is found,
  # delegates to the chunk accumulation loop.
  #
  # State: {rest, acc, original, skip}
  #   rest     — remaining bytes to process
  #   acc      — accumulated iodata (chunk references and escape sequences)
  #   original — the original binary (for binary_part references)
  #   skip     — offset into original where current chunk would start

  # Backslash needs escaping: \ → \\
  defp escape_string(<<?\\, rest::binary>>, acc, original, skip) do
    acc = [acc | escape_byte(?\\)]
    escape_string(rest, acc, original, skip + 1)
  end

  # Double quote needs escaping: " → \"
  defp escape_string(<<?", rest::binary>>, acc, original, skip) do
    acc = [acc | escape_byte(?")]
    escape_string(rest, acc, original, skip + 1)
  end

  # Newline needs escaping: \n → \\n
  defp escape_string(<<?\n, rest::binary>>, acc, original, skip) do
    acc = [acc | escape_byte(?\n)]
    escape_string(rest, acc, original, skip + 1)
  end

  # Carriage return needs escaping: \r → \\r
  defp escape_string(<<?\r, rest::binary>>, acc, original, skip) do
    acc = [acc | escape_byte(?\r)]
    escape_string(rest, acc, original, skip + 1)
  end

  # Tab needs escaping: \t → \\t
  defp escape_string(<<?\t, rest::binary>>, acc, original, skip) do
    acc = [acc | escape_byte(?\t)]
    escape_string(rest, acc, original, skip + 1)
  end

  # Control characters (U+0000 to U+001F, U+007F) — escape as \uXXXX
  defp escape_string(<<byte, rest::binary>>, acc, original, skip) when byte < 32 or byte == 127 do
    replacement = "\\u#{escape_control(byte)}"
    escape_string(rest, [acc | replacement], original, skip + 1)
  end

  # Safe ASCII byte (0x00-0x7F, excluding control chars and the 5 chars above) — enter chunk mode
  defp escape_string(<<byte, rest::binary>>, acc, original, skip) when byte < 128 do
    escape_string_chunk(rest, acc, original, skip, 1)
  end

  # Multi-byte UTF-8 byte (>= 128) — enter chunk mode (no escaping needed)
  defp escape_string(<<_byte, rest::binary>>, acc, original, skip) do
    escape_string_chunk(rest, acc, original, skip, 1)
  end

  # End of input — return accumulated iodata (no trailing chunk to flush)
  defp escape_string(<<>>, acc, _original, _skip) do
    acc
  end

  # ── Chunk accumulation loop ─────────────────────────────────────────────────
  # Keeps scanning safe bytes, extending the chunk length. When a byte needing
  # escaping is found, flushes the chunk via binary_part/3 and appends the escape.
  #
  # State: {rest, acc, original, skip, len}
  #   len — length of the current safe chunk

  # Backslash in chunk — flush chunk, then escape
  defp escape_string_chunk(<<?\\, rest::binary>>, acc, original, skip, len) do
    part = binary_part(original, skip, len)
    acc = [acc, part | escape_byte(?\\)]
    escape_string(rest, acc, original, skip + len + 1)
  end

  # Double quote in chunk — flush chunk, then escape
  defp escape_string_chunk(<<?", rest::binary>>, acc, original, skip, len) do
    part = binary_part(original, skip, len)
    acc = [acc, part | escape_byte(?")]
    escape_string(rest, acc, original, skip + len + 1)
  end

  # Newline in chunk — flush chunk, then escape
  defp escape_string_chunk(<<?\n, rest::binary>>, acc, original, skip, len) do
    part = binary_part(original, skip, len)
    acc = [acc, part | escape_byte(?\n)]
    escape_string(rest, acc, original, skip + len + 1)
  end

  # Carriage return in chunk — flush chunk, then escape
  defp escape_string_chunk(<<?\r, rest::binary>>, acc, original, skip, len) do
    part = binary_part(original, skip, len)
    acc = [acc, part | escape_byte(?\r)]
    escape_string(rest, acc, original, skip + len + 1)
  end

  # Tab in chunk — flush chunk, then escape
  defp escape_string_chunk(<<?\t, rest::binary>>, acc, original, skip, len) do
    part = binary_part(original, skip, len)
    acc = [acc, part | escape_byte(?\t)]
    escape_string(rest, acc, original, skip + len + 1)
  end

  # Control characters (U+0000 to U+001F, U+007F) in chunk — flush chunk, then escape as \uXXXX
  defp escape_string_chunk(<<byte, rest::binary>>, acc, original, skip, len)
       when byte < 32 or byte == 127 do
    part = binary_part(original, skip, len)
    replacement = "\\u#{escape_control(byte)}"
    acc = [acc, part | replacement]
    escape_string(rest, acc, original, skip + len + 1)
  end

  # Safe ASCII byte in chunk — extend chunk length
  defp escape_string_chunk(<<byte, rest::binary>>, acc, original, skip, len)
       when byte < 128 do
    escape_string_chunk(rest, acc, original, skip, len + 1)
  end

  # Multi-byte UTF-8 byte in chunk — extend chunk length
  # (UTF-8 bytes >= 0x80 are never structure chars, never need escaping)
  defp escape_string_chunk(<<_byte, rest::binary>>, acc, original, skip, len) do
    escape_string_chunk(rest, acc, original, skip, len + 1)
  end

  # End of input in chunk — flush final chunk
  defp escape_string_chunk(<<>>, acc, original, skip, len) do
    part = binary_part(original, skip, len)
    [acc | part]
  end

  # ── Escape byte lookup ──────────────────────────────────────────────────────
  # Returns the escape sequence for each special character.
  # Inlined for zero-overhead dispatch.

  @compile {:inline, escape_byte: 1}
  defp escape_byte(?\\), do: "\\\\"
  defp escape_byte(?"), do: "\\\""
  defp escape_byte(?\n), do: "\\n"
  defp escape_byte(?\r), do: "\\r"
  defp escape_byte(?\t), do: "\\t"

  # Control characters (U+0000 to U+001F, U+007F) — emit \uXXXX
  defp escape_byte(byte) when byte < 32 or byte == 127 do
    "\\u#{escape_control(byte)}"
  end

  # Safe ASCII (printable) — pass through
  defp escape_byte(_byte), do: nil

  # Format a control character byte as 4-digit uppercase hex: U+001F → "001F"
  defp escape_control(byte) do
    hex = Integer.to_string(byte, 16) |> String.upcase()
    String.pad_leading(hex, 4, "0")
  end

  # ── Safe string detection ───────────────────────────────────────────────────

  @doc """
  Checks if a string can be used unquoted as a value.

  A string is safe unquoted if:
  - It's not empty
  - It doesn't have leading or trailing spaces
  - It's not a literal (true, false, null)
  - It doesn't look like a number
  - It doesn't contain structure characters or delimiters
  - It doesn't contain control characters
  - It doesn't start with a hyphen
  - It doesn't start with a hash (#)

  ## Examples

      iex> ToonEx.Encode.Strings.safe_unquoted?("hello", ",")
      true

      iex> ToonEx.Encode.Strings.safe_unquoted?("", ",")
      false

      iex> ToonEx.Encode.Strings.safe_unquoted?(" hello", ",")
      false

      iex> ToonEx.Encode.Strings.safe_unquoted?("true", ",")
      false

      iex> ToonEx.Encode.Strings.safe_unquoted?("42", ",")
      false
  """
  @spec safe_unquoted?(String.t(), String.t()) :: boolean()
  def safe_unquoted?(string, delimiter) when is_binary(string) do
    not (string == "" or needs_quoting_basic?(string) or
           needs_quoting_delimiter?(string, delimiter))
  end

  # Check basic quoting requirements (leading/trailing spaces, literals, numbers, structure)
  defp needs_quoting_basic?(string) do
    has_leading_or_trailing_space?(string) or
      literal?(string) or
      looks_like_number?(string) or
      contains_structure_chars?(string) or
      contains_control_chars?(string) or
      starts_with_hyphen?(string) or
      starts_with_hash?(string)
  end

  # Check delimiter-specific quoting requirements
  defp needs_quoting_delimiter?(string, delimiter) do
    contains_delimiter?(string, delimiter)
  end

  @doc """
  Checks if a string can be used as an unquoted key.

  A key is safe if it matches /^[A-Za-z_][A-Za-z0-9_.]*$/i

  ## Examples

      iex> ToonEx.Encode.Strings.safe_key?("name")
      true

      iex> ToonEx.Encode.Strings.safe_key?("user_name")
      true

      iex> ToonEx.Encode.Strings.safe_key?("User123")
      true

      iex> ToonEx.Encode.Strings.safe_key?("user.name")
      true

      iex> ToonEx.Encode.Strings.safe_key?("user-name")
      false

      iex> ToonEx.Encode.Strings.safe_key?("123")
      false
  """
  # Performance: Binary character range checks instead of regex
  # Matches: ^[A-Za-z_][A-Za-z0-9_.]*$
  @spec safe_key?(String.t()) :: boolean()
  def safe_key?(<<first, rest::binary>>) do
    do_safe_key_first?(first) and do_safe_key_rest?(rest)
  end

  def safe_key?(_), do: false

  # First character: must be A-Z, a-z, or _
  defp do_safe_key_first?(c) when c in ?A..?Z, do: true
  defp do_safe_key_first?(c) when c in ?a..?z, do: true
  defp do_safe_key_first?(_), do: false

  # Remaining characters: A-Z, a-z, 0-9, _, or .
  defp do_safe_key_rest?(<<>>), do: true
  defp do_safe_key_rest?(<<c, rest::binary>>) when c in ?A..?Z, do: do_safe_key_rest?(rest)
  defp do_safe_key_rest?(<<c, rest::binary>>) when c in ?a..?z, do: do_safe_key_rest?(rest)
  defp do_safe_key_rest?(<<c, rest::binary>>) when c in ?0..?9, do: do_safe_key_rest?(rest)
  defp do_safe_key_rest?(<<?_, rest::binary>>), do: do_safe_key_rest?(rest)
  defp do_safe_key_rest?(<<?., rest::binary>>), do: do_safe_key_rest?(rest)
  defp do_safe_key_rest?(_), do: false

  # ── Private helpers ─────────────────────────────────────────────────────────

  # Performance: Binary pattern matching instead of String.starts_with?/String.ends_with?
  # Avoids 2 intermediate allocations for O(1) byte checks
  defp has_leading_or_trailing_space?(<<?\s, _::binary>>), do: true
  defp has_leading_or_trailing_space?(string), do: :binary.last(string) == ?\s

  defp contains_structure_chars?(string), do: do_contains_structure_chars?(string)
  defp contains_control_chars?(string), do: do_contains_control_chars?(string)

  @compile {:inline, literal?: 1}
  defp literal?("true"), do: true
  defp literal?("false"), do: true
  defp literal?("null"), do: true
  defp literal?(_), do: false

  # State machine for number detection: /^-?\d+(?:\.\d+)?(?:e[+-]?\d+)?$/i
  # Also accepts leading + sign: /^[+-]?\d+(?:\.\d+)?(?:e[+-]?\d+)?$/i
  defp looks_like_number?(string) do
    do_looks_like_number?(string, :start)
  end

  # :start — optional minus or plus, then digits
  defp do_looks_like_number?(<<?-, rest::binary>>, :start),
    do: do_looks_like_number?(rest, :digits)

  defp do_looks_like_number?(<<?+, rest::binary>>, :start),
    do: do_looks_like_number?(rest, :digits)

  defp do_looks_like_number?(<<c, rest::binary>>, :start) when c in ?0..?9,
    do: do_looks_like_number?(rest, :digits)

  defp do_looks_like_number?(_, :start), do: false

  # :digits — digits, or dot, or exponent
  defp do_looks_like_number?(<<>>, :digits), do: true

  defp do_looks_like_number?(<<c, rest::binary>>, :digits) when c in ?0..?9,
    do: do_looks_like_number?(rest, :digits)

  defp do_looks_like_number?(<<?., rest::binary>>, :digits),
    do: do_looks_like_number?(rest, :frac)

  defp do_looks_like_number?(<<c, rest::binary>>, :digits) when c == ?e or c == ?E,
    do: do_looks_like_number?(rest, :exp_sign)

  defp do_looks_like_number?(_, :digits), do: false

  # :frac — digits after decimal point, or exponent
  defp do_looks_like_number?(<<>>, :frac), do: true

  defp do_looks_like_number?(<<c, rest::binary>>, :frac) when c in ?0..?9,
    do: do_looks_like_number?(rest, :frac)

  defp do_looks_like_number?(<<c, rest::binary>>, :frac) when c == ?e or c == ?E,
    do: do_looks_like_number?(rest, :exp_sign)

  defp do_looks_like_number?(_, :frac), do: false

  # :exp_sign — optional +/- after exponent, then digits
  defp do_looks_like_number?(<<c, rest::binary>>, :exp_sign) when c == ?+ or c == ?-,
    do: do_looks_like_number?(rest, :exp_digits)

  defp do_looks_like_number?(<<c, rest::binary>>, :exp_sign) when c in ?0..?9,
    do: do_looks_like_number?(rest, :exp_digits)

  defp do_looks_like_number?(_, :exp_sign), do: false

  # :exp_digits — digits after exponent
  defp do_looks_like_number?(<<>>, :exp_digits), do: true

  defp do_looks_like_number?(<<c, rest::binary>>, :exp_digits) when c in ?0..?9,
    do: do_looks_like_number?(rest, :exp_digits)

  defp do_looks_like_number?(_, :exp_digits), do: false

  # Single-pass binary scan for structure characters
  @compile {:inline, do_contains_structure_chars?: 1}
  defp do_contains_structure_chars?(<<>>), do: false
  defp do_contains_structure_chars?(<<?:, _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?[, _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?], _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?{, _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?}, _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?(, _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<41, _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?", _rest::binary>>), do: true
  defp do_contains_structure_chars?(<<?\\, _rest::binary>>), do: true

  defp do_contains_structure_chars?(<<_byte, rest::binary>>),
    do: do_contains_structure_chars?(rest)

  # Delimiter check — uses String.contains? for correct variable handling
  @compile {:inline, contains_delimiter?: 2}
  defp contains_delimiter?(string, delimiter) do
    String.contains?(string, delimiter)
  end

  # Single-pass binary scan for control characters
  @compile {:inline, do_contains_control_chars?: 1}
  defp do_contains_control_chars?(<<>>), do: false
  defp do_contains_control_chars?(<<?\n, _rest::binary>>), do: true
  defp do_contains_control_chars?(<<?\r, _rest::binary>>), do: true
  defp do_contains_control_chars?(<<?\t, _rest::binary>>), do: true
  defp do_contains_control_chars?(<<?\b, _rest::binary>>), do: true
  defp do_contains_control_chars?(<<?\f, _rest::binary>>), do: true
  defp do_contains_control_chars?(<<_byte, rest::binary>>), do: do_contains_control_chars?(rest)

  # Performance: Binary pattern matching instead of String.starts_with?
  defp starts_with_hyphen?(<<?-, _::binary>>), do: true
  defp starts_with_hyphen?(_), do: false

  defp starts_with_hash?(<<"#", _::binary>>), do: true
  defp starts_with_hash?(_), do: false
end
