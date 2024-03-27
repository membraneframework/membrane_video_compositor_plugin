defmodule Membrane.LiveCompositor.Events do
  @moduledoc """
  Events sent to the parent process
  """

  alias Membrane.LiveCompositor.Context
  alias Membrane.Pad

  @typedoc """
  The output pad was connected and the TCP connection was established between pipeline and
  the LiveCompositor server.
  """
  @type output_registered_event_type :: :output_registered

  @typedoc """
  The input pad was connected and the TCP connection was established between pipeline and
  the LiveCompositor server.
  """
  @type input_registered_event_type :: :input_registered

  @typedoc """
  The compositor instance received the input, and the first frames/samples of that input are
  ready to be used.

  For example, if you want to ensure that some inputs are ready before you send the
  `:start_composing` message, you can wait for those events for specific inputs.
  Note that you need to set `composing_strategy:` to something other than `:real_time_auto_init`
  if you want to send `:start_composing` message yourself.
  """
  @type input_delivered_event_type :: :input_delivered

  @typedoc """
  The compositor instance received the input, and the first frames/samples of that input are used
  for rendering. This event can only be sent only if compositor was already started either via
  `composing_strategy: :real_time_auto_init` or with `:start_composing` message.

  This event is usually sent at the same time as `t:input_delivered_event_type/0` except for 2 cases:
  - First frames/samples of the input were delivered before composing was started.
  - If input has the `offset` field defined.
  """
  @type input_playing_event_type :: :input_playing

  @typedoc """
  Input finished processing and it is safe to unlink pads.
  """
  @type input_eos_event_type :: :input_eos

  @typedoc """
  Messages that LiveCompositor bin can send to the parent process.
  """
  @type event :: {
          output_registered_event_type()
          | input_registered_event_type()
          | input_delivered_event_type()
          | input_eos_event_type(),
          Pad.ref(),
          Context.t()
        }
end
