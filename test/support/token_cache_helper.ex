defmodule Daraja.Test.TokenCacheHelper do
  @moduledoc false

  defmacro start!(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      require ExUnit.Callbacks

      name = Keyword.get(opts, :name, Daraja.TokenCache)
      task_sup = Keyword.get(opts, :task_supervisor, :"#{name}_tasks")

      unless Process.whereis(task_sup) do
        ExUnit.Callbacks.start_supervised!({Task.Supervisor, name: task_sup})
      end

      ExUnit.Callbacks.start_supervised!(
        {Daraja.TokenCache, Keyword.merge(opts, name: name, task_supervisor: task_sup)}
      )
    end
  end
end
