defmodule Membrane.VideoCompositor.Mixfile do
  use Mix.Project

  @version "0.7.1"
  @github_url "https://github.com/membraneframework/membrane_video_compositor_plugin"

  def project do
    [
      app: :membrane_video_compositor_plugin,
      version: @version,
      elixir: "~> 1.13",
      compilers: Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      compilers: Mix.compilers(),
      # hex
      description: "Video Compositor Plugin for Membrane Multimedia Framework",
      package: package(),

      # docs
      name: "Membrane Video Compositor plugin",
      source_url: @github_url,
      homepage_url: "https://membraneframework.org",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: []
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:unifex, "~> 1.0"},
      {:membrane_core, "~> 1.0"},
      {:membrane_framerate_converter_plugin, "~> 0.8.0"},
      {:membrane_raw_video_format, "~> 0.3.0"},
      {:qex, "~> 0.5.1"},
      {:rustler, "~> 0.26.0"},
      {:ratio, "~> 3.0"},
      # Testing
      {:membrane_file_plugin, "~> 0.16.0", only: :test},
      {:membrane_h264_plugin, "~> 0.9.0", only: :test},
      {:membrane_h264_ffmpeg_plugin, "~> 0.31.1", only: :test},
      {:membrane_raw_video_parser_plugin, "~> 0.12.0", only: :test},

      # Development
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp dialyzer() do
    opts = [
      flags: [:error_handling],
      plt_add_apps: [:ex_unit]
    ]

    if System.get_env("CI") == "true" do
      # Store PLTs in cacheable directory for CI
      [plt_local_path: "priv/plts", plt_core_path: "priv/plts"] ++ opts
    else
      opts
    end
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @github_url,
        "Membrane Framework Homepage" => "https://membraneframework.org"
      },
      files:
        ["lib", "mix.exs", "README*", "LICENSE*", ".formatter.exs"] ++
          Enum.map(
            ["src", ".cargo/config", "Cargo.toml", "Cargo.lock"],
            &"native/membrane_videocompositor/#{&1}"
          )
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      formatters: ["html"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [
        Membrane.VideoCompositor,
        Membrane.VideoCompositor.Transformations,
        Membrane.VideoCompositor.QueueingStrategy
      ],
      groups_for_modules: [
        Transformations: [
          ~r/^Membrane\.VideoCompositor\.Transformations($|\.)/
        ],
        Handler: [
          ~r/^Membrane\.VideoCompositor\.Handler($|\.)/
        ],
        QueueingStrategy: [
          ~r/^Membrane\.VideoCompositor\.QueueingStrategy($|\.)/
        ]
      ]
    ]
  end
end
