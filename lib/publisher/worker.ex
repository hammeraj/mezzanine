defmodule Hutch.Publisher.Worker do
  use GenServer
  require Logger

  @startup_timeout_ms 30000
  @startup_max_retry 5

  defmodule State do
    defstruct [:connection, :rabbit_uri]
  end

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, timeout: @startup_timeout_ms)
  end

  def init(opts) do
    Keyword.fetch!(opts, :rabbit_uri)

    {:ok, struct(State, opts), {:continue, {:connect, 0}}}
  end

  def handle_continue({:connect, @startup_max_retry}, _state), do: {:stop, :failed_to_connect}

  def handle_continue({:connect, attempt}, state) do
    case AMQP.Connection.open(state.rabbit_uri) do
      {:ok, connection} ->
        {:noreply, %State{state | connection: connection}}

      {:error, _error} ->
        cooldown_interval = Integer.floor_div(@startup_timeout_ms, @startup_max_retry + 1)

        Logger.error(
          "Unable to connect to RabbitMQ Server, will retry in #{cooldown_interval} seconds"
        )

        :timer.sleep(cooldown_interval)

        {:continue, {:connect, attempt + 1}}
    end
  end

  def handle_info({_ref, {:ok_publish, routing_key}}, state) do
    Telemetry.Metrics.counter("publisher.success.total", tags: [routing_key])
    Logger.debug("Successful publish")

    {:noreply, state}
  end

  def handle_info({_ref, {:error_publish, routing_key, error}}, state) do
    Telemetry.Metrics.counter("publisher.failure.total", tags: [routing_key])
    Logger.debug("Unsuccessful publish due to #{inspect(error)}")

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state) do
    {:noreply, state}
  end

  def handle_cast({:publish, exchange, routing_key, payload, opts}, state) do
    Telemetry.Metrics.counter("publisher.call.total", tags: [routing_key])

    Task.Supervisor.async_nolink(WorkerSupervisor, fn ->
      publish(state, exchange, routing_key, payload, opts)
    end)

    {:noreply, state}
  end

  defp publish(state, exchange, routing_key, payload, opts) do
    state.connection
    |> with_channel(fn channel ->
      AMQP.Basic.publish(channel, exchange, routing_key, payload, opts)
    end)
    |> case do
      :ok ->
        {:ok_publish, routing_key}

      error ->
        {:error_publish, routing_key, error}
    end
  end

  defp with_channel(conn, callback) do
    case AMQP.Channel.open(conn) do
      {:ok, channel} ->
        callback.(channel)

        AMQP.Channel.close(channel)

      error ->
        error
    end
  end
end
