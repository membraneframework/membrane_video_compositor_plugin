defmodule Membrane.LiveCompositor.State do
  @moduledoc false

  require Membrane.Pad
  alias Membrane.LiveCompositor
  alias Membrane.LiveCompositor.Context

  @enforce_keys [:output_framerate, :output_sample_rate, :lc_port, :context, :composing_strategy]
  defstruct @enforce_keys ++
              [server_pid: nil, last_ssrc: 0, tcp_sink_eos: MapSet.new()]

  @type t :: %__MODULE__{
          context: Context.t(),
          output_framerate: Membrane.RawVideo.framerate_t(),
          output_sample_rate: LiveCompositor.output_sample_rate(),
          composing_strategy: :real_time_auto_init | :real_time | :offline_processing,
          lc_port: :inet.port_number(),
          server_pid: pid() | nil,
          tcp_sink_eos: MapSet.t()
        }

  @spec next_ssrc(t()) :: {t(), non_neg_integer()}
  def next_ssrc(state = %__MODULE__{last_ssrc: last_ssrc}) do
    {%__MODULE__{state | last_ssrc: last_ssrc + 1}, last_ssrc}
  end
end
