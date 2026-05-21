defmodule Daraja.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [Daraja.Auth.Cache]
    Supervisor.start_link(children, strategy: :one_for_one, name: Daraja.Supervisor)
  end
end
