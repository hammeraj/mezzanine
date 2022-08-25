defmodule Hutch.Publishable do
  @callback exchange() :: String.t()
  @callback routing_key() :: String.t()
end
