defmodule Membrane.VideoCompositor.OfflineQueueTest do
  @moduledoc false
  use ExUnit.Case

  alias Membrane.VideoCompositor
  alias Membrane.VideoCompositor.Support.Handler
  alias Membrane.{Buffer, Pad, RawVideo, Time}
  alias Membrane.Element.Action
  alias Membrane.VideoCompositor.{CompositorCoreFormat, Scene, SceneChangeEvent}
  alias Membrane.VideoCompositor.Queue.Strategy.Offline.Element, as: OfflineQueue
  alias Membrane.VideoCompositor.Queue.Strategy.State
  alias Membrane.VideoCompositor.{BaseVideoPlacement, VideoConfig}

  @frame <<0::3_110_400>>

  @video_config %VideoConfig{
    placement: %BaseVideoPlacement{
      position: {0, 0},
      size: {1.0, 1.0}
    }
  }

  @video_stream_format %RawVideo{
    width: 1920,
    height: 1080,
    framerate: {1, 1},
    pixel_format: :I420,
    aligned: true
  }

  @pad1 {Pad, :input, 1}
  @pad2 {Pad, :input, 2}

  @pad2_pts_offset Time.seconds(1) + 1

  test "if queue doesn't send actions on init and handle pad added" do
    setup_videos()
  end

  test "if updates stream format and scene on send buffer" do
    state = setup_videos()

    actions = pad1_actions()
    {^actions, _state} = OfflineQueue.handle_process(@pad1, send_buffer(0), %{}, state)
  end

  test "if removed pad doesn't block queue and if stream format, scene and buffer actions are send." do
    state = setup_videos()
    assert {[], state} = OfflineQueue.handle_process(@pad2, send_buffer(0), {}, state)

    assert {[], state} =
             OfflineQueue.handle_process(@pad2, send_buffer(Time.seconds(1)), {}, state)

    assert {_pad1_buffer1_actions, state} =
             OfflineQueue.handle_process(@pad1, send_buffer(0), %{}, state)

    pad1_buffer2_action = [get_buffer_action(@pad1, Time.seconds(1))]

    assert {^pad1_buffer2_action, state} =
             OfflineQueue.handle_process(@pad1, send_buffer(Time.seconds(1)), %{}, state)

    second_pad_actions = unlocked_pad2_actions()
    assert {^second_pad_actions, _state} = OfflineQueue.handle_end_of_stream(@pad1, %{}, state)
  end

  test "if compositor is sending EOS once all pads are removed" do
    state = setup_videos()
    assert {[], state} = OfflineQueue.handle_end_of_stream(@pad1, %{}, state)

    eos_action = [end_of_stream: :output]

    assert {^eos_action, _state} = OfflineQueue.handle_end_of_stream(@pad2, %{}, state)
  end

  defp send_buffer(pts) do
    %Buffer{
      pts: pts,
      dts: pts,
      payload: @frame
    }
  end

  defp setup_videos() do
    pad1_options = %{metadata: @video_config, timestamp_offset: 0, vc_input_ref: @pad1}

    pad2_options = %{
      metadata: @video_config,
      timestamp_offset: @pad2_pts_offset,
      vc_input_ref: @pad2
    }

    assert {[], state} =
             OfflineQueue.handle_init(%{}, %{
               vc_init_options: %VideoCompositor{
                 output_stream_format: @video_stream_format,
                 queuing_strategy: Membrane.VideoCompositor.QueueingStrategy.Offline,
                 handler: Handler,
                 metadata: nil
               }
             })

    assert {[], state} =
             OfflineQueue.handle_pad_added(
               @pad1,
               %{options: pad1_options},
               state
             )

    assert {[], state} =
             OfflineQueue.handle_stream_format(@pad1, @video_stream_format, %{}, state)

    assert {[], state} =
             OfflineQueue.handle_pad_added(
               @pad2,
               %{options: pad2_options},
               state
             )

    assert {[], state} =
             OfflineQueue.handle_stream_format(@pad2, @video_stream_format, %{}, state)

    state
  end

  @spec pad1_actions() :: [
          Action.stream_format() | [State.notify_compositor_scene() | Action.buffer()]
        ]
  defp pad1_actions() do
    stream_format = %CompositorCoreFormat{pad_formats: %{@pad1 => @video_stream_format}}
    stream_format_action = {:stream_format, {:output, stream_format}}

    scene = %Scene{video_configs: %{@pad1 => @video_config}}
    scene_action = {:event, {:output, %SceneChangeEvent{new_scene: scene}}}

    buffer_action = get_buffer_action(@pad1, 0)

    [stream_format_action, scene_action, buffer_action]
  end

  defp unlocked_pad2_actions() do
    stream_format_action =
      {:stream_format,
       {:output, %CompositorCoreFormat{pad_formats: %{@pad2 => @video_stream_format}}}}

    scene = %Scene{video_configs: %{@pad2 => @video_config}}
    scene_action = {:event, {:output, %SceneChangeEvent{new_scene: scene}}}

    buffer_actions = [
      get_buffer_action(@pad2, Time.seconds(2)),
      get_buffer_action(@pad2, Time.seconds(3))
    ]

    [stream_format_action, scene_action] ++ buffer_actions
  end

  defp get_buffer_action(pad, pts) do
    {:buffer, {:output, %Buffer{pts: pts, dts: pts, payload: %{pad => @frame}}}}
  end
end