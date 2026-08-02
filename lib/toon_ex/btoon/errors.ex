defmodule ToonEx.Btoon.EncodeError do
  @moduledoc """
  Exception raised when BTOON encoding fails.

  Raised when a value cannot be represented in the BTOON data model, a
  schema field is missing or has the wrong type, or an integer overflows
  its declared width.
  """

  defexception [:message, :value, :reason]

  @type t :: %__MODULE__{
          message: String.t(),
          value: term(),
          reason: term()
        }

  @impl true
  def exception(opts) when is_list(opts) do
    %__MODULE__{
      message: Keyword.get(opts, :message, "encode error"),
      value: Keyword.get(opts, :value),
      reason: Keyword.get(opts, :reason)
    }
  end

  def exception(message) when is_binary(message) do
    %__MODULE__{message: message, value: nil, reason: nil}
  end

  @impl true
  def message(%__MODULE__{message: message, value: nil}), do: message

  def message(%__MODULE__{message: message, value: value}) do
    "#{message}: #{inspect(value)}"
  end
end

defmodule ToonEx.Btoon.DecodeError do
  @moduledoc """
  Exception raised when BTOON decoding fails.

  Raised when the input is malformed: bad magic, unsupported version,
  truncated data, invalid type tags, out-of-range string refs, alignment or
  nesting-limit violations.
  """

  defexception [:message, :input, :offset, :reason]

  @type t :: %__MODULE__{
          message: String.t(),
          input: binary() | nil,
          offset: non_neg_integer() | nil,
          reason: term()
        }

  @impl true
  def exception(opts) when is_list(opts) do
    %__MODULE__{
      message: Keyword.get(opts, :message, "decode error"),
      input: Keyword.get(opts, :input),
      offset: Keyword.get(opts, :offset),
      reason: Keyword.get(opts, :reason)
    }
  end

  def exception(message) when is_binary(message) do
    %__MODULE__{message: message, input: nil, offset: nil, reason: nil}
  end

  @impl true
  def message(%__MODULE__{message: message, offset: nil}), do: message

  def message(%__MODULE__{message: message, offset: offset}) do
    "#{message} (at offset #{offset})"
  end
end
