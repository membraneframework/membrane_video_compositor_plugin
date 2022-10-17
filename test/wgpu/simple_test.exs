defmodule VideoCompositor.Wgpu.Test do
  use ExUnit.Case, async: false

  alias Membrane.VideoCompositor.Common.{Position, RawVideo}
  alias Membrane.VideoCompositor.Test.Support.Utility
  alias Membrane.VideoCompositor.Wgpu.Native

  describe "wgpu native test on" do
    @describetag :tmp_dir
    @describetag :wgpu

    test "inits" do
      out_video = %RawVideo{width: 640, height: 720, pixel_format: :I420, framerate: {60, 1}}

      assert {:ok, _state} = Native.init(out_video)
    end

    test "compose doubled raw video frame on top of each other", %{tmp_dir: tmp_dir} do
      {in_path, out_path, ref_path} = Utility.prepare_paths("1frame.yuv", tmp_dir, "native")
      assert {:ok, frame} = File.read(in_path)

      in_video = %RawVideo{
        width: 640,
        height: 360,
        pixel_format: :I420,
        framerate: {60, 1}
      }

      assert {:ok, state} =
               Native.init(%RawVideo{
                 width: 640,
                 height: 720,
                 pixel_format: :I420,
                 framerate: {60, 1}
               })

      assert :ok =
               Native.add_video(state, 0, in_video, %Position{
                 x: 0,
                 y: 0,
                 z: 0.0,
                 scale_factor: 1.0
               })

      assert :ok =
               Native.add_video(state, 1, in_video, %Position{
                 x: 0,
                 y: 360,
                 z: 0.0,
                 scale_factor: 1.0
               })

      assert :ok = Native.upload_frame(state, 0, frame, 1)
      assert {:ok, {out_frame, 1}} = Native.upload_frame(state, 1, frame, 1)
      assert {:ok, file} = File.open(out_path, [:write])
      IO.binwrite(file, out_frame)
      File.close(file)

      reference_input_path = String.replace_suffix(in_path, "yuv", "h264")

      Utility.generate_ffmpeg_reference(
        reference_input_path,
        ref_path,
        "split[b], pad=iw:ih*2[src], [src][b]overlay=0:h"
      )

      Utility.compare_contents_with_error(out_path, ref_path)
    end

    test "z value affects composition", %{tmp_dir: tmp_dir} do
      {in_path, out_path, _ref_path} = Utility.prepare_paths("1frame.yuv", tmp_dir, "native")
      assert {:ok, frame} = File.read(in_path)

      caps = %RawVideo{
        width: 640,
        height: 360,
        pixel_format: :I420,
        framerate: {60, 1}
      }

      assert {:ok, state} = Native.init(caps)

      assert :ok =
               Native.add_video(state, 0, caps, %Position{
                 x: 0,
                 y: 0,
                 z: 0.5,
                 scale_factor: 1.0
               })

      assert :ok =
               Native.add_video(state, 1, caps, %Position{
                 x: 0,
                 y: 0,
                 z: 0.0,
                 scale_factor: 1.0
               })

      s = bit_size(frame)
      empty_frame = <<0::size(s)>>

      assert :ok = Native.upload_frame(state, 0, empty_frame, 1)
      assert {:ok, {out_frame, 1}} = Native.upload_frame(state, 1, frame, 1)

      assert {:ok, file} = File.open(out_path, [:write])
      IO.binwrite(file, out_frame)
      File.close(file)

      Utility.compare_contents_with_error(in_path, out_path)
    end
  end
end
