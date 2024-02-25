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
        text = Enum.join(text)
        ElevenLabs.WebSocket.send(pid, text)
        text
      end)
      |> Enum.join()

    ElevenLabs.WebSocket.flush(pid)

    result
  end

  defp group_tokens(stream) do
    Stream.transform(stream, {[], []}, fn item, {current_chunk, _acc} ->
      updated_chunk = [item | current_chunk]

      if String.ends_with?(item, @separators) do
        {[Enum.reverse(updated_chunk)], {[], []}}
      else
        {[], {updated_chunk, []}}
      end
    end)
    |> Stream.flat_map(fn
      {[], []} -> []
      chunk -> [chunk]
    end)
  end
end
