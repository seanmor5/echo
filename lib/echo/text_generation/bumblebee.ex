defmodule Echo.TextGeneration.Bumblebee do
  @behaviour Echo.TextGeneration.Provider

  @impl true
  def chat_completion(messages) do
    prompt = apply_chat_template(messages)

    Nx.Serving.batched_run(Echo.TextGeneration, prompt)
  end

  def serving() do
    repo = {:hf, env(:repo)}

    {:ok, model} = Bumblebee.load_model(repo, type: :bf16)
    {:ok, tokenizer} = Bumblebee.load_tokenizer(repo)
    {:ok, generation_config} = Bumblebee.load_generation_config(repo)

    generation_config = config(generation_config)

    Bumblebee.Text.generation(model, tokenizer, generation_config,
      defn_options: [compiler: EXLA],
      compile: [batch_size: 1, sequence_length: env(:max_sequence_length)],
      stream: true
    )
  end

  defp apply_chat_template(messages) do
    content =
      Enum.map_join(messages, "", fn
        %{role: "user", content: content} -> user_message(content)
        %{role: "assistant", content: content} -> assistant_message(content)
      end)

    "<s>#{content}"
  end

  defp user_message(content), do: "[INST]#{content}[/INST]"
  defp assistant_message(content), do: "#{String.replace(content, "</s>", "")}</s>"

  defp config(generation_config) do
    Bumblebee.configure(generation_config, %{
      max_new_tokens: env(:max_tokens),
      type: :multinomial_sampling,
      top_k: 4
    })
  end

  defp env(key), do: :echo |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(key)
end
