defmodule Hutch.Publisher do
  def publish(struct, opts \\ []) when is_struct(struct) do
    with module <- struct.__struct__,
         {:ok, message} <- Jason.encode(struct) do
      publish(module.exchange(), module.routing_key(), message, opts)
    end
  end

  def publish(exchange, routing_key, message_or_payload, opts \\ [])

  def publish(exchange, routing_key, message, opts) when is_binary(message) do
    :poolboy.transaction(:publisher_pool, fn worker_pid ->
      GenServer.cast(worker_pid, {:publish, exchange, routing_key, message, opts})
    end)
  end

  def publish(exchange, routing_key, payload, opts) do
    with {:ok, message} <- Jason.encode(payload) do
      publish(exchange, routing_key, message, opts)
    end
  end
end
