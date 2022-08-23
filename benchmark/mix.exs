defmodule Membrane.VideoCompositor.Benchmark.Mixfile do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :membrane_video_compositor_benchmark,
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
    ]
  end

  def application do
    [
      extra_applications: []
    ]
  end

  defp deps do
    [
      {:membrane_video_compositor_plugin, path: ".."},
      {:benchee, "~> 1.1.0"},
      {:benchee_html, "~> 1.0"},
      {:beamchmark, "~> 1.4.0"},
      {:credo, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end