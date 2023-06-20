defmodule Membrane.VideoCompositor.Pipeline.Utils.Options do
  @moduledoc """
  Options for the testing pipeline.
  """

  @typedoc """
  Specifications of the input video sources
  """
  @type inputs :: [InputStream.t()]

  @typedoc """
  Specifications of the sink element or path to the output video file
  """
  @type output :: String.t() | Membrane.Sink

  @typedoc """
  Specification of the output video, parameters of the final \"canvas\"
  """
  @type output_stream_format :: RawVideo.t()

  @typedoc """
  Multiple Frames Compositor
  """
  @type compositor :: Membrane.Filter.t()

  @typedoc """
  Decoder for the input buffers. Frames are passed by if `nil` given.
  """
  @type decoder :: Membrane.Filter.t() | nil

  @typedoc """
  Encoder for the output buffers. Frames are passed by if `nil` given.
  """
  @type encoder :: Membrane.Filter.t() | nil

  @typedoc """
  An additional plugin that sits between the decoder (or source if there is no decoder) and the compositor.
  """
  @type input_filter :: Membrane.Filter.t() | nil

  @type t() :: %__MODULE__{
          inputs: inputs(),
          output: output(),
          output_stream_format: output_stream_format(),
          compositor: compositor(),
          decoder: decoder(),
          encoder: encoder(),
          input_filter: input_filter()
        }
  @enforce_keys [:inputs, :output, :output_stream_format]
  defstruct [:inputs, :output, :output_stream_format, :compositor, :decoder, :encoder, :input_filter]
end
