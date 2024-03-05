defmodule Echo.TextGeneration do
  @moduledoc """
  Generic Text Generation module.
  """

  def chat_completion(messages) do
    provider().chat_completion(messages)
  end

  defp provider, do: env(:provider)

  defp env(key), do: :echo |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(key)
end
