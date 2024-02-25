defmodule EchoWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :echo

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_echo_key",
    signing_salt: "ygE5htLL",
    same_site: "Lax"
  ]

  socket "/conversation", EchoWeb.Socket.Conversation,
    websocket: [
      path: "/conversation",
      serializer: EchoWeb.Socket.Serializer
    ],
    longpoll: false

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug EchoWeb.Router
end
