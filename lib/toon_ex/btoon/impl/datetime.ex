defimpl ToonEx.Btoon.Encoder, for: DateTime do
  def encode(%DateTime{} = struct, _opts) do
    DateTime.to_iso8601(struct)
  end
end

defimpl ToonEx.Btoon.Encoder, for: Date do
  def encode(%Date{} = struct, _opts) do
    Date.to_iso8601(struct)
  end
end

defimpl ToonEx.Btoon.Encoder, for: NaiveDateTime do
  def encode(%NaiveDateTime{} = struct, _opts) do
    NaiveDateTime.to_iso8601(struct)
  end
end
