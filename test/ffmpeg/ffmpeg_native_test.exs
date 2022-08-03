defmodule VideoCompositor.FFmpeg.Native.Test do
  use ExUnit.Case, async: true

  alias Membrane.RawVideo
  alias Membrane.VideoCompositor.FFmpeg.Native
  alias Membrane.VideoCompositor.Test.Utility

  @tag :tmp_dir
  test "compose doubled raw video frame on top of each other", %{tmp_dir: tmp_dir} do
    {in_path, out_path, ref_path} = Utility.prepare_paths("1frame.yuv", "ref-native.yuv", tmp_dir)
    assert {:ok, frame_a} = File.read(in_path)
    assert {:ok, frame_b} = File.read(in_path)

    videos = [
      %RawVideo{
        width: 640,
        height: 360,
        pixel_format: :I420,
        framerate: nil,
        aligned: nil
      },
      %RawVideo{
        width: 640,
        height: 360,
        pixel_format: :I420,
        framerate: nil,
        aligned: nil
      }
    ]

    assert {:ok, ref} = Native.init(videos)
    frames = [frame_a, frame_b]
    assert {:ok, out_frame} = Native.apply_filter(frames, ref)
    assert {:ok, file} = File.open(out_path, [:write])
    on_exit(fn -> File.close(file) end)

    IO.binwrite(file, out_frame)
    reference_input_path = "../fixtures/1frame.h264" |> Path.expand(__DIR__)

    Utility.create_ffmpeg_reference(
      reference_input_path,
      ref_path,
      "split[b], pad=iw:ih*2[src], [src][b]overlay=0:h"
    )

    Utility.compare_contents(out_path, ref_path)
  end
end
