defmodule Echo.TextToSpeech do
  @moduledoc """
  Generic TTS module.
  """
  alias Echo.Client.ElevenLabs
  require Logger

  @separators [".", ",", "?", "!", ";", ":", "—", "-", "(", ")", "[", "]", "}", " "]

  defmodule Error do
    defexception [:message, :reason]

    @type t :: %__MODULE__{
            message: String.t(),
            reason: :connection_closed | :send_failed | :flush_failed | any()
          }
  end

  @doc """
  Consumes an Enumerable (such as a stream) of text
  into speech, applying `fun` to each audio element.

  Returns the spoken text contained within `enumerable`.

  Raises `Echo.TextToSpeech.Error` if an error occurs during streaming.
  """
  @spec stream(Enumerable.t(), pid()) :: String.t() | no_return()
  def stream(enumerable, pid) do
    result =
      enumerable
      |> group_tokens()
      |> Stream.map(fn text ->
        text = IO.iodata_to_binary(text)

        case send_text(pid, text) do
          :ok -> text
          {:error, reason} -> raise Error, message: "WebSocket send failed", reason: reason
        end
      end)
      |> Enum.join()

    case flush_websocket(pid) do
      :ok -> result
      {:error, reason} -> raise Error, message: "WebSocket flush failed", reason: reason
    end
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

  defp send_text(pid, text) do
    case ElevenLabs.WebSocket.send(pid, text) do
      :ok ->
        :ok

      {:error, :not_alive} ->
        Logger.error("WebSocket connection is closed.")
        {:error, :connection_closed}

      {:error, reason} ->
        Logger.error("Failed to send text: #{inspect(reason)}")
        {:error, :send_failed}
    end
  end

  defp flush_websocket(pid) do
    try do
      ElevenLabs.WebSocket.flush(pid)
    rescue
      e ->
        Logger.error("Failed to flush WebSocket: #{inspect(e)}")
        {:error, :flush_failed}
    end
  end
end
