defmodule Midifile.Mixfile do
  use Mix.Project

  def project do
    [
      app: :midifile,
      version: "1.0.0",
      elixir: "~> 1.18",
      deps: deps(),
      description: "Library for working with MIDI files in Elixir",
      package: package()
    ]
  end

  # Configuration for the OTP application
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/bwanab/elixir-midifile"}
    ]
  end

  defp deps do
    [
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end
end
