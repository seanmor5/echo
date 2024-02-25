defmodule Echo.TextGeneration do
  @moduledoc """
  Generic Text Generation module.
  """

  def chat_completion(opts \\ []) do
    # for now we just shell out to OpenAI
    OpenAI.chat_completion(opts)
    |> Stream.map(&get_in(&1, ["choices", Access.at(0), "delta", "content"]))
    |> Stream.reject(&is_nil/1)
  end
end
