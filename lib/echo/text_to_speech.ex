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

      if ends_with_separator?(item, @separators) do
        {[updated_chunk], {[], []}}
      else
        {[], {updated_chunk, []}}
      end
    end)
  end

  # This should be faster than String.ends_with?/2
  # but can only be done because we know the separators beforehand
  defp ends_with_separator?(text) do
    last_character = binary_part(text, byte_size(text) - 1, 1)
    is_separator?(last_character)
  end

  for separator <- @separators do
    defp is_separator?(@separators), do: true
  end

  defp is_separator?(_), do: false
end
