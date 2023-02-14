defmodule Membrane.VideoCompositor.CompositorElement do
  @moduledoc false
  # The element responsible for composing frames.

  # It is capable of operating in one of two modes:

  #  * offline compositing:
  #    The compositor will wait for all videos to have a recent enough frame available and then perform the compositing.

  use Membrane.Filter

  alias Membrane.Buffer
  alias Membrane.RawVideo
  alias Membrane.VideoCompositor.RustStructs.BaseVideoPlacement
  alias Membrane.VideoCompositor.VideoTransformations
  alias Membrane.VideoCompositor.WgpuAdapter

  def_options stream_format: [
                spec: RawVideo.t(),
                description: "Struct with video width, height, framerate and pixel format."
              ]

  def_input_pad :input,
    availability: :on_request,
    demand_mode: :auto,
    accepted_format: %RawVideo{pixel_format: :I420},
    options: [
      initial_placement: [
        spec: BaseVideoPlacement.t(),
        description: "Initial placement of the video on the screen"
      ],
      timestamp_offset: [
        spec: Membrane.Time.non_neg_t(),
        description: "Input stream PTS offset in nanoseconds. Must be non-negative.",
        default: 0
      ],
      initial_video_transformations: [
        spec: VideoTransformations.t(),
        description:
          "Specify the initial types and the order of transformations applied to video.",
        # Membrane Core uses macro with a quote on def_input_pad, which breaks structured data like structs.
        # To avoid that, we would need to use Macro.escape(%VideoTransformations{texture_transformations: []})
        # here and handle its mapping letter, which is a significantly harder and less readable than handling nil
        # as a default value, that's why we use nil here.
        default: nil
      ]
    ]

  def_output_pad :output,
    demand_mode: :auto,
    accepted_format: %RawVideo{pixel_format: :I420}

  @impl true
  def handle_init(_ctx, options) do
    {:ok, wgpu_state} = WgpuAdapter.init(options.stream_format)

    state = %{
      initial_video_placements: %{},
      initial_video_transformations: %{},
      timestamp_offsets: %{},
      stream_format: options.stream_format,
      wgpu_state: wgpu_state,
      pads_to_ids: %{},
      new_pad_id: 0
    }

    {[], state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[stream_format: {:output, state.stream_format}], state}
  end

  @impl true
  def handle_pad_added(pad, context, state) do
    timestamp_offset =
      case context.options.timestamp_offset do
        timestamp_offset when timestamp_offset < 0 ->
          raise ArgumentError,
            message:
              "Invalid timestamp_offset option for pad: #{Pad.name_by_ref(pad)}. timestamp_offset can't be negative."

        timestamp_offset ->
          timestamp_offset
      end

    initial_placement = context.options.initial_placement

    initial_transformations =
      case context.options.initial_video_transformations do
        nil ->
          VideoTransformations.empty()

        _other ->
          context.options.initial_video_transformations
      end

    state = register_pad(state, pad, initial_placement, initial_transformations, timestamp_offset)
    {[], state}
  end

  defp register_pad(state, pad, placement, transformations, timestamp_offset) do
    new_id = state.new_pad_id

    %{
      state
      | initial_video_placements: Map.put(state.initial_video_placements, new_id, placement),
        initial_video_transformations:
          Map.put(state.initial_video_transformations, new_id, transformations),
        timestamp_offsets: Map.put(state.timestamp_offsets, new_id, timestamp_offset),
        pads_to_ids: Map.put(state.pads_to_ids, pad, new_id),
        new_pad_id: new_id + 1
    }
  end

  @impl true
  def handle_stream_format(pad, stream_format, _context, state) do
    %{
      pads_to_ids: pads_to_ids,
      wgpu_state: wgpu_state,
      initial_video_placements: initial_video_placements,
      initial_video_transformations: initial_video_transformations
    } = state

    id = Map.get(pads_to_ids, pad)

    {initial_video_placements, initial_video_transformations} =
      case {Map.pop(initial_video_placements, id), Map.pop(initial_video_transformations, id)} do
        {{nil, initial_video_placements}, {nil, initial_video_transformations}} ->
          # this video was added before
          :ok = WgpuAdapter.update_stream_format(wgpu_state, id, stream_format)
          {initial_video_placements, initial_video_transformations}

        {{placement, initial_video_placements}, {transformations, initial_video_transformations}} ->
          # this video was waiting for first stream_format to be added to the compositor
          :ok = WgpuAdapter.add_video(wgpu_state, id, stream_format, placement, transformations)
          {initial_video_placements, initial_video_transformations}
      end

    {
      [],
      %{
        state
        | initial_video_placements: initial_video_placements,
          initial_video_transformations: initial_video_transformations
      }
    }
  end

  @impl true
  def handle_process(pad, buffer, _context, state) do
    %{
      pads_to_ids: pads_to_ids,
      wgpu_state: wgpu_state,
      timestamp_offsets: timestamp_offsets
    } = state

    id = Map.get(pads_to_ids, pad)

    %Membrane.Buffer{payload: frame, pts: pts} = buffer
    pts = pts + Map.get(timestamp_offsets, id)

    case WgpuAdapter.upload_frame(wgpu_state, id, {frame, pts}) do
      {:ok, {frame, pts}} ->
        {[buffer: {:output, %Membrane.Buffer{payload: frame, pts: pts}}], state}

      :ok ->
        {[], state}
    end
  end

  @impl true
  def handle_end_of_stream(
        pad,
        context,
        state
      ) do
    %{pads_to_ids: pads_to_ids, wgpu_state: wgpu_state} = state
    id = Map.get(pads_to_ids, pad)

    {:ok, frames} = WgpuAdapter.send_end_of_stream(wgpu_state, id)

    buffers = frames |> Enum.map(fn {frame, pts} -> %Buffer{payload: frame, pts: pts} end)

    buffers = [buffer: {:output, [buffers]}]

    end_of_stream =
      if all_input_pads_received_end_of_stream?(context.pads) do
        [end_of_stream: :output]
      else
        []
      end

    actions = buffers ++ end_of_stream

    {actions, state}
  end

  defp all_input_pads_received_end_of_stream?(pads) do
    Map.to_list(pads)
    |> Enum.all?(fn {ref, pad} -> ref == :output or pad.end_of_stream? end)
  end

  @impl true
  def handle_pad_removed(pad, ctx, state) do
    {pad_id, pads_to_ids} = Map.pop!(state.pads_to_ids, pad)
    state = %{state | pads_to_ids: pads_to_ids}

    if is_pad_waiting_for_caps?(pad, state) do
      # this is the case of removing a video that did not receive caps yet
      # since it did not receive caps, it wasn't added to the internal compositor state yet
      {[],
       %{
         state
         | initial_video_transformations: Map.delete(state.initial_video_transformations, pad_id),
           initial_video_placements: Map.delete(state.initial_video_placements, pad_id)
       }}
    else
      if Map.get(ctx.pads, pad).end_of_stream? do
        # videos that already received end of stream don't require special treatment
        {[], state}
      else
        # this is the case of removing a video that did receive caps, but did not receive
        # end of stream. all videos that were added to the compositor need to receive
        # end of stream, so we need to send one here.
        {:ok, frames} = WgpuAdapter.send_end_of_stream(state.wgpu_state, pad_id)
        buffers = frames |> Enum.map(fn {frame, pts} -> %Buffer{payload: frame, pts: pts} end)

        {[buffer: buffers], state}
      end
    end
  end

  defp is_pad_waiting_for_caps?(pad, state) do
    pad_id = Map.get(state.pads_to_ids, pad)

    Map.has_key?(state.initial_video_transformations, pad_id)
  end

  @impl true
  def handle_parent_notification({:update_placement, placements}, _ctx, state) do
    %{
      pads_to_ids: pads_to_ids,
      wgpu_state: wgpu_state,
      initial_video_placements: initial_video_placements
    } = state

    initial_video_placements =
      update_placements(placements, pads_to_ids, wgpu_state, initial_video_placements)

    {[], %{state | initial_video_placements: initial_video_placements}}
  end

  @impl true
  def handle_parent_notification({:update_transformations, all_transformations}, _ctx, state) do
    %{
      pads_to_ids: pads_to_ids,
      wgpu_state: wgpu_state,
      initial_video_transformations: initial_video_transformations
    } = state

    initial_video_transformations =
      update_transformations(
        all_transformations,
        pads_to_ids,
        wgpu_state,
        initial_video_transformations
      )

    {[], %{state | initial_video_transformations: initial_video_transformations}}
  end

  defp update_placements(
         [],
         _pads_to_ids,
         _wgpu_state,
         initial_video_placements
       ) do
    initial_video_placements
  end

  defp update_placements(
         [{pad, placement} | other_placements],
         pads_to_ids,
         wgpu_state,
         initial_video_placements
       ) do
    id = Map.get(pads_to_ids, pad)

    initial_video_placements =
      case WgpuAdapter.update_placement(wgpu_state, id, placement) do
        :ok -> initial_video_placements
        # in case of update_placements is called before handle_stream_format and add_video in rust
        # wasn't called yet (the video wasn't registered in rust yet)
        {:error, :bad_video_index} -> Map.put(initial_video_placements, id, placement)
      end

    update_placements(other_placements, pads_to_ids, wgpu_state, initial_video_placements)
  end

  defp update_transformations(
         [],
         _pads_to_ids,
         _wgpu_state,
         initial_video_transformations
       ) do
    initial_video_transformations
  end

  defp update_transformations(
         [{pad, video_transformations} | other_transformations],
         pads_to_ids,
         wgpu_state,
         initial_video_transformations
       ) do
    id = Map.get(pads_to_ids, pad)

    initial_video_transformations =
      case WgpuAdapter.update_transformations(wgpu_state, id, video_transformations) do
        :ok ->
          initial_video_transformations

        # in case of update_transformations is called before handle_stream_format and add_video in rust
        # wasn't called yet (the video wasn't registered in rust yet)
        {:error, :bad_video_index} ->
          Map.put(initial_video_transformations, id, video_transformations)
      end

    update_transformations(
      other_transformations,
      pads_to_ids,
      wgpu_state,
      initial_video_transformations
    )
  end
end
