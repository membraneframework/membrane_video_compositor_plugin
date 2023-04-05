defmodule Membrane.VideoCompositor.Scene.Transformation do
  @moduledoc """
  Module representing single-input, single-output frames processing graph nodes
  that apply a single effect on the input frame (e.g. crop them or round corners).

  Transformations can change frame resolution. Cropping, CornersRounding, ColorFiler,
  RollToBall, etc. can be implemented as transformations.
  """

  @typedoc """
  Specify how Transformations can be defined:
    - By struct - when transformation can be parametrized with different values
    e.g. corners round (parametrized with border-radius), cropping, etc.
    - By module - when there are no reasonable / common use cases of parametrization,
    and identifying transformation without it is enough e.g. RollToBall - transformation
    turning input object / frame / video into the ball
  """
  @type definition :: struct() | module()
  @type name :: tuple() | atom()
end