defmodule Hedwig.Adapters.SlackSocket do
  alias HedwigSlackSocket.ChannelCache
  alias HedwigSlackSocket.WebSocketPool

  use Hedwig.Adapter

  defstruct channels: %{},
            req: nil,
            robot: nil,
            app_token: nil,
            bot_token: nil

  @slack_api "https://slack.com/api"

  @impl true
  def init({robot, opts}) do
    state = %__MODULE__{
      robot: robot,
      app_token: Keyword.get(opts, :app_token),
      bot_token: Keyword.get(opts, :bot_token)
    }

    {:ok, state, {:continue, :init_connectivity}}
  end

  @impl true
  def handle_continue(:init_connectivity, state) do
    req =
      Req.new(base_url: @slack_api)
      |> Req.Request.put_new_header("authorization", "Bearer " <> state.bot_token)
      |> Req.Request.put_new_header("content-type", "application/json")

    children = [
      {ChannelCache, [req: req]},
      {NimblePool,
       worker: {WebSocketPool, [caller_pid: self(), token: state.app_token]},
       pool_size: 3,
       name: WebSocketPool}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__.Supervisor)
    Kernel.send(self(), :connected)

    {:noreply, %{state | req: req}}
  end

  @impl true
  def handle_cast({:send, msg}, %{req: req} = state) do
    Req.post!(req, url: "/chat.postMessage", json: slack_message(msg))
    {:noreply, state}
  end

  @impl true
  def handle_cast({:reply, %{user: user, text: text} = msg}, %{req: req} = state) do
    Req.post!(req,
      url: "/chat.postMessage",
      json: slack_message(%{msg | text: "<@#{user.id}>: #{text}"})
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast({:join_channel, channel_id}, %{req: req} = state) do
    Req.post!(req, url: "/conversations.join", json: %{channel: channel_id})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:leave_channel, channel_id}, %{req: req} = state) do
    Req.post!(req, url: "/conversations.leave", json: %{channel: channel_id})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:emote, msg}, %{req: req} = state) do
    Req.post!(req, url: "/chat.meMessage", json: slack_message(msg))
    {:noreply, state}
  end

  # Ignore all bots -- including self
  @impl true
  def handle_call(%{"bot_id" => _bot_id} = _msg, _from, state) do
    {:reply, :ok, state}
  end

  # Handle Slack message events incoming from the websocket pool
  @impl true
  def handle_call(%{"type" => "message", "user" => user} = msg, _from, %{robot: robot} = state) do
    if msg["text"] do
      msg = %Hedwig.Message{
        ref: make_ref(),
        robot: robot,
        room: msg["channel"],
        text: msg["text"],
        type: "message",
        user: %Hedwig.User{
          id: user,
          name: nil
        }
      }

      :ok = Hedwig.Robot.handle_in(robot, msg)
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:connected, %{robot: robot} = state) do
    :ok = Hedwig.Robot.handle_connect(robot)
    {:noreply, state}
  end

  defp slack_message(%Hedwig.Message{} = msg, overrides \\ %{}) do
    Map.merge(%{channel: msg.room, text: msg.text}, overrides)
  end
end
