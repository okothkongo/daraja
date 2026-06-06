defmodule Daraja.Test.TokenCacheHelper do
  @moduledoc false

  import ExUnit.Callbacks, only: [start_supervised!: 1]

  @spec start!(keyword()) :: pid()
  def start!(opts \\ []) do
    name = Keyword.get(opts, :name, Daraja.TokenCache)
    task_sup = Keyword.get(opts, :task_supervisor, task_supervisor_name(name))

    unless Process.whereis(task_sup) do
      start_supervised!({Task.Supervisor, name: task_sup})
    end

    start_supervised!(
      {Daraja.TokenCache, Keyword.merge(opts, name: name, task_supervisor: task_sup)}
    )
  end

  defp task_supervisor_name(name), do: :"#{name}_tasks"
end
