defmodule RobineWakeDevWeb do
  @moduledoc false

  def live_view do
    quote do
      use Phoenix.LiveView, layout: {RobineWakeDevWeb.Layouts, :app}
      import Phoenix.Component
      import RobineWakeDevWeb.Helpers
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Phoenix.LiveView.Router
    end
  end

  def html do
    quote do
      use Phoenix.Component
      import Phoenix.HTML
    end
  end

  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])
end

defmodule RobineWakeDevWeb.Helpers do
  @moduledoc false

  def status_class(value) when value in [:healthy, :available, :trusted], do: "good"
  def status_class(value) when value in [:unhealthy, :unavailable, :failing], do: "bad"
  def status_class(_value), do: "warn"

  def display(nil), do: "—"
  def display(value) when is_atom(value), do: Atom.to_string(value)
  def display(value), do: to_string(value)
end
