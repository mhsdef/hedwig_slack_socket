defmodule HedwigSlackSocket.ChannelCache do
  @moduledoc """
  Slack Channel Cache

  Slack does not offer granular ways to lookup
  channels IDs <-> channel strings. The API forces
  iteration over the entire list of channels in a
  Slack workspace.

  Sooo, we cache the list. Every six hours we iterate
  through at at the Tier 2 ratelimit threshold of
  20 req/min.

  See https://api.slack.com/methods/conversations.list
  """
  use GenServer
  require Logger

  @path "/conversations.list"
  @rate_limit_ms 3000
  @next_refresh 4 * 60 * 60 * 1000

  def start_link([{:req, req}]) do
    GenServer.start_link(__MODULE__, %{req: req, cursor: nil}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    :ets.new(:slack_channels, [:set, :protected, :named_table])
    send(self(), :fetch_channel_page)
    {:ok, state}
  end

  @impl true
  def handle_info(:fetch_channel_page, %{req: _req, cursor: ""} = state) do
    Logger.info("HedwigSlackSocket.ChannelCache: refresh completed")
    init_next_refresh(state)
  end

  @impl true
  def handle_info(:fetch_channel_page, %{req: req, cursor: nil} = state) do
    Logger.info("HedwigSlackSocket.ChannelCache: starting refresh")
    Req.get!(req, url: @path, params: %{limit: 200}).body |> handle_page(state)
  end

  @impl true
  def handle_info(:fetch_channel_page, %{req: req, cursor: cursor} = state) do
    Req.get!(req, url: @path, params: %{cursor: cursor, limit: 200}).body |> handle_page(state)
  end

  defp handle_page(
         %{
           "ok" => true,
           "channels" => channels,
           "response_metadata" => %{"next_cursor" => cursor}
         },
         state
       ) do
    save_channel_ids(channels)
    Process.send_after(self(), :fetch_channel_page, @rate_limit_ms)
    {:noreply, %{state | cursor: cursor}}
  end

  defp handle_page(%{"ok" => true, "channels" => channels}, state) do
    save_channel_ids(channels)
    init_next_refresh(state)
  end

  defp handle_page(_, state), do: init_next_refresh(state)

  defp save_channel_ids(channels) do
    names_to_ids = Enum.map(channels, fn c -> {c["name"], c["id"]} end)
    :ets.insert(:slack_channels, names_to_ids)
  end

  defp init_next_refresh(state) do
    Process.send_after(self(), :fetch_channel_page, @next_refresh)
    {:noreply, %{state | cursor: nil}, :hibernate}
  end
end
