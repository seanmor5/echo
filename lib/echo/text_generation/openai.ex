defmodule Echo.TextGeneration.OpenAI do
  @behaviour Echo.TextGeneration.Provider

  @impl true
  def chat_completion(messages) do
    opts = Keyword.merge([messages: messages], config())

    OpenAI.chat_completion(opts)
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
