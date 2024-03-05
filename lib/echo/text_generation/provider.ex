defmodule Echo.TextGeneration.Provider do
  @callback chat_completion(messages :: list()) :: Stream.t()
end
