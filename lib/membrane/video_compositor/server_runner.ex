defmodule Membrane.LiveCompositor.ServerRunner do
  @moduledoc false

  require Membrane.Logger

  alias Membrane.LiveCompositor
  alias Membrane.LiveCompositor.Request

  @spec ensure_server_started(LiveCompositor.t()) ::
          {:ok, :inet.port_number(), pid()} | {:error, err :: String.t()}
  def ensure_server_started(opt) do
    {framerate_num, framerate_den} = opt.framerate
    framerate_str = "#{framerate_num}/#{framerate_den}"
    instance_id = "live_compositor_#{:rand.uniform(1_000_000_000)}"

    env = %{
      "LIVE_COMPOSITOR_INSTANCE_ID" => instance_id,
      "LIVE_COMPOSITOR_OFFLINE_PROCESSING_ENABLE" =>
        to_string(opt.composing_strategy == :offline_processing),
      "LIVE_COMPOSITOR_OUTPUT_FRAMERATE" => framerate_str,
      "LIVE_COMPOSITOR_STREAM_FALLBACK_TIMEOUT_MS" =>
        to_string(Membrane.Time.as_milliseconds(opt.stream_fallback_timeout, :round))
    }

    case opt.server_setup do
      :start_locally ->
        path = Mix.Tasks.Compile.DownloadCompositor.lc_app_path()
        {:ok, lc_port, server_pid} = start_server(path, opt.api_port, env, instance_id)
        {:ok, lc_port, server_pid}

      {:start_locally, path} ->
        {:ok, lc_port, server_pid} = start_server(path, opt.api_port, env, instance_id)
        {:ok, lc_port, server_pid}

      :already_started ->
        case opt.api_port do
          {_start, _end} ->
            raise "Exact api_port is required when server_setup is set to :already_started"

          exact ->
            {:ok, exact, nil}
        end
    end
  end

  @spec start_server(
          String.t(),
          :inet.port_number() | LiveCompositor.port_range(),
          map(),
          String.t()
        ) ::
          {:ok, :inet.port_number(), pid()} | {:error, err :: String.t()}
  defp start_server(bin_path, port_or_port_range, env, instance_id) do
    {port_lower_bound, port_upper_bound} =
      case port_or_port_range do
        {start, endd} -> {start, endd}
        exact -> {exact, exact}
      end

    port_lower_bound..port_upper_bound
    |> Enum.shuffle()
    |> Enum.reduce_while(
      {:error, "Failed to start a LiveCompositor server on any of the ports."},
      fn port, err -> try_starting_on_port(port, err, env, bin_path, instance_id) end
    )
  end

  @spec try_starting_on_port(:inet.port_number(), String.t(), map(), String.t(), String.t()) ::
          {:halt, {:ok, :inet.port_number()}} | {:cont, err :: String.t()}
  defp try_starting_on_port(port, err, env, bin_path, instance_id) do
    Membrane.Logger.debug("Trying to launch LiveCompositor on port: #{port}")

    case start_on_port(port, env, bin_path, instance_id) do
      {:ok, pid} -> {:halt, {:ok, port, pid}}
      :error -> {:cont, err}
    end
  end

  @spec start_on_port(:inet.port_number(), map(), String.t(), String.t()) :: {:ok, pid()} | :error
  defp start_on_port(lc_port, env, bin_path, instance_id) do
    unless File.exists?(bin_path) do
      raise "Live Compositor binary is not available under search path: \"#{bin_path}\"."
    end

    pid =
      spawn(fn ->
        bin_path
        |> MuonTrap.cmd([],
          into: IO.stream(),
          env:
            Map.merge(
              %{
                "LIVE_COMPOSITOR_API_PORT" => "#{lc_port}",
                "LIVE_COMPOSITOR_WEB_RENDERER_ENABLE" => "false"
              },
              env
            )
        )
      end)

    case wait_for_lc_startup(lc_port, pid, instance_id) do
      :started ->
        {:ok, pid}

      :not_started ->
        Process.exit(pid, :kill)
        :error
    end
  end

  @spec wait_for_lc_startup(:inet.port_number(), pid(), String.t()) :: :started | :not_started
  defp wait_for_lc_startup(lc_port, pid, instance_id) do
    0..300
    |> Enum.reduce_while(:not_started, fn _i, _acc ->
      Process.sleep(100)

      with {:is_alive, true} <- {:is_alive, Process.alive?(pid)},
           {:ok, response} <- Request.get_status(lc_port) do
        if response.body["instance_id"] == instance_id do
          {:halt, :started}
        else
          {:halt, :not_started}
        end
      else
        {:is_alive, false} ->
          {:halt, :not_started}

        {:error, _reason} ->
          {:cont, :not_started}
      end
    end)
  end
end
