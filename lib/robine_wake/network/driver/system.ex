defmodule RobineWake.Network.Driver.System do
  @moduledoc false
  @behaviour RobineWake.Network.Driver

  @impl true
  def status do
    case :inet.getifaddrs() do
      {:ok, interfaces} ->
        names = connected_interfaces(interfaces)
        addresses = ipv4_addresses(interfaces)

        if names == [],
          do: %{
            state: :degraded,
            reason: :network_unavailable,
            interfaces: [],
            ipv4_addresses: []
          },
          else: %{state: :available, interfaces: names, ipv4_addresses: addresses}

      {:error, reason} ->
        %{state: :degraded, reason: reason, interfaces: []}
    end
  end

  defp connected_interfaces(interfaces) do
    interfaces
    |> Enum.filter(fn {_name, properties} ->
      properties
      |> Keyword.get_values(:addr)
      |> Enum.any?(fn
        {127, _b, _c, _d} -> false
        {_a, _b, _c, _d} -> true
        _ipv6_or_other -> false
      end)
    end)
    |> Enum.map(fn {name, _properties} -> to_string(name) end)
    |> Enum.sort()
  end

  defp ipv4_addresses(interfaces) do
    interfaces
    |> Enum.flat_map(fn {_name, properties} -> Keyword.get_values(properties, :addr) end)
    |> Enum.filter(fn
      {127, _b, _c, _d} -> false
      {169, 254, _c, _d} -> false
      {_a, _b, _c, _d} -> true
      _ipv6_or_other -> false
    end)
    |> Enum.map(fn address -> address |> :inet.ntoa() |> to_string() end)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
