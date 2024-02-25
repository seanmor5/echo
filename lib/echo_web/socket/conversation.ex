defmodule EchoWeb.Socket.Conversation do
  @moduledoc """
  Implements a WebSocket API for a conversational agent.

  Possible states:

    - `:closed` - doing nothing
    - `:waiting` - waiting for voice activity
    - `:listening` - listening to voice activity
    - `:transcribing` - actively transcribing a message
    - `:replying` - pushing audio

  We open in a closed state, until we receive a message to kick off
  the conversation from the user. That message can contain conversation
  parameters to include the prompt, and other settings.
  """
  alias Echo.Client.ElevenLabs.WebSocket

  require Logger

  @behaviour Phoenix.Socket.Transport

  @impl true
  def child_spec(_opts) do
    # We won't spawn any process, so let's ignore the child spec
    :ignore
  end

  @impl true
  def connect(_connect_opts) do
    # Callback to retrieve relevant data from the connection.
    # The map contains options, params, transport and endpoint keys.
    {:ok, %{}}
  end

  @impl true
  def init(_state) do
    {:ok,
     %{
       mode: :closed,
       last_audio_buffer: "",
       accumulated_audio_buffer: "",
       transcription_pid: nil,
       reply_pid: nil,
       tts_pid: nil,
       chat: []
     }}
  end

  @impl true
  def handle_in({msg, _opts}, state) do
    decoded = Msgpax.unpack!(msg)
    handle_message(decoded, state)
  end

  @impl true
  def handle_info({ref, transcription}, state) when ref == state.transcription_pid.ref do
    chat = state.chat ++ [%{role: "user", content: transcription}]
    state = reply(%{state | chat: chat})
    {:ok, %{state | transcription_pid: nil}}
  end

  def handle_info({ref, response}, state) when ref == state.reply_pid.ref do
    chat = state.chat ++ [%{role: "assistant", content: response}]
    {:ok, %{state | reply_pid: nil, chat: chat}}
  end

  def handle_info({:token, token}, state) do
    message = Msgpax.pack!(%{type: "token", token: token})
    {:push, {:binary, message}, state}
  end

  def handle_info({:audio, data}, state) do
    message = Msgpax.pack!(%{type: "audio", audio: Msgpax.Bin.new(data)})
    {:push, {:binary, message}, state}
  end

  def handle_info(_, state) do
    Logger.info("Ignored message")
    {:ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    WebSocket.close_stream(state.tts_pid)
  end

  ## Helpers

  defp handle_message(%{"type" => "open", "prompt" => prompt}, %{mode: :closed} = state) do
    chat = [%{role: "system", content: prompt}, %{role: "user", content: "Hello!"}]
    target = self()

    # Start TTS pid and sync tokens
    token = tts_token()

    {:ok, tts_pid} =
      WebSocket.start_link(fn audio ->
        send(target, {:audio, audio})
      end, token)
    tts_pid = WebSocket.open_stream(tts_pid)

    # Update state, and start conversation
    state = reply(%{state | tts_pid: tts_pid, chat: chat})

    # Push token to client
    message = Msgpax.pack!(%{type: "token", token: token})

    {:push, {:binary, message}, state}
  end

  defp handle_message(%{"type" => "open"}, state) do
    Logger.info("Received open message in already-open state. Ignoring...")
    {:ok, state}
  end

  defp handle_message(%{"type" => "close"}, state) do
    Logger.info("Received close message. Closing connection...")
    {:stop, :normal, state}
  end

  defp handle_message(%{"type" => "audio", "audio" => data}, %{mode: mode} = state) do
    voice_detected? = Echo.VAD.predict(data)

    case {voice_detected?, mode} do
      {true, :waiting} ->
        # if we are waiting or listening and detect voice activity,
        # then we enter a listening state and start accumulating
        # incoming audio to transcribe
        state = %{
          state
          | last_audio_buffer: data,
            accumulated_audio_buffer: state.last_audio_buffer <> data,
            mode: :listening
        }

        {:ok, state}

      {true, :listening} ->
        # if we are listening and detect voice activity,
        # then we continue listening and accumulating
        state = %{
          state
          | last_audio_buffer: data,
            accumulated_audio_buffer: state.accumulated_audio_buffer <> data,
            mode: :listening
        }

        {:ok, state}

      {true, :replying} ->
        # if we detect voice activity while we are replying,
        # then we need to push an interrupt to the client to
        # stop speaking
        state = %{
          state
          | last_audio_buffer: data,
            accumulated_audio_buffer: state.last_audio_buffer <> data,
            mode: :listening
        }

        # any interrupt needs to cycle the tts token, so we avoid
        # a race condition of sending dead audio to the audio queue
        token = tts_token()
        WebSocket.update_token(state.tts_pid, token)
        message = Msgpax.pack!(%{type: "interrupt", token: token})
        {:push, {:binary, message}, state}

      {true, :transcribing} ->
        # if we detect voice activity while we are transcribing,
        # then I'm honestly not sure what to do except maybe just
        # accumulate transcription pids and concat all of the transcriptions
        # together, for now this is ignored
        # TODO:
        {:ok, state}

      {false, :listening} ->
        # if we are listening and do not detect voice activity,
        # then we clear the buffers and trigger transcription
        state = transcribe(data, state)
        {:ok, state}

      {false, mode} when mode in [:waiting, :replying, :transcribing] ->
        # if we are waiting, replying, or transcribing and do not
        # detect voice activity, then we do nothing
        state = %{state | last_audio_buffer: data}
        {:ok, state}

      {_, :closed} ->
        # just ignore anything in the closed state, we shouldn't even
        # be pushing audio in this state
        {:ok, state}
    end
  end

  defp handle_message(%{"type" => "state", "state" => "waiting"}, state) do
    {:ok, %{state | mode: :waiting}}
  end

  defp transcribe(data, %{accumulated_audio_buffer: buffer} = state) do
    final_buffer = buffer <> data
    transcription_pid = start_transcription(final_buffer)

    %{
      state
      | transcription_pid: transcription_pid,
        last_audio_buffer: data,
        accumulated_audio_buffer: "",
        mode: :transcribing
    }
  end

  defp reply(%{chat: chat, tts_pid: tts_pid} = state) do
    response =
      Echo.TextGeneration.chat_completion(
        model: "gpt-3.5-turbo",
        messages: chat,
        max_tokens: 400,
        stream: true
      )

    reply_pid = start_speaking(response, tts_pid)
    %{state | reply_pid: reply_pid, mode: :replying}
  end

  defp start_speaking(response, tts_pid) do
    Task.async(fn ->
      Echo.TextToSpeech.stream(response, tts_pid)
    end)
  end

  defp start_transcription(buffer) do
    Task.async(fn ->
      buffer
      |> Nx.from_binary(:f32)
      |> Echo.SpeechToText.transcribe()
    end)
  end

  defp tts_token() do
    for _ <- 1..8, into: "", do: <<Enum.random(?a..?z)>>
  end
end
