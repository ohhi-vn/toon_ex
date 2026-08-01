defmodule ToonEx.Encode.Writer do
  @moduledoc """
  Writer for building TOON output incrementally with efficient indentation handling.
  """
  alias ToonEx.Constants

  @type t :: %__MODULE__{lines: [iodata()], indent_string: String.t(), indent_cache: map()}
  defstruct lines: [], indent_string: "  ", indent_cache: %{}

  def new(indent_size \\ 2) when is_integer(indent_size) and indent_size > 0 do
    %__MODULE__{lines: [], indent_string: String.duplicate(" ", indent_size), indent_cache: %{}}
  end

  # Performance: Use :binary.copy for repeated string duplication - faster than String.duplicate
  @compile {:inline, build_indent: 2}
  defp build_indent(writer, depth) when depth >= 0 do
    case Map.fetch(writer.indent_cache, depth) do
      {:ok, indent} ->
        {writer, indent}

      :error ->
        indent = :binary.copy(writer.indent_string, depth)
        writer = %{writer | indent_cache: Map.put(writer.indent_cache, depth, indent)}
        {writer, indent}
    end
  end

  def push(%__MODULE__{} = w, content, depth) when is_integer(depth) and depth >= 0 do
    {writer, indent} = build_indent(w, depth)
    %{writer | lines: [[indent, content] | writer.lines]}
  end

  def push_many(%__MODULE__{} = w, lines, depth) when is_list(lines) do
    {writer, indent} = build_indent(w, depth)
    new_lines = Enum.reduce(lines, writer.lines, fn line, acc -> [[indent, line] | acc] end)
    %{writer | lines: new_lines}
  end

  # Performance: Use :lists.reverse instead of Enum.reverse for better performance
  @spec to_lines(t()) :: [iodata()]
  def to_lines(%__MODULE__{lines: lines}), do: :lists.reverse(lines)

  # Performance: Build iodata tree directly without Enum.intersperse intermediate list
  @spec to_iodata(t()) :: iodata()
  def to_iodata(%__MODULE__{} = w) do
    lines = to_lines(w)
    newline = Constants.newline()
    do_build_iodata(lines, newline, [])
  end

  # Tail-recursive iodata builder - avoids Enum.intersperse allocation
  defp do_build_iodata([], _newline, acc), do: :lists.reverse(acc)
  defp do_build_iodata([line], _newline, acc), do: :lists.reverse([line | acc])

  defp do_build_iodata([line | rest], newline, acc),
    do: do_build_iodata(rest, newline, [newline, line | acc])

  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{} = w), do: IO.iodata_to_binary(to_iodata(w))

  def line_count(%__MODULE__{lines: lines}), do: length(lines)
  def empty?(%__MODULE__{lines: []}), do: true
  def empty?(%__MODULE__{}), do: false
end
