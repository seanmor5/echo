defmodule Echo.SpeechToText do
  @doc """
  Generic TTS Module.
  """

  @repo "distil-whisper/distil-medium.en"

  def serving() do
    {:ok, model_info} =
      Bumblebee.load_model({:hf, @repo},
        type: Axon.MixedPrecision.create_policy(params: {:f, 16}, compute: {:f, 16})
      )

    {:ok, featurizer} = Bumblebee.load_featurizer({:hf, @repo})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, @repo})
    {:ok, generation_config} = Bumblebee.load_generation_config({:hf, @repo})

    Bumblebee.Audio.speech_to_text_whisper(model_info, featurizer, tokenizer, generation_config,
      task: nil,
      compile: [batch_size: 1],
      defn_options: [compiler: EXLA, debug: true]
    )
  end

  def transcribe(audio) do
    output = Nx.Serving.batched_run(__MODULE__, audio)
    output.chunks |> Enum.map_join(& &1.text) |> String.trim()
  end
end
