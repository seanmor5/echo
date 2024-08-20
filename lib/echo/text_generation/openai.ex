defmodule Echo.TextGeneration.OpenAI do
  @behaviour Echo.TextGeneration.Provider

  require Logger

  @impl true
  def chat_completion(opts) when is_list(opts) do
    config = config()
    merged_opts = Keyword.merge(config, opts)

    # Ensure the model is a string
    model = Keyword.get(merged_opts, :model)
    model = if is_tuple(model), do: elem(model, 1), else: model
    merged_opts = Keyword.put(merged_opts, :model, model)

    Logger.debug("Sending chat completion request with options: #{inspect(merged_opts)}")

    OpenAI.chat_completion(merged_opts)
    |> Stream.map(&get_in(&1, ["choices", Access.at(0), "delta", "content"]))
    |> Stream.reject(&is_nil/1)
  end

  defp config do
    [
      model: env(:model),
      max_tokens: env(:max_tokens),
      stream: true
    ]
  end

  defp env(key), do: :echo |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(key)
end
