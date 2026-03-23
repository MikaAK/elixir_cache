if System.get_env("IS_CI") == "true" do
  adapter_configs = [
    {Cache.Redis, [opts: [uri: "redis://localhost:6379"]]},
    {Cache.DETS, []},
    {Cache.ETS, []},
    {Cache.Agent, []},
    {Cache.Counter, [opts: [initial_size: 100_000_000]]},
    {Cache.PersistentTerm, []},
    {Cache.ConCache, [opts: [dirty?: false]]},
    {Cache.ConCache, [name_suffix: "DirtyConCache", opts: []]}
  ]

  for {adapter, config} <- adapter_configs do
    suffix = Keyword.get(config, :name_suffix, adapter |> Module.split() |> List.last())
    module_name = Module.concat(TestCache, suffix)
    cache_name = :"test_cache_#{suffix |> Macro.underscore()}"
    opts = Keyword.get(config, :opts, [])

    module_contents =
      quote do
        use Cache,
          adapter: unquote(adapter),
          name: unquote(cache_name),
          opts: unquote(opts)
      end

    Module.create(module_name, module_contents, Macro.Env.location(__ENV__))
  end

  strategy_configs = [
    {{Cache.RefreshAhead, Cache.ETS}, [name_suffix: "RefreshAheadETS", opts: [refresh_before: 500],
      extra_fns: quote(do: (def refresh(key), do: {:ok, "refreshed:#{key}"}))]},
    {{Cache.HashRing, Cache.ETS}, [name_suffix: "HashRingETS", opts: []]},
    {{Cache.MultiLayer, [Cache.ETS, Cache.Agent]}, [name_suffix: "MultiLayerETS", opts: []]},
    {Cache.ETS, [name_suffix: "Layer1", name_prefix: "test_multi_layer", opts: []]},
    {Cache.Agent, [name_suffix: "Layer2", name_prefix: "test_multi_layer", opts: []]},
    {{Cache.MultiLayer, [TestCache.Layer1, TestCache.Layer2]}, [name_suffix: "MultiLayerModules", opts: []]},
    {{Cache.MultiLayer, [Cache.ETS]}, [name_suffix: "MultiLayerFetch", opts: [on_fetch: &TestCache.MultiLayerFetch.fetch/1],
      extra_fns: quote(do: (def fetch(key), do: {:ok, "fetched:#{key}"}))]},
  ]

  for {adapter, config} <- strategy_configs do
    suffix = Keyword.fetch!(config, :name_suffix)
    name_prefix = Keyword.get(config, :name_prefix, "test_strategy")
    module_name = Module.concat(TestCache, suffix)
    cache_name = :"#{name_prefix}_#{suffix |> Macro.underscore()}"
    opts = Keyword.get(config, :opts, [])
    extra_fns = Keyword.get(config, :extra_fns)

    module_contents =
      if extra_fns do
        quote do
          use Cache,
            adapter: unquote(adapter),
            name: unquote(cache_name),
            opts: unquote(opts)

          unquote(extra_fns)
        end
      else
        quote do
          use Cache,
            adapter: unquote(adapter),
            name: unquote(cache_name),
            opts: unquote(opts)
        end
      end

    Module.create(module_name, module_contents, Macro.Env.location(__ENV__))
  end
end
