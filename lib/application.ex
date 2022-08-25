defmodule Hutch.Application do
  def start(_type, _args) do
    rabbit_uri = Application.get_env(:hutch, :rabbit_uri)
    children = [
      :poolboy.child_spec(:publisher_pool, processor_poolboy_config(), rabbit_uri: rabbit_uri)
    ]

    Supervisor.start_link(children, [strategy: :one_for_one, name: Hutch.Supervisor])
  end

  def processor_poolboy_config() do
    opts = Application.get_env(:hutch, :publisher_opts, [])
    Keyword.merge([
      name: {:local, :publisher_pool},
      worker_module: Hutch.Publisher.Worker,
      size: 10, # Initial number of workers
      max_overflow: 4 # Extra workers (auto-stopped after work) to spawn if under load
    ], opts)
  end
end
