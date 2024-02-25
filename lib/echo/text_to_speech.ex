defmodule Echo.TextToSpeech do
  @moduledoc """
  Generic TTS module.
  """
  alias Echo.Client.ElevenLabs

  @separators [".", ",", "?", "!", ";", ":", "—", "-", "(", ")", "[", "]", "}", " "]

  @doc """
  Consumes an Enumerable (such as a stream) of text
  into speech, applying `fun` to each audio element.

  Returns the spoken text contained within `enumerable`.
  """
  def stream(enumerable, pid) do
    result =
      enumerable
      |> group_tokens()
      |> Stream.map(fn text ->
        text = IO.iodata_to_binary(text)
        ElevenLabs.WebSocket.send(pid, text)
        text
      end)
      |> Enum.join()

    ElevenLabs.WebSocket.flush(pid)

    result
  end

  defp group_tokens(stream) do
    Stream.transform(stream, {[], []}, fn item, {current_chunk, _acc} ->
      updated_chunk = [current_chunk, item]

      if String.ends_with?(item, @separators) do
        {[updated_chunk], {[], []}}
      else
        {[], {updated_chunk, []}}
      end
    end)
  end
end
