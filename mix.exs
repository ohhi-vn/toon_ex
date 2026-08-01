defmodule ToonEx.MixProject do
  use Mix.Project

  @version "1.2.0"
  @source_url "https://github.com/ohhi-vn/toon_ex"

  def project do
    [
      app: :toon_ex,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        plt_core_path: "priv/plts",
        plt_local_path: "priv/plts",
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        flags: [
          :error_handling,
          :underspecs,
          :unmatched_returns,
          :unknown
        ],
        ignore_warnings: ".dialyzer_ignore.exs"
      ],
      aliases: aliases()
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/fixtures"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # Core dependencies
      {:nimble_parsec, "~> 1.4"},

      # Development dependencies
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:benchee, "~> 1.5", only: :dev, runtime: false},

      # Test dependencies
      {:excoveralls, "~> 0.18", only: :test},

      # Code quality
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    TOON encoder/decoder for Elixir, TOON <--> JSON converter, supported for Phoenix Channels.
    """
  end

  defp package do
    [
      name: "toon_ex",
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      maintainers: ["Manh Vu"]
    ]
  end

  defp docs do
    [
      main: "ToonEx",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "LICENSE"],
      groups_for_modules: [
        Encoding: [
          ToonEx.Encode,
          ToonEx.Encode.Primitives,
          ToonEx.Encode.Objects,
          ToonEx.Encode.Arrays,
          ToonEx.Encode.Strings,
          ToonEx.Encode.Writer,
          ToonEx.Encode.Options,
          ToonEx.Encoder
        ],
        Decoding: [
          ToonEx.Decode,
          ToonEx.Decode.Fast.Decoder,
          ToonEx.Decode.Options
        ],
        Convertors: [
          ToonEx.JSON
        ],
        ImplHelpers: [
          ToonEx.ToonImplHelper
        ],
        Phoenix: [
          ToonEx.Phoenix.Serializer
        ],
        "Shared Types": [
          ToonEx.Types,
          ToonEx.Constants,
          ToonEx.Utils
        ],
        Errors: [
          ToonEx.EncodeError,
          ToonEx.DecodeError
        ]
      ]
    ]
  end

  defp aliases do
    [
      "quality.ci": [
        "format --check-formatted",
        "credo --strict",
        "dialyzer"
      ],
      precommit: ["compile --warning-as-errors", "deps.unlock --unused", "format", "test"],
      # Testing & Coverage
      coveralls: ["test --cover", "coveralls.html"],
      # Code Quality
      quality: ["format --check-formatted", "credo --strict", "dialyzer"]
    ]
  end
end
