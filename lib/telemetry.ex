defmodule Hutch.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {Telemetry.Metrics.PublisherReporter, metrics: publisher_metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def publisher_metrics do
    [
      summary("publisher.call.total"),
      summary("publisher.success.total")
    ]
  end
end
