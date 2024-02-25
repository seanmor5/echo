defmodule EchoWeb.Router do
  use EchoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", EchoWeb do
    pipe_through :browser
  end
end
