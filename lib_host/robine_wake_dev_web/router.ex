defmodule RobineWakeDevWeb.Router do
  use RobineWakeDevWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RobineWakeDevWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", RobineWakeDevWeb do
    pipe_through :browser
    live "/", EmulatorLive, :index
    get "/room", RoomRedirect, []
  end
end
