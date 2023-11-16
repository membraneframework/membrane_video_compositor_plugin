defmodule Membrane.VideoCompositor.Examples.DynamicOutputs.Pipeline do
  @moduledoc false

  use Membrane.Pipeline

  require Membrane.Logger

  alias Membrane.VideoCompositor
  alias Membrane.VideoCompositor.{Context, OutputOptions}

  @output_width 1920
  @output_height 1080
  @layout_id "layout"

  @impl true
  def handle_init(_ctx, %{sample_path: sample_path}) do
    spec =
      child(:video_compositor, %Membrane.VideoCompositor{
        framerate: 30
      })

    input_specs = 0..10 |> Enum.map(fn input_number -> input_spec(input_number, sample_path) end)

    0..5
    |> Enum.map(fn output_number ->
      five_seconds = 5_000

      Process.send_after(
        self(),
        {:register_output, output_id(output_number)},
        output_number * five_seconds
      )
    end)

    {[spec: spec, spec: input_specs], %{sample_path: sample_path, inputs: [], outputs: []}}
  end

  @impl true
  def handle_child_notification(
        {register, _id, vc_ctx},
        :video_compositor,
        _ctx,
        state
      )
      when register == :input_registered or register == :output_registered do
    {inputs, outputs} = inputs_outputs_ids(vc_ctx)
    {update_scene_action(inputs, outputs), %{state | inputs: inputs, outputs: outputs}}
  end

  @impl true
  def handle_child_notification(
        {:new_output_stream, output_id, _vc_ctx},
        :video_compositor,
        _membrane_ctx,
        state
      ) do
    Process.send_after(self(), {:remove_output, output_id}, 10_000)
    {[spec: output_spec(output_id)], state}
  end

  @impl true
  def handle_child_notification(
        {:vc_request_response, req, %Req.Response{status: response_code, body: response_body},
         _vc_ctx},
        :video_compositor,
        _membrane_ctx,
        state
      ) do
    if response_code != 200 do
      raise """
      Request failed.
      Request: `#{inspect(req)}.
      Response code: #{response_code}.
      Response body: #{inspect(response_body)}.
      """
    end

    {[], state}
  end

  @impl true
  def handle_child_notification(notification, child, _ctx, state) do
    Membrane.Logger.info(
      "Received notification: #{inspect(notification)} from child: #{inspect(child)}."
    )

    {[], state}
  end

  @impl true
  def handle_info({:register_output, output_id}, _ctx, state) do
    output_opt = %OutputOptions{
      width: @output_width,
      height: @output_height,
      id: output_id
    }

    {[notify_child: {:video_compositor, {:register_output, output_opt}}], state}
  end

  @impl true
  def handle_info(
        {:remove_output, output_id},
        _ctx,
        state = %{inputs: inputs, outputs: outputs}
      ) do
    outputs = outputs |> Enum.reject(fn id -> id == output_id end)

    children = [
      {:output_parser, output_id},
      {:output_decoder, output_id},
      {:sdl_player, output_id}
    ]

    # Change the scene before removing the output.
    # VideoCompositor forbids removing output used in the current scene.
    {update_scene_action(inputs, outputs) ++ [remove_children: children],
     %{state | outputs: outputs}}
  end

  @spec update_scene_action(list(VideoCompositor.input_id()), list(VideoCompositor.output_id())) ::
          [Membrane.Pipeline.Action.notify_child()]
  defp update_scene_action(input_ids, output_ids) do
    update_scene_request =
      if length(output_ids) > 0 and length(input_ids) > 0 do
        outputs =
          output_ids
          |> Enum.map(fn output_id -> %{output_id: output_id, input_pad: @layout_id} end)

        %{
          type: :update_scene,
          nodes: [tiled_layout(input_ids)],
          outputs: outputs
        }
      else
        %{
          type: :update_scene,
          nodes: [],
          outputs: []
        }
      end

    [notify_child: {:video_compositor, {:vc_request, update_scene_request}}]
  end

  @spec tiled_layout(list(String.t())) :: map()
  defp tiled_layout(input_pads) do
    %{
      type: "built-in",
      transformation: :tiled_layout,
      node_id: "layout",
      margin: 10,
      resolution: %{
        width: 1920,
        height: 1080
      },
      input_pads: input_pads
    }
  end

  defp input_spec(input_number, sample_path) do
    child({:video_src, input_number}, %Membrane.File.Source{location: sample_path})
    |> child({:input_parser, input_number}, %Membrane.H264.Parser{
      output_alignment: :nalu,
      generate_best_effort_timestamps: %{framerate: {30, 1}}
    })
    |> child({:realtimer, input_number}, Membrane.Realtimer)
    |> via_in(Pad.ref(:input, input_number), options: [input_id: "input_#{input_number}"])
    |> get_child(:video_compositor)
  end

  defp output_spec(output_id) do
    get_child(:video_compositor)
    |> via_out(Membrane.Pad.ref(:output, output_id),
      options: [
        output_id: output_id
      ]
    )
    |> child({:output_parser, output_id}, Membrane.H264.Parser)
    |> child({:output_decoder, output_id}, Membrane.H264.FFmpeg.Decoder)
    |> child({:sdl_player, output_id}, Membrane.SDL.Player)
  end

  defp inputs_outputs_ids(%Context{inputs: inputs, outputs: outputs}) do
    input_ids = inputs |> Enum.map(fn %Context.InputStream{id: input_id} -> input_id end)
    output_ids = outputs |> Enum.map(fn %Context.OutputStream{id: output_id} -> output_id end)

    {input_ids, output_ids}
  end

  defp output_id(output_number) do
    "output_#{output_number}"
  end
end
