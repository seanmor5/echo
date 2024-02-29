defmodule Echo.SpeechToText.Bumblebee do
  @behaviour Echo.SpeechToText.Provider

  @impl true
  def transcribe(audio) do
    output = Nx.Serving.batched_run(Echo.SpeechToText, audio)
    output.chunks |> Enum.map_join(& &1.text) |> String.trim()
  end

  def serving() do
    repo = {:hf, env(:repo)}

    {:ok, model_info} =
      Bumblebee.load_model(repo,
        type: Axon.MixedPrecision.create_policy(params: {:f, 16}, compute: {:f, 16})
      )

    {:ok, featurizer} = Bumblebee.load_featurizer(repo)
    {:ok, tokenizer} = Bumblebee.load_tokenizer(repo)
    {:ok, generation_config} = Bumblebee.load_generation_config(repo)

    Bumblebee.Audio.speech_to_text_whisper(model_info, featurizer, tokenizer, generation_config,
      task: nil,
      compile: [batch_size: 1],
      defn_options: [compiler: EXLA]
    )
  end

  defp env(key), do: :echo |> Application.fetch_env!(__MODULE__) |> Keyword.fetch!(key)
end
