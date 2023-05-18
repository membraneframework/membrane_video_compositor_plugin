defmodule Membrane.VideoCompositor.WgpuAdapter do
  @moduledoc false

  alias Membrane.VideoCompositor.CompositorCoreFormat
  alias Membrane.{Pad, RawVideo}
  alias Membrane.VideoCompositor.{RustStructs, Scene}
  alias Membrane.VideoCompositor.Wgpu.Native

  @type wgpu_state() :: any()
  @type error() :: any()
  @type frame() :: binary()
  @type pts() :: Membrane.Time.t()
  @type frame_with_pts :: {binary(), pts()}
  @type video_id() :: non_neg_integer()

  @spec init(RawVideo.t()) :: {:error, wgpu_state()} | {:ok, wgpu_state()}
  def init(output_stream_format) do
    {:ok, output_stream_format} =
      RustStructs.RawVideo.from_membrane_raw_video(output_stream_format)

    Native.init(output_stream_format)
  end

  @doc """
  Uploads a frame to the compositor.

  If all videos have provided input frames with a current enough pts, this will also render and return a composed frame.
  """
  @spec process_frame(wgpu_state(), video_id(), frame_with_pts()) ::
          :ok | {:ok, frame_with_pts()}
  def process_frame(state, video_id, {frame, pts}) do
    case Native.process_frame(state, video_id, frame, pts) do
      :ok ->
        :ok

      {:ok, frame} ->
        {:ok, frame}

      {:error, reason} ->
        raise "Error while uploading/composing frame, reason: #{inspect(reason)}"
    end
  end

  @spec set_scene(wgpu_state(), CompositorCoreFormat.t(), Scene.t(), %{Pad.ref_t() => video_id()}) ::
          :ok
  def set_scene(state, %CompositorCoreFormat{pads_formats: pads_formats}, scene, pads_to_ids) do
    rust_stream_format =
      Map.new(pads_formats, fn {pad, raw_video = %RawVideo{}} ->
        {Map.get(pads_to_ids, pad), RustStructs.RawVideo.from_membrane_raw_video(raw_video)}
      end)

    case Native.set_videos(state, rust_stream_format, scene) do
      :ok ->
        :ok

      {:error, reason} ->
        raise "Error while setting scene, reason: #{inspect(reason)}"
    end
  end
end
