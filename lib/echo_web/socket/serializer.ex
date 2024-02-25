defmodule EchoWeb.Socket.Serializer do
  @behaviour Phoenix.Socket.Serializer

  def decode!(iodata, _options) do
    %Phoenix.Socket.Message{payload: List.to_string(iodata)}
  end

  def encode!(%{payload: data}), do: {:socket_push, :binary, data}

  def fastlane!(%{payload: data}), do: {:socket_push, :binary, data}
end
