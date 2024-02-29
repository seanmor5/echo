defmodule Echo.Client.ElevenLabs.WebSocket do
  use WebSockex

  require Logger

  ## Client

  def start_link(broadcast_fun, token) do
    headers = [{"xi-api-key", env(:api_key)}]

    params = %{
      model_id: env(:model_id),
      optimize_streaming_latency: env(:optimize_streaming_latency),
      output_format: env(:output_format)
    }

    url =
      URI.new!("wss://api.elevenlabs.io")
      |> URI.append_path("/v1/text-to-speech/#{env(:voice_id)}/stream-input")
      |> URI.append_query(URI.encode_query(params))
      |> URI.to_string()

    WebSockex.start_link(url, __MODULE__, %{fun: broadcast_fun, token: token},
      extra_headers: headers
    )
  end

  def open_stream(pid) do
    msg = Jason.encode!(%{text: " "})
    WebSockex.send_frame(pid, {:text, msg})

    pid
  end

  def close_stream(pid) do
    msg = Jason.encode!(%{text: ""})
    WebSockex.send_frame(pid, {:text, msg})
  end

  def send(pid, text) do
    msg = Jason.encode!(%{text: "#{text} ", try_trigger_generation: true})
    WebSockex.send_frame(pid, {:text, msg})
  end

  def flush(pid) do
    msg = Jason.encode!(%{text: " ", try_trigger_generation: true, flush: true})
    WebSockex.send_frame(pid, {:text, msg})
  end

  def update_token(pid, token) do
    WebSockex.cast(pid, {:update_token, {:binary, token}})
  end

  ## Server

  def handle_cast({:update_token, {:binary, token}}, state) do
    {:ok, %{state | token: token}}
  end

  def handle_frame({:text, msg}, %{fun: broadcast_fun, token: token} = state) do
    case Jason.decode!(msg) do
      %{"audio" => audio} when is_binary(audio) ->
        raw = Base.decode64!(audio)
        broadcast_fun.(token <> raw)

      error ->
        Logger.error("Something went wrong: #{inspect(error)}")
        :ok
    end

    {:ok, state}
  end

  defp env(key), do: :echo |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(key)
end
