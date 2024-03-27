defmodule Membrane.LiveCompositor.StreamsHandler do
  @moduledoc false

  alias Membrane.LiveCompositor
  alias Membrane.LiveCompositor.{Request, State}

  @spec register_video_input_stream(String.t(), map(), State.t()) ::
          {:ok, :inet.port_number()} | {:error, any()}
  def register_video_input_stream(pad_id, input_pad_opts, state) do
    port =
      case input_pad_opts.port do
        {start, endd} -> "#{start}:#{endd}"
        exact_port -> exact_port
      end

    response =
      %{
        type: :register,
        entity_type: :rtp_input_stream,
        input_id: pad_id,
        transport_protocol: :tcp_server,
        port: port,
        video: %{
          codec: :h264
        },
        required: input_pad_opts.required,
        offset_ms:
          case input_pad_opts.offset do
            nil -> nil
            offset -> Membrane.Time.as_milliseconds(offset, :round)
          end
      }
      |> Request.send_request(state.lc_port)

    case response do
      {:ok, response} -> {:ok, response.body["port"]}
      {:error_response_code, err} -> {:error, err}
      {:error, err} -> {:error, err}
    end
  end

  @spec register_audio_input_stream(String.t(), map(), State.t()) ::
          {:ok, :inet.port_number()} | {:error, any()}
  def register_audio_input_stream(pad_id, input_pad_opts, state) do
    port =
      case input_pad_opts.port do
        {start, endd} -> "#{start}:#{endd}"
        exact_port -> exact_port
      end

    response =
      %{
        type: :register,
        entity_type: :rtp_input_stream,
        input_id: pad_id,
        transport_protocol: :tcp_server,
        port: port,
        audio: %{
          codec: :opus
        },
        required: input_pad_opts.required,
        offset_ms:
          case input_pad_opts.offset do
            nil -> nil
            offset -> Membrane.Time.as_milliseconds(offset, :round)
          end
      }
      |> Request.send_request(state.lc_port)

    case response do
      {:ok, response} -> {:ok, response.body["port"]}
      {:error_response_code, err} -> {:error, err}
      {:error, err} -> {:error, err}
    end
  end

  @spec register_video_output_stream(String.t(), map(), State.t()) ::
          {:ok, :inet.port_number()} | {:error, any()}
  def register_video_output_stream(pad_id, output_pad_opts, state) do
    requested_port =
      case output_pad_opts.port do
        {start, endd} -> "#{start}:#{endd}"
        exact_port -> exact_port
      end

    result =
      %{
        type: :register,
        entity_type: :output_stream,
        output_id: pad_id,
        transport_protocol: :tcp_server,
        port: requested_port,
        video: %{
          send_eos_when: map_eos_cond(output_pad_opts.send_eos_when),
          resolution: %{
            width: output_pad_opts.width,
            height: output_pad_opts.height
          },
          encoder_preset: output_pad_opts.encoder_preset,
          ffmpeg_options: output_pad_opts.ffmpeg_options,
          initial: output_pad_opts.initial
        }
      }
      |> Request.send_request(state.lc_port)

    case result do
      {:ok, response} -> {:ok, response.body["port"]}
      {:error_response_code, err} -> {:error, err}
      {:error, err} -> {:error, err}
    end
  end

  @spec register_audio_output_stream(String.t(), map(), State.t()) ::
          {:ok, :inet.port_number()} | {:error, any()}
  def register_audio_output_stream(pad_id, output_pad_opts, state) do
    requested_port =
      case output_pad_opts.port do
        {start, endd} -> "#{start}:#{endd}"
        exact_port -> exact_port
      end

    result =
      %{
        type: :register,
        entity_type: :output_stream,
        output_id: pad_id,
        transport_protocol: :tcp_server,
        port: requested_port,
        audio: %{
          send_eos_when: map_eos_cond(output_pad_opts.send_eos_when),
          channels: output_pad_opts.channels,
          encoder_preset: output_pad_opts.encoder_preset,
          initial: output_pad_opts.initial
        }
      }
      |> Request.send_request(state.lc_port)

    case result do
      {:ok, response} -> {:ok, response.body["port"]}
      {:error_response_code, err} -> {:error, err}
      {:error, err} -> {:error, err}
    end
  end

  @spec map_eos_cond(LiveCompositor.send_eos_condition()) :: any()
  defp map_eos_cond(cond) do
    case cond do
      nil -> nil
      :any_input -> %{any_input: true}
      :all_inputs -> %{all_inputs: true}
      {:any_of, input_ids} -> %{any_of: input_ids}
      {:all_of, input_ids} -> %{all_of: input_ids}
    end
  end
end
