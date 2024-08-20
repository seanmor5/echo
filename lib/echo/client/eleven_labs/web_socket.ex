defmodule Echo.Client.ElevenLabs.WebSocket do
  use WebSockex

  require Logger

  @reconnect_interval 5000
  @keepalive_interval 15000

  ## Client

  def start_link(broadcast_fun, token) do
    state = %{
      fun: broadcast_fun,
      token: token,
      keepalive_timer: nil,
      reconnect_timer: nil
    }

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

    WebSockex.start_link(url, __MODULE__, state,
      extra_headers: headers,
      handle_initial_conn_failure: true
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
    if Process.alive?(pid) do
      msg = Jason.encode!(%{text: "#{text} ", try_trigger_generation: true})
      WebSockex.send_frame(pid, {:text, msg})
    else
      Logger.error("WebSocket process is not alive.")
      {:error, :not_alive}
    end
  end

  def flush(pid) do
    msg = Jason.encode!(%{text: " ", try_trigger_generation: true, flush: true})
    WebSockex.send_frame(pid, {:text, msg})
  end

  def update_token(pid, token) do
    WebSockex.cast(pid, {:update_token, {:binary, token}})
  end

  ## Server

  def handle_connect(_conn, state) do
    Logger.info("Connected to ElevenLabs WebSocket")
    {:ok, schedule_keepalive(state)}
  end

  def handle_disconnect(%{reason: {:local, reason}}, state) do
    Logger.warning("Local disconnect: #{inspect(reason)}. Reconnecting...")
    {:reconnect, schedule_reconnect(state)}
  end

  def handle_disconnect(disconnect_map, state) do
    Logger.warning("Disconnected: #{inspect(disconnect_map)}. Reconnecting...")
    {:reconnect, schedule_reconnect(state)}
  end

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

  def handle_info(:keepalive, state) do
    Logger.debug("Sending keepalive")
    msg = Jason.encode!(%{text: " "})
    {:reply, {:text, msg}, schedule_keepalive(state)}
  end

  def handle_info(:reconnect, state) do
    Logger.info("Attempting to reconnect...")
    {:reconnect, state}
  end

  defp schedule_keepalive(state) do
    if state.keepalive_timer, do: Process.cancel_timer(state.keepalive_timer)
    timer = Process.send_after(self(), :keepalive, @keepalive_interval)
    %{state | keepalive_timer: timer}
  end

  defp schedule_reconnect(state) do
    if state.reconnect_timer, do: Process.cancel_timer(state.reconnect_timer)
    timer = Process.send_after(self(), :reconnect, @reconnect_interval)
    %{state | reconnect_timer: timer}
  end

  defp env(key), do: :echo |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(key)
end
