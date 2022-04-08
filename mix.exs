defmodule RavixEcto.MixProject do
  use Mix.Project

  def project do
    [
      app: :ravix_ecto,
      version: "0.1.0",
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ecto, "~> 3.7"},
      {:ravix, github: "YgorCastor/ravix"},
      {:ok, "~> 2.3"},
      {:gradient, github: "esl/gradient", only: [:dev, :test], runtime: false},
      {:elixir_sense, github: "elixir-lsp/elixir_sense", only: [:dev]},
      {:ex_doc, "~> 0.28.3", only: :dev, runtime: false},
      {:dialyxir, "~> 1.1.0", only: [:dev, :test], runtime: false},
      {:ex_machina, "~> 2.7", only: :test},
      {:assertions, "~> 0.19.0", only: :test},
      {:excoveralls, "~> 0.14.4", only: :test},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:version_tasks, "~> 0.12.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
