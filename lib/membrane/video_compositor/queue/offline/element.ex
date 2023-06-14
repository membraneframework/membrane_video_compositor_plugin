defmodule Membrane.VideoCompositor.Queue.Offline.Element do
  @moduledoc """
  This module is responsible for offline queueing strategy.

  In this strategy frames are sent to the compositor only when all added input pads queues,
  with timestamp offset lower or equal to composed buffer pts,
  have at least one frame.

  This element requires all input pads to have equal fps to work properly.
  A framerate converter should be used for every input pad to synchronize the framerate.
  """

  use Membrane.Filter

  alias Membrane.{Pad, RawVideo, Time}
  alias Membrane.VideoCompositor
  alias Membrane.VideoCompositor.{CompositorCoreFormat, Handler, Queue}
  alias Membrane.VideoCompositor.Queue.Offline.State, as: OfflineState
  alias Membrane.VideoCompositor.Queue.State
  alias Membrane.VideoCompositor.Queue.State.{HandlerState, PadState}

  def_options output_framerate: [
                spec: RawVideo.framerate_t()
              ],
              handler: [
                spec: Handler.t()
              ],
              metadata: [
                spec: VideoCompositor.init_metadata()
              ]

  def_input_pad :input,
    availability: :on_request,
    demand_mode: :auto,
    accepted_format: %RawVideo{pixel_format: :I420},
    options: [
      timestamp_offset: [
        spec: Time.non_neg_t(),
        description: "Input stream PTS offset in nanoseconds. Must be non-negative."
      ],
      vc_input_ref: [
        spec: Pad.ref_t(),
        description: "Reference to VC input pad."
      ],
      metadata: [
        spec: VideoCompositor.input_pad_metadata()
      ]
    ]

  def_output_pad :output,
    demand_mode: :auto,
    accepted_format: %CompositorCoreFormat{}

  @impl true
  def handle_init(
        _ctx,
        %{output_framerate: output_framerate, handler: handler, metadata: metadata}
      ) do
    {[],
     %State{
       output_framerate: output_framerate,
       custom_strategy_state: %OfflineState{},
       handler: HandlerState.new(handler, metadata)
     }}
  end

  @impl true
  def handle_pad_added(pad, context, state = %State{}) do
    vc_input_ref = Bunch.Struct.get_in(context, [:options, :vc_input_ref])

    state =
      state
      |> Bunch.Struct.put_in([:custom_strategy_state, :inputs_mapping, pad], vc_input_ref)
      |> State.register_pad(vc_input_ref, context.options)

    {[], state}
  end

  @impl true
  def handle_end_of_stream(
        pad,
        _ctx,
        state = %State{custom_strategy_state: %OfflineState{inputs_mapping: inputs_mapping}}
      ) do
    vc_input_ref = Map.fetch!(inputs_mapping, pad)

    state = State.put_event(state, {:end_of_stream, vc_input_ref})

    check_pads_queues({[], state})
  end

  @impl true
  def handle_stream_format(
        pad,
        stream_format,
        _context,
        state = %State{custom_strategy_state: %OfflineState{inputs_mapping: inputs_mapping}}
      ) do
    vc_input_ref = Map.fetch!(inputs_mapping, pad)

    state = State.put_event(state, {{:stream_format, stream_format}, vc_input_ref})

    {[], state}
  end

  @impl true
  def handle_process(
        pad,
        buffer,
        _context,
        state = %State{custom_strategy_state: %OfflineState{inputs_mapping: inputs_mapping}}
      ) do
    vc_input_ref = Map.fetch!(inputs_mapping, pad)

    state = State.register_buffer(state, buffer, vc_input_ref)

    check_pads_queues({[], state})
  end

  @impl true
  def handle_parent_notification(msg, _ctx, state) do
    state = State.put_event(state, {:message, msg})
    {[], state}
  end

  @spec frame_or_eos(list(PadState.pad_event())) :: :neither_frame_nor_eos | :frame | :eos
  defp frame_or_eos(events_queue) do
    Enum.reduce_while(
      events_queue,
      :neither_frame_nor_eos,
      fn event, _acc ->
        case PadState.event_type(event) do
          :frame -> {:halt, :frame}
          :end_of_stream -> {:halt, :eos}
          _other -> {:cont, :neither_frame_nor_eos}
        end
      end
    )
  end

  # Returns :all_pads_eos when
  # all pads queues have :eos event without any :frame event.
  # Returns :all_pads_ready when
  # 1. at least one pad queue has frame (to avoid sending empty buffer)
  # 2. all pads queues have:
  #   a. larger timestamp offset then next buffer pts or
  #   b. at least one waiting frame or
  #   c. eos event
  @spec queues_state(State.t()) :: :all_pads_eos | :all_pads_ready | :waiting
  defp queues_state(%State{
         pads_states: pads_states,
         next_buffer_pts: buffer_pts
       }) do
    pads_states
    |> Map.values()
    |> Enum.reduce_while(
      :all_pads_eos,
      fn %PadState{timestamp_offset: timestamp_offset, events_queue: events_queue},
         current_state ->
        case frame_or_eos(events_queue) do
          :frame ->
            {:cont, :all_pads_ready}

          :eos ->
            {:cont, current_state}

          :neither_frame_nor_eos
          when timestamp_offset > buffer_pts and current_state == :all_pads_eos ->
            {:cont, :waiting}

          :neither_frame_nor_eos
          when timestamp_offset > buffer_pts and current_state == :all_pads_ready ->
            {:cont, :all_pads_ready}

          :neither_frame_nor_eos ->
            {:halt, :waiting}
        end
      end
    )
  end

  @spec check_pads_queues({Queue.compositor_actions(), State.t()}) ::
          {Queue.compositor_actions(), State.t()}
  defp check_pads_queues({actions, state = %State{}}) do
    case queues_state(state) do
      :all_pads_ready ->
        pop_events(state)
        |> then(fn {new_actions, state} -> {actions ++ new_actions, state} end)
        # In some cases, multiple buffers might be composed,
        # e.g. when dropping pad after handling :end_of_stream event on blocking pad queue
        |> check_pads_queues()

      :all_pads_eos ->
        {actions ++ [end_of_stream: :output], state}

      :waiting ->
        {actions, state}
    end
  end

  @spec pop_events(State.t()) :: {Queue.compositor_actions(), State.t()}
  defp pop_events(
         initial_state = %State{
           pads_states: pads_states,
           next_buffer_pts: buffer_pts
         }
       ) do
    frame_indexes =
      pads_states
      |> Map.to_list()
      |> Enum.reject(fn {_pad, pad_state = %PadState{timestamp_offset: timestamp_offset}} ->
        timestamp_offset > buffer_pts or PadState.no_frame_eos?(pad_state)
      end)
      |> Enum.map(fn {pad, %PadState{events_queue: events_queue}} ->
        {pad, Enum.find_index(events_queue, &(PadState.event_type(&1) == :frame))}
      end)
      |> Enum.into(%{})

    {pads_frames, new_state} =
      initial_state
      |> State.pop_events(frame_indexes, false)

    actions = State.get_actions(new_state, initial_state, pads_frames, buffer_pts)

    {actions, new_state}
  end
end
