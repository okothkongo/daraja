defmodule Daraja.MixProject do
  use Mix.Project
  @version "0.1.0"
  @daraja_link "https://developer.safaricom.co.ke"
  @source_url "https://github.com/okothkongo/daraja"
  def project do
    [
      app: :daraja,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      dialyzer: dialyzer(),
      description: description(),
      package: package(),
      docs: docs(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test,
        docs: :docs
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    []
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.2", only: :dev},
      {:finch, "~> 0.23", optional: true},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp dialyzer do
    [
      plt_add_apps: [:json]
    ]
  end

  defp description do
    "Safaricom Daraja API library
    #{@daraja_link}
    "
  end

  defp package() do
    [
      maintainers: ["Okoth Kongo"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "daraja",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/daraja",
      source_url: @source_url,
      extras: ["README.md", "LICENSE", "CHANGELOG.md"]
    ]
  end

  defp aliases do
    [
      lint: [
        "compile --warnings-as-errors --force",
        "format --check-formatted",
        "deps.unlock --unused",
        "credo  --strict"
      ]
    ]
  end
end
