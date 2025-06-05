defmodule ConfluenceLoader.MixProject do
  use Mix.Project

  def project do
    [
      app: :confluence_loader,
      version: "0.1.1",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      test_coverage: [summary: [threshold: 85]],
      name: "confluence_loader",
      source_url: "https://github.com/cloudwalk/confluence-loader"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5.0"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:mox, "~> 1.0", only: :test},
      {:bypass, "~> 2.1", only: :test}
    ]
  end

  defp description do
    """
    An Elixir library for fetching and reading Confluence pages using the REST API v2.
    """
  end

  defp package do
    [
      name: "confluence_loader",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/cloudwalk/confluence-loader"
      }
    ]
  end

  defp docs do
    [
      main: "ConfluenceLoader",
      extras: ["README.md"]
    ]
  end
end
