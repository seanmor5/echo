defmodule Echo.SpeechToText do
  @doc """
  Generic TTS Module.
  """

  def transcribe(audio) do
    provider().transcribe(audio)
  end

  defp provider, do: env(:provider)

  defp env(key), do: :echo |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(key)
end
