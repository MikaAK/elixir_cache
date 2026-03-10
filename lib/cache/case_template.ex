defmodule Cache.CaseTemplate do
  @moduledoc """
  A reusable ExUnit case template for applications using `elixir_cache`.

  Creates a `CacheCase` module that automatically starts sandboxed caches in
  `setup` for every test that uses it.

  ## Creating a CacheCase module

  Pass an explicit list of cache modules:

  ```elixir
  defmodule MyApp.CacheCase do
    use Cache.CaseTemplate, default_caches: [MyApp.UserCache, MyApp.SessionCache]
  end
  ```

  Or discover caches at runtime by inspecting a running supervisor:

  ```elixir
  defmodule MyApp.CacheCase do
    use Cache.CacheTemplate, supervisors: [MyApp.Supervisor]
  end
  ```

  ## Using the CacheCase in a test file

  ```elixir
  defmodule MyApp.SomeTest do
    use ExUnit.Case, async: true
    use MyApp.CacheCase

    # or with additional caches just for this file:
    use MyApp.CacheCase, caches: [MyApp.ExtraCache]
  end
  ```

  ## Options for `use Cache.CaseTemplate`

  - `:default_caches` — list of cache modules to start for every test
  - `:supervisors` — list of supervisor atoms; their `Cache` children are discovered at runtime

  ## Options for `use MyApp.CacheCase`

  - `:caches` — additional cache modules for this test file only
  - `:sleep` — milliseconds to sleep after starting caches (default: `10`)
  """

  defmacro __using__(template_opts) do
    default_caches = Keyword.get(template_opts, :default_caches, [])
    supervisors = Keyword.get(template_opts, :supervisors, [])

    if Keyword.has_key?(template_opts, :caches) do
      raise ":caches is not valid here, use :default_caches instead"
    end

    quote bind_quoted: [default_caches: default_caches, supervisors: supervisors] do
      defmacro __using__(case_opts) do
        sleep_time = Keyword.get(case_opts, :sleep, 10)
        case_caches = Keyword.get(case_opts, :caches, [])
        template_default_caches = unquote(default_caches)
        template_supervisors = unquote(supervisors)

        quote do
          setup do
            inferred = Cache.CaseTemplate.inferred_caches(unquote(template_supervisors))

            (unquote(template_default_caches) ++ inferred ++ unquote(case_caches))
            |> Cache.CaseTemplate.validate_uniq!()
            |> Cache.SandboxRegistry.start()

            Process.sleep(unquote(sleep_time))
          end
        end
      end
    end
  end

  @doc """
  Inspects a running supervisor's children to find cache modules started under a
  `Cache` supervisor child.

  Raises if the given supervisor is not running or has no `Cache` child.
  """
  @spec inferred_caches([atom] | atom) :: [module]
  def inferred_caches([]), do: []

  def inferred_caches(supervisors) when is_list(supervisors) do
    Enum.flat_map(supervisors, &inferred_caches/1)
  end

  def inferred_caches(supervisor) when is_atom(supervisor) do
    case Process.whereis(supervisor) do
      nil ->
        raise """
        Supervisor #{inspect(supervisor)} is not started.

        It is either misspelled or not started as part of your application's supervision tree.
        Verify that the supervisor exists and that the app starting it is a dependency of
        the current app.
        """

      sup_pid ->
        case find_cache_supervisor(sup_pid) do
          nil ->
            raise """
            Supervisor #{inspect(supervisor)} has no Cache child supervisor.

            Add a Cache supervisor under #{inspect(supervisor)} in your Application, for example:

              children = [
                {Cache, [MyApp.UserCache, MyApp.SessionCache]}
              ]
            """

          cache_pid ->
            cache_pid
            |> Supervisor.which_children()
            |> Enum.filter(fn {_id, _pid, _type, modules} ->
              is_list(modules) and
                Enum.any?(modules, &function_exported?(&1, :cache_name, 0))
            end)
            |> Enum.flat_map(fn {_id, _pid, _type, modules} ->
              Enum.filter(modules, &function_exported?(&1, :cache_name, 0))
            end)
        end
    end
  end

  @doc """
  Validates that the list of cache modules contains no duplicates.

  Raises with a descriptive message listing the duplicates if any are found.
  """
  @spec validate_uniq!([module]) :: [module]
  def validate_uniq!(caches) do
    unique = Enum.uniq(caches)

    if unique === caches do
      caches
    else
      duplicates = caches -- unique

      raise """
      The following caches have been specified more than once:
      #{inspect(duplicates)}

      Please compare your test file and CacheCase module.
      """
    end
  end

  defp find_cache_supervisor(sup_pid) do
    sup_pid
    |> Supervisor.which_children()
    |> Enum.find_value(fn {_id, pid, _type, modules} ->
      if is_list(modules) and Cache in modules, do: pid
    end)
  end
end
