defmodule Echo.TextGeneration do
  @moduledoc """
  Generic Text Generation module.
  """

  def chat_completion(opts \\ []) do
    # for now we just shell out to OpenAI
    OpenAI.chat_completion(opts)
  end
end
