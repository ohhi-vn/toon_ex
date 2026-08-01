defmodule ToonEx.OrderedObject do
  @moduledoc """
  A TOON object that preserves the order of its keys.

  Elixir maps with 32 or fewer keys are stored in sorted order, so the
  encoder cannot recover the original insertion order from a plain map.
  Wrap your key-value pairs in a `%ToonEx.OrderedObject{}` (or use
  `ToonEx.OrderedObject.new/1`) to control the order in which fields are
  emitted.

  ## Example

      iex> obj = ToonEx.OrderedObject.new([{"id", 123}, {"name", "Ada"}, {"active", true}])
      iex> ToonEx.encode!(obj)
      "id: 123\\nname: Ada\\nactive: true"

  Nested objects, tabular arrays, and keyed tabular objects all preserve
  the order declared by the wrapping `OrderedObject`.
  """

  @type t :: %__MODULE__{values: [{String.t(), term()}]}

  defstruct values: []

  @doc """
  Creates an ordered object from a list of key-value pairs.
  """
  @spec new([{String.t(), term()}]) :: t()
  def new(values) when is_list(values) do
    %__MODULE__{values: values}
  end
end
