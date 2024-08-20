import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/echo start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.

# LLM
provider = System.get_env("TEXT_GENERATION_PROVIDER") || "openai"

case provider do
  "openai" ->
    openai_api_key = System.fetch_env!("OPENAI_API_KEY")
    openai_model = System.fetch_env!("TEXT_GENERATION_MODEL")

    openai_max_tokens =
      System.get_env("TEXT_GENERATION_MAX_NEW_TOKENS", "400") |> String.to_integer()

    config :openai,
      api_key: openai_api_key,
      http_options: [recv_timeout: :infinity, async: :once]

    config :echo, Echo.TextGeneration, provider: Echo.TextGeneration.OpenAI

    config :echo, Echo.TextGeneration.OpenAI,
      model: openai_model,
      max_tokens: openai_max_tokens

  "generic" ->
    generic_api_url = System.fetch_env!("TEXT_GENERATION_API_URL")
    generic_model = System.fetch_env!("TEXT_GENERATION_MODEL")

    generic_max_tokens =
      System.get_env("TEXT_GENERATION_MAX_NEW_TOKENS", "400") |> String.to_integer()

    config :echo, Echo.TextGeneration, provider: Echo.TextGeneration.OpenAI

    config :openai,
      api_url: generic_api_url,
      http_options: [recv_timeout: :infinity, async: :once]

    config :echo, Echo.TextGeneration.OpenAI,
      model: generic_model,
      max_tokens: generic_max_tokens

  "bumblebee" ->
    bb_text_generation_model = System.fetch_env!("TEXT_GENERATION_MODEL")

    bb_max_new_tokens =
      System.get_env("TEXT_GENERATION_MAX_NEW_TOKENS", "400") |> String.to_integer()

    bb_max_sequence_length =
      System.get_env("TEXT_GENERATION_MAX_SEQUENCE_LENGTH", "2048") |> String.to_integer()

    config :echo, Echo.TextGeneration, provider: Echo.TextGeneration.Bumblebee

    config :echo, Echo.TextGeneration.Bumblebee,
      repo: bb_text_generation_model,
      max_new_tokens: bb_max_new_tokens,
      max_sequence_length: bb_max_sequence_length
end

# Speech-to-Text
stt_model_repo = System.fetch_env!("SPEECH_TO_TEXT_MODEL")

config :echo, Echo.SpeechToText, provider: Echo.SpeechToText.Bumblebee
config :echo, Echo.SpeechToText.Bumblebee, repo: stt_model_repo
# Text-to-Speech
eleven_labs_api_key = System.fetch_env!("ELEVEN_LABS_API_KEY")
eleven_labs_voice_id = System.get_env("ELEVEN_LABS_VOICE_ID", "21m00Tcm4TlvDq8ikWAM")
eleven_labs_model_id = System.get_env("ELEVEN_LABS_MODEL_ID", "eleven_turbo_v2")

eleven_labs_optimize_streaming_latency =
  System.get_env("ELEVEN_LABS_OPTIMIZE_STREAMING_LATENCY", "2") |> String.to_integer()

eleven_labs_output_format = System.get_env("ELEVEN_LABS_OUTPUT_FORMAT", "mp3_22050_32")

config :echo, Echo.Client.ElevenLabs.WebSocket,
  api_key: eleven_labs_api_key,
  voice_id: eleven_labs_voice_id,
  model_id: eleven_labs_model_id,
  optimize_streaming_latency: eleven_labs_optimize_streaming_latency,
  output_format: eleven_labs_output_format

# Regular Config

config :nx, default_backend: EXLA.Backend

if System.get_env("PHX_SERVER") do
  config :echo, EchoWeb.Endpoint, server: true
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  port = String.to_integer(System.get_env("PORT") || "4000")

  config :echo, EchoWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: port],
    server: true,
    code_reloader: false,
    check_origin: false,
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :echo, EchoWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your endpoint, ensuring
  # no data is ever sent via http, always redirecting to https:
  #
  #     config :echo, EchoWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
