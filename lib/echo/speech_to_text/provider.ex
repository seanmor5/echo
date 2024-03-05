defmodule Echo.SpeechToText.Provider do
  @callback transcribe(audio :: binary()) :: binary()
end
