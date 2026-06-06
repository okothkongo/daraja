defmodule Daraja.HTTP.RetryTest do
  use ExUnit.Case, async: true

  alias Daraja.HTTP.Retry

  setup do
    on_exit(fn -> Application.delete_env(:daraja, :http_retry) end)
    :ok
  end

  test "returns immediately when retry is disabled" do
    calls = :counters.new(1, [])

    result =
      Retry.run(fn ->
        :counters.add(calls, 1, 1)
        {:error, :http_error, :timeout}
      end)

    assert result == {:error, :http_error, :timeout}
    assert :counters.get(calls, 1) == 1
  end

  test "retries transport errors when enabled" do
    Application.put_env(:daraja, :http_retry,
      enabled: true,
      max_attempts: 3,
      base_ms: 1,
      max_ms: 5,
      jitter: false
    )

    calls = :counters.new(1, [])

    result =
      Retry.run(fn ->
        case :counters.get(calls, 1) do
          0 ->
            :counters.add(calls, 1, 1)
            {:error, :http_error, :timeout}

          _ ->
            :counters.add(calls, 1, 1)
            {:ok, :recovered}
        end
      end)

    assert result == {:ok, :recovered}
    assert :counters.get(calls, 1) == 2
  end

  test "does not retry finch pool not started errors" do
    Application.put_env(:daraja, :http_retry, enabled: true, max_attempts: 3, base_ms: 1)

    calls = :counters.new(1, [])

    result =
      Retry.run(fn ->
        :counters.add(calls, 1, 1)
        {:error, :http_error, {:finch_pool_not_started, Daraja.Finch}}
      end)

    assert result == {:error, :http_error, {:finch_pool_not_started, Daraja.Finch}}
    assert :counters.get(calls, 1) == 1
  end
end
