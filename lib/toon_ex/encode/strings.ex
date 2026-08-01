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
    # Single-pass escape with chunk tracking
    do_escape_string(data, data, 0, 0, [], byte_size(data))
  end

  # Single-pass escape loop with accumulator.
  # State: {rest, original, chunk_start, chunk_len, acc}
  #   rest         — remaining bytes to process
  #   original     — the original binary (for binary_part references)
  #   chunk_start  — offset into original where current chunk starts
  #   chunk_len    — length of current safe chunk being accumulated
  #   acc          — accumulated iodata (chunk references and escape sequences) in REVERSE order

  # Backslash needs escaping: \ → \\
  defp do_escape_string(<<?\\, rest::binary>>, original, chunk_start, chunk_len, acc, size_hint) do
    acc = flush_chunk(acc, original, chunk_start, chunk_len)

    do_escape_string(
      rest,
      original,
      chunk_start + chunk_len + 1,
      0,
      [escape_byte(?\\) | acc],
      size_hint
    )
  end

  # Double quote needs escaping: " → \"
  defp do_escape_string(<<?", rest::binary>>, original, chunk_start, chunk_len, acc, size_hint) do
    acc = flush_chunk(acc, original, chunk_start, chunk_len)

    do_escape_string(
      rest,
      original,
      chunk_start + chunk_len + 1,
      0,
      [escape_byte(?") | acc],
      size_hint
    )
  end

  # Newline needs escaping: \n → \\n
  defp do_escape_string(<<?\n, rest::binary>>, original, chunk_start, chunk_len, acc, size_hint) do
    acc = flush_chunk(acc, original, chunk_start, chunk_len)

    do_escape_string(
      rest,
      original,
      chunk_start + chunk_len + 1,
      0,
      [escape_byte(?\n) | acc],
      size_hint
    )
  end

  # Carriage return needs escaping: \r → \\r
  defp do_escape_string(<<?\r, rest::binary>>, original, chunk_start, chunk_len, acc, size_hint) do
    acc = flush_chunk(acc, original, chunk_start, chunk_len)

    do_escape_string(
      rest,
      original,
      chunk_start + chunk_len + 1,
      0,
      [escape_byte(?\r) | acc],
      size_hint
    )
  end

  # Tab needs escaping: \t → \\t
  defp do_escape_string(<<?\t, rest::binary>>, original, chunk_start, chunk_len, acc, size_hint) do
    acc = flush_chunk(acc, original, chunk_start, chunk_len)

    do_escape_string(
      rest,
      original,
      chunk_start + chunk_len + 1,
      0,
      [escape_byte(?\t) | acc],
      size_hint
    )
  end

  # Control characters (U+0000 to U+001F, U+007F) — escape as \uXXXX
  defp do_escape_string(<<byte, rest::binary>>, original, chunk_start, chunk_len, acc, size_hint)
       when byte < 32 or byte == 127 do
    acc = flush_chunk(acc, original, chunk_start, chunk_len)
    replacement = "\\u#{escape_control(byte)}"

    do_escape_string(
      rest,
      original,
      chunk_start + chunk_len + 1,
      0,
      [replacement | acc],
      size_hint
    )
  end

  # Safe ASCII byte (0x00-0x7F, excluding control chars and the 5 chars above) — extend chunk
  defp do_escape_string(<<byte, rest::binary>>, original, chunk_start, chunk_len, acc, size_hint)
       when byte < 128 do
    do_escape_string(rest, original, chunk_start, chunk_len + 1, acc, size_hint)
  end

  # Multi-byte UTF-8 byte (>= 128) — extend chunk (no escaping needed)
  defp do_escape_string(<<_byte, rest::binary>>, original, chunk_start, chunk_len, acc, size_hint) do
    do_escape_string(rest, original, chunk_start, chunk_len + 1, acc, size_hint)
  end

  # End of input — flush final chunk and reverse accumulator
  defp do_escape_string(<<>>, original, chunk_start, chunk_len, acc, _size_hint) do
    final_acc = flush_chunk(acc, original, chunk_start, chunk_len)
    :lists.reverse(final_acc)
  end

  # Flush accumulated chunk via binary_part (O(1) sub-binary reference)
  @compile {:inline, flush_chunk: 4}
  defp flush_chunk(acc, _original, _chunk_start, 0), do: acc

  defp flush_chunk(acc, original, chunk_start, chunk_len) do
    [binary_part(original, chunk_start, chunk_len) | acc]
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

  # Format a control character byte as 4-digit lowercase hex: U+001F → "001f"
  # (Integer.to_string/2 emits uppercase for base 16; the spec uses lowercase)
  defp escape_control(byte) do
    hex = Integer.to_string(byte, 16) |> String.downcase()
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
  defp do_safe_key_first?(?_), do: true
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

  # Single-pass binary scan for control characters (U+0000–U+001F)
  @compile {:inline, do_contains_control_chars?: 1}
  defp do_contains_control_chars?(<<>>), do: false
  defp do_contains_control_chars?(<<byte, _rest::binary>>) when byte < 32, do: true
  defp do_contains_control_chars?(<<_byte, rest::binary>>), do: do_contains_control_chars?(rest)

  # Performance: Binary pattern matching instead of String.starts_with?
  defp starts_with_hyphen?(<<?-, _::binary>>), do: true
  defp starts_with_hyphen?(_), do: false

  defp starts_with_hash?(<<"#", _::binary>>), do: true
  defp starts_with_hash?(_), do: false
end
