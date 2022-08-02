defmodule Membrane.VideoCompositor.OpenGL do
  @moduledoc """
  This module implements video composition in OpenGL.
  """

  @behaviour Membrane.VideoCompositor.FrameCompositor

  @impl Membrane.VideoCompositor.FrameCompositor
  def init(_caps) do
    {:ok, %{}}
  end

  @impl Membrane.VideoCompositor.FrameCompositor
  def merge_frames(frames, internal_state) do
    merged_frames_binary = frames.first <> frames.second
    {:ok, merged_frames_binary, internal_state}
  end
end