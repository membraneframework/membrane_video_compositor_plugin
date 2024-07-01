# Membrane Video Compositor Plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_video_compositor_plugin.svg)](https://hex.pm/packages/membrane_video_compositor_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_video_compositor_plugin)
[![CircleCI](https://dl.circleci.com/status-badge/img/gh/membraneframework/membrane_video_compositor_plugin/tree/master.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/membraneframework/membrane_video_compositor_plugin/tree/master)

Membrane plugin that accepts multiple video inputs, transforms them according to provided transformations and composes them into a single output video.

It is part of [Membrane Multimedia Framework](https://membraneframework.org).

## Installation

The package can be installed by adding `membrane_video_compositor_plugin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_video_compositor_plugin, "~> 0.7.1"}
  ]
end
```

Since parts of this package are implemented in Rust, you need to have a Rust installation to compile this package. You can get one [here](https://rustup.rs/)

## Usage

Before jumping into Livebook, check out this [installation guide](https://github.com/membraneframework/guide/tree/master/livebook_examples).
Note that it's running on the previous version of this plugin.

[![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fgithub.com%2Fmembraneframework%2Fguide%2Fblob%2Fmaster%2Flivebook_examples%2Fvideo_compositor%2Fvideo_compositor.livemd)

## Copyright and License

Copyright 2022, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_video_compositor_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_video_compositor_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
