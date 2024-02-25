import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :echo, EchoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "MTR+T29AbArhJeW33OZ+9l9OZ9UmZpSHDO3NqVE00TE+CbrBgBITy7A+0tw4X5kl",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
