defmodule Nerdalert do
  use GenServer
  alias Nerves.Neopixel

  @channel 0
  @default_intensity 80
  @lower_intensity 5
  @api_url "https://gitlab.uptime.dk/api/v4/projects/60/pipelines"

  def start_link() do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(_) do
    state = %{
      old_status: :failure,
      colors: [],
      intensity: @default_intensity,
      dimming: false
    }
    ch0_config = [pin: 18, count: 200]
    {:ok, _pid} = Neopixel.start_link(ch0_config)
    send(self(), :render)
    {:ok, state}
  end

  def handle_info(:render, state) do
    new_status = gitlab_pipeline_status()
    state = display(new_status, state)
    
    Neopixel.render(@channel, {state.intensity, state.colors})
    Process.send_after(self(), :render, 50)

    {:noreply, state}
  end

  def dimming(current_intensity, current_dimming) do
    cond do
      current_intensity >= @default_intensity -> true
      current_intensity <= @lower_intensity -> false
      true -> current_dimming
    end
  end 

  def display(:running, %{old_status: :running} = state) do
    colors = 
      state.colors
      |> Stream.cycle()
      |> Stream.drop(1)
      |> Enum.take(100)
    %{state | colors: colors}
  end

  def display(:pending, %{old_status: :pending} = state) do
    dimming = dimming(state.intensity, state.dimming)
    new_intensity = if dimming do
      state.intensity - 2
    else
      state.intensity + 2
    end
    %{state | intensity: new_intensity, dimming: dimming}
  end

  def display(new_status, state) do
    base_colors = [{0, 255, 0}, {255, 0, 0}, {0, 255, 255}]

    colors = case new_status do
      :success -> for _number <- 1..100, do: {0, 255, 0}
      :failure -> for _number <- 1..100, do: {255, 0, 0}
      :pending -> for _number <- 1..100, do: {0, 255, 255}
      :running -> 
        base_colors
        |> Stream.cycle()
        |> Stream.drop(1)
        |> Enum.take(100)
      _ -> for _number <- 1..100, do: {50, 0, 0}
    end
    %{state | old_status: new_status, colors: colors}
  end

  def gitlab_pipeline_status() do
    headers = ["PRIVATE-TOKEN": Application.config(:nerdalert, :gitlab_token)]

    case HTTPoison.get(@api_url, headers, hackney: [:insecure]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> 
        body
        |> Poison.decode!()
        |> List.first()
        |> Map.get("status")
        |> case do
          "success" -> :success
          "pending" -> :pending
          "running" -> :running
          _ -> :failure
        end 
      {:ok, %HTTPoison.Response{}} -> :http_status_error
      {:error, %HTTPoison.Error{reason: _reason}} -> :error
    end
  end
end
