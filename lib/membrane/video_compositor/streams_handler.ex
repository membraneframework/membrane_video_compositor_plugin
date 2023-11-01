defmodule Membrane.VideoCompositor.StreamsHandler do
  @moduledoc false

  alias Membrane.VideoCompositor
  alias Membrane.VideoCompositor.{OutputOptions, Request, State}

  @spec register_input_stream(VideoCompositor.input_id(), State.t()) ::
          {:ok, :inet.port_number()} | :error
  def register_input_stream(input_id, state) do
    try_register = fn input_port ->
      Request.register_input_stream(input_id, input_port, state.vc_port)
    end

    register_input_or_output(try_register, state)
  end

  @spec register_output_stream(OutputOptions.t(), Membrane.VideoCompositor.State.t()) ::
          {:ok, :inet.port_number()} | :error
  def register_output_stream(output_opt, state) do
    try_register = fn output_port ->
      Request.register_output_stream(
        output_opt,
        output_port,
        state.vc_port
      )
    end

    register_input_or_output(try_register, state)
  end

  @spec register_input_or_output((:inet.port_number() -> Request.request_result()), State.t()) ::
          {:ok, :inet.port_number()} | :error
  defp register_input_or_output(try_register, state) do
    {port_lower_bound, port_upper_bound} = state.port_range
    used_ports = state |> State.used_ports() |> MapSet.new()

    port_lower_bound..port_upper_bound
    |> Enum.shuffle()
    |> Enum.reduce_while(:error, fn port, _acc -> try_port(try_register, port, used_ports) end)
  end

  @spec try_port(
          (:inet.port_number() -> Request.request_result()),
          :inet.port_number(),
          MapSet.t()
        ) ::
          {:halt, {:ok, :inet.port_number()}} | {:cont, :error}
  defp try_port(try_register, port, used_ports) do
    # FFmpeg reserves additional ports (two ports for each RTP stream).
    if [port - 1, port, port] |> Enum.any?(fn port -> MapSet.member?(used_ports, port) end) do
      {:cont, :error}
    else
      case try_register.(port) do
        {:ok, _resp} ->
          {:halt, {:ok, port}}

        {:error_response_code, _resp} ->
          {:cont, :error}

        _other ->
          raise "Register input failed"
      end
    end
  end
end
