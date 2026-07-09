defmodule Daraja.HTTP.Retry do
  @moduledoc """
  Opt-in HTTP retry with exponential backoff and jitter.

  Disabled by default. Enable for idempotent operations such as OAuth token
  fetches:

      config :daraja, :http_retry,
        enabled: true,
        max_attempts: 3,
        base_ms: 100,
        max_ms: 2_000,
        jitter: true

  `Daraja.Auth.fetch_token/1` respects this config. Payment POST endpoints
  do **not** retry automatically — wrap your own calls with `run/2` when you
  have explicit idempotency guarantees.
  """

  @type config :: %{
          enabled: boolean(),
          max_attempts: pos_integer(),
          base_ms: pos_integer(),
          max_ms: pos_integer(),
          jitter: boolean()
        }

  @doc """
  Runs `fun/0`, retrying `{:error, reason}` results when retry is enabled and
  `reason` is retryable.

  Pass `enabled: true` in `opts` to force retries for a single call regardless
  of application config.
  """
  @spec run((-> term()), keyword()) :: term()
  def run(fun, opts \\ []) when is_function(fun, 0) do
    config = config(opts)

    if config.enabled do
      do_run(fun, config, 1)
    else
      fun.()
    end
  end

  @doc false
  @spec retryable?(term()) :: boolean()
  def retryable?({:error, :http_error, {:finch_pool_not_started, _}}), do: false
  def retryable?({:error, :http_error, _}), do: true
  def retryable?(_), do: false

  defp do_run(fun, config, attempt) do
    case fun.() do
      {:error, _, _} = error ->
        maybe_retry(fun, config, attempt, error)

      {:error, _} = error ->
        maybe_retry(fun, config, attempt, error)

      result ->
        result
    end
  end

  defp maybe_retry(fun, config, attempt, error) do
    if attempt < config.max_attempts and retryable?(error) do
      Process.sleep(backoff_ms(config, attempt))
      do_run(fun, config, attempt + 1)
    else
      error
    end
  end

  defp config(opts) do
    defaults = Application.get_env(:daraja, :http_retry, [])
    enabled = Keyword.get(opts, :enabled, Keyword.get(defaults, :enabled, false))

    %{
      enabled: enabled,
      max_attempts: Keyword.get(opts, :max_attempts, Keyword.get(defaults, :max_attempts, 3)),
      base_ms: Keyword.get(opts, :base_ms, Keyword.get(defaults, :base_ms, 100)),
      max_ms: Keyword.get(opts, :max_ms, Keyword.get(defaults, :max_ms, 2_000)),
      jitter: Keyword.get(opts, :jitter, Keyword.get(defaults, :jitter, true))
    }
  end

  defp backoff_ms(config, attempt) do
    exp = min(config.max_ms, config.base_ms * round(:math.pow(2, attempt - 1)))

    if config.jitter do
      exp + :rand.uniform(max(div(exp, 4), 1)) - 1
    else
      exp
    end
  end
end
