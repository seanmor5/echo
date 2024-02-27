defmodule Echo.VAD do
  @moduledoc """
  Voice-activity detection based on Silero-VAD ONNX model.

  Ideally, we would use Nx.Serving here, but unfortunately it does
  not currently support custom batch dimensions.
  """
  @sample_rate 16_000

  @threshold 0.5

  use GenServer

  ## Client

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :unused_state, name: __MODULE__)
  end

  def predict(audio) do
    GenServer.call(__MODULE__, {:predict, audio})
  end

  ## Server

  @impl true
  def init(_opts) do
    model = Ortex.load(Path.join([:code.priv_dir(:echo), "models", "silero_vad.onnx"]))

    {:ok,
     %{
       model: model,
       last: 0.0,
       h: Nx.broadcast(0.0, {2, 1, 64}),
       c: Nx.broadcast(0.0, {2, 1, 64})
     }}
  end

  @impl true
  def handle_call({:predict, audio}, _from, %{model: model, h: h, c: c} = state) do
    {prob, h, c} = do_predict(model, h, c, audio)
    prob = prob |> Nx.squeeze() |> Nx.to_number()
    {:reply, prob > @threshold, %{state | h: h, c: c}}
  end

  defp do_predict(model, h, c, audio) do
    input = Nx.from_binary(audio, :f32) |> Nx.new_axis(0)
    sr = Nx.tensor(@sample_rate)
    Ortex.run(model, {input, sr, h, c})
  end
end
