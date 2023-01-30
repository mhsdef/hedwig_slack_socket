defmodule HedwigSlackSocket.MixProject do
  use Mix.Project

  def project do
    [
      app: :hedwig_slack_socket,
      name: "Hedwig Slack Socket",
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:hedwig, "~> 1.0"},
      {:mint, "~> 1.4"},
      {:mint_web_socket, "~> 1.0"},
      {:req, "~> 0.3.4"},
      {:nimble_pool, "~> 0.2.6"},

      # Dev and test
      {:dialyxir, "~> 1.2.0", only: :dev, runtime: false},
      {:ex_doc, "~> 0.29.0", only: :dev, runtime: false}
    ]
  end
end
