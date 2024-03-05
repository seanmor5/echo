defmodule Echo.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [EchoWeb.Telemetry] ++ servings() ++ [Echo.VAD, EchoWeb.Endpoint]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Echo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp servings() do
    stt_serving =
      {Nx.Serving,
       name: Echo.SpeechToText,
       serving: Echo.SpeechToText.Bumblebee.serving(),
       batch_size: 1,
       batch_timeout: 10}

    if Application.fetch_env!(:echo, Echo.TextGeneration)[:provider] == "bumblebee" do
      [
        stt_serving,
        {Nx.Serving,
         name: Echo.TextGeneration,
         serving: Echo.TextGeneration.Bumblebee.serving(),
         batch_size: 1,
         batch_timeout: 10}
      ]
    else
      [stt_serving]
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EchoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
