defmodule ToonEx.Btoon.TypedArrayTest do
  use ExUnit.Case, async: true

  alias ToonEx.Btoon.TypedArray
  alias ToonEx.Btoon.ObjectTable

  describe "TypedArray" do
    test "to_list materializes numbers" do
      ta = TypedArray.new(:int32, <<1::32-little, 300::32-little>>)
      assert TypedArray.to_list(ta) == [1, 300]
    end

    test "from_list picks the narrowest type" do
      assert %TypedArray{type: :int8, data: <<1, 2>>} = TypedArray.from_list([1, 2])
      assert %TypedArray{type: :float32} = TypedArray.from_list([1.5, 2.5])
    end

    test "new validates buffer size" do
      assert_raise ArgumentError, fn -> TypedArray.new(:int32, <<1>>) end
    end

    test "decode lists mode materializes elements" do
      bin = ToonEx.Btoon.encode!(TypedArray.from_list([1, 2, 3]))
      assert ToonEx.Btoon.decode!(bin) == [1, 2, 3]
      assert ToonEx.Btoon.decode!(bin, typed_arrays: :lists) == [1, 2, 3]
    end

    test "decode views mode returns the struct with a sub-binary" do
      bin = ToonEx.Btoon.encode!(TypedArray.from_list([1, 2, 3]))

      assert %TypedArray{type: :int8, data: data} =
               ToonEx.Btoon.decode!(bin, typed_arrays: :views)

      assert data == <<1, 2, 3>>
    end
  end

  describe "alignment" do
    test "data buffers are aligned to the element size" do
      for {type, data} <- [
            {:float64, <<1.5::64-little-float>>},
            {:float32, <<1.5::32-little-float>>},
            {:int16, <<1::16-little>>},
            {:int8, <<1>>}
          ] do
        bin =
          ToonEx.Btoon.encode!(%{
            "prefix" => "padding",
            "data" => TypedArray.new(type, data)
          })

        assert {:ok, %{"data" => ta}} = ToonEx.Btoon.decode(bin, typed_arrays: :views)
        assert %TypedArray{type: ^type} = ta
      end
    end

    test "nested typed array data offsets are element-aligned" do
      # Wrap in enough varying content that naive placement would misalign.
      ta = TypedArray.new(:float64, <<1.5::64-little-float>>)
      bin = ToonEx.Btoon.encode!([%{"x" => "s"}, ta, %{"y" => "longer string"}] |> Enum.reverse())

      {:ok, [%{"y" => _}, %TypedArray{data: data}, %{"x" => _}]} =
        ToonEx.Btoon.decode(bin, typed_arrays: :views)

      assert <<1.5::64-little-float>> = data
    end
  end

  describe "ObjectTable" do
    test "from_rows and rows round trip" do
      table =
        ObjectTable.from_rows([
          %{"x" => 1, "y" => 2.5},
          %{"x" => 3, "y" => 4.5}
        ])

      assert ObjectTable.rows(table) == [%{"x" => 1, "y" => 2.5}, %{"x" => 3, "y" => 4.5}]
    end

    test "from_rows rejects non-homogeneous input" do
      assert_raise ArgumentError, fn ->
        ObjectTable.from_rows([%{"x" => 1}, %{"y" => 2}])
      end
    end

    test "encode/decode list of maps round trips" do
      rows = [%{"x" => 1, "y" => 2.5}, %{"x" => 3, "y" => 4.5}]
      assert ToonEx.Btoon.decode!(ToonEx.Btoon.encode!(rows)) == rows
    end

    test "views mode returns the table struct" do
      bin = ToonEx.Btoon.encode!([%{"x" => 1, "y" => 2.5}, %{"x" => 3, "y" => 4.5}])

      assert %ObjectTable{
               row_count: 2,
               columns: [%ObjectTable.Column{name: "x"}, %ObjectTable.Column{name: "y"}]
             } =
               ToonEx.Btoon.decode!(bin, typed_arrays: :views)
    end

    test "column buffers are aligned and contiguous" do
      rows = [%{"a" => 1, "b" => 2.5}, %{"a" => 2, "b" => 4.5}]
      bin = ToonEx.Btoon.encode!(rows)

      {:ok,
       %ObjectTable{
         columns: [
           %ObjectTable.Column{type: :int8, data: a},
           %ObjectTable.Column{type: :float32, data: b}
         ]
       }} =
        ToonEx.Btoon.decode(bin, typed_arrays: :views)

      assert a == <<1, 2>>
      assert b == <<0, 0, 32, 64, 0, 0, 144, 64>>
    end
  end
end
