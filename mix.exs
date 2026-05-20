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
      deps: deps(),
      dialyzer: dialyzer(),
      description: description(),
      package: package(),
      docs: docs(),
      aliases: aliases(),
      preferred_cli_env: [docs: :docs]
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
      {:finch, "~> 0.22.0", optional: true}
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: []
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
      extras: ["README.md", "CHANGELOG.md", "LICENSE"]
    ]
  end

  defp aliases do
    [
      lint: [
        "compile --warnings-as-errors --force",
        "format --check-formatted",
        "deps.unlock --unused"
      ]
    ]
  end
end
