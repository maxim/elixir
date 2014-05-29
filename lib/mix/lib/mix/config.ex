defmodule Mix.Config do
  @moduledoc ~S"""
  Module for defining, reading and merging app configurations.

  Most commonly, this module is used to define your own configuration:

      import Mix.Config

      config :plug,
        key1: "value1",
        key2: "value2"

      import_config "#{Mix.env}.exs"

  All `config/*` macros, including `import_config/1`, are used
  to help define such configuration files.

  Furthermore, this module provides functions like `read!/1`,
  `merge/2` and friends which help manipulate configurations
  in general.
  """

  defmodule LoadError do
    defexception [:file, :error]

    def message(%LoadError{file: file, error: error}) do
      "could not load config #{Path.relative_to_cwd(file)}\n    " <>
        "#{Exception.format_banner(:error, error)}"
    end
  end

  @doc """
  Configures the given application.

  ## Examples

  The given `opts` are merged into the existing configuration
  for the given `app`. Conflicting keys are overridden by the
  ones specified in `opts`. For example, the declaration below:

      config :lager,
        log_level: :warn,
        mode: :truncate

      config :lager,
        log_level: :info,
        threshold: 1024

  Will have a final configuration of:

      [log_level: :info, mode: :truncate, threshold: 1024]

  """
  defmacro config(app, opts) do
    quote do
      var!(config, Mix.Config) =
        Mix.Config.merge(unquote(get_config(__CALLER__)), [{unquote(app), unquote(opts)}])
    end
  end

  @doc """
  Configures the given key for the given application.

  ## Examples

  The given `opts` are merged into the existing values for `key`
  in the given `app`. Conflicting keys are overridden by the
  ones specified in `opts`. For example, the declaration below:

      config :ecto, Repo,
        log_level: :warn

      config :ecto, Repo,
        log_level: :info,
        pool_size: 10

  Will have a final value for `Repo` of:

      [log_level: :info, pool_size: 10]

  """
  defmacro config(app, key, opts) do
    quote do
      var!(config, Mix.Config) =
        Mix.Config.merge(unquote(get_config(__CALLER__)),
                         [{unquote(app), [{unquote(key), unquote(opts)}]}],
                         fn _app, _key, v1, v2 -> Keyword.merge(v1, v2) end)
    end
  end

  @doc ~S"""
  Imports configuration from the given file.

  The path is expected to be related to the directory the
  current configuration file is on.

  ## Examples

  This is often used to emulate configuration across environments:

      import_config "#{Mix.env}.exs"

  Or to import files from children in umbrella projects:

      import_config "../apps/child/config/config.exs"

  """
  defmacro import_config(file) do
    quote do
      var!(config, Mix.Config) =
        Mix.Config.merge(unquote(get_config(__CALLER__)),
                         Mix.Config.read!(Path.expand(unquote(file), __DIR__)))
    end
  end

  defp get_config(%Macro.Env{vars: vars}) do
    if {:config, Mix.Config} in vars do
      quote do: var!(config, Mix.Config)
    else
      []
    end
  end

  @doc """
  Reads and validates a configuration file.
  """
  def read!(file) do
    try do
      {config, binding} = Code.eval_file(file)
      config =
        case List.keyfind(binding, {:config, Mix.Config}, 0) do
          {_, value} -> value
          nil -> config
        end
      validate!(config)
      config
    rescue
      e in [LoadError] -> reraise(e, System.stacktrace)
      e -> raise LoadError, file: file, error: e
    end
  end

  @doc """
  Persists the given configuration by modifying
  the configured applications environment.
  """
  def persist(config) do
    for {app, kw} <- config, {k, v} <- kw do
      :application.set_env(app, k, v, persistent: true)
    end
    :ok
  end

  @doc """
  Validates a configuration.
  """
  def validate!(config) do
    if is_list(config) do
      Enum.all?(config, fn
        {app, value} when is_atom(app) ->
          if Keyword.keyword?(value) do
            true
          else
            raise ArgumentError,
              "expected config for app #{inspect app} to return keyword list, got: #{inspect value}"
          end
        _ ->
          false
      end)
    else
      raise ArgumentError,
        "expected config file to return keyword list, got: #{inspect config}"
    end
  end

  @doc """
  Merges two configurations.

  The configuration of each application is merged together
  with the values in the second one having higher preference
  than the first in case of conflicts.

  ## Examples

      iex> Mix.Config.merge([app: [k: :v1]], [app: [k: :v2]])
      [app: [k: :v2]]

      iex> Mix.Config.merge([app1: []], [app2: []])
      [app1: [], app2: []]

  """
  def merge(config1, config2) do
    Keyword.merge(config1, config2, fn _, app1, app2 ->
      Keyword.merge(app1, app2)
    end)
  end

  @doc """
  Merges two configurations.

  The configuration of each application is merged together
  and a callback is invoked in case of conflicts receiving
  the app, the conflicting key and both values. It must return
  a value that will be used as part of the conflict resolution.

  ## Examples

      iex> Mix.Config.merge([app: [k: :v1]], [app: [k: :v2]],
      ...>   fn app, k, v1, v2 -> {app, k, v1, v2} end)
      [app: [k: {:app, :k, :v1, :v2}]]

  """
  def merge(config1, config2, callback) do
    Keyword.merge(config1, config2, fn app, app1, app2 ->
      Keyword.merge(app1, app2, fn k, v1, v2 ->
        if v1 == v2 do
          v1
        else
          callback.(app, k, v1, v2)
        end
      end)
    end)
  end
end
