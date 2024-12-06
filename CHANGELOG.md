# 0.3.6
- chore: fix child_spec type

# 0.3.5
- fix: Cache child spec for starting under a supervisor

# 0.3.4
- add `get_or_create(key, (() -> {:ok, value} | {:error, reson}))` to allow for create or updates

# 0.3.3
- use adapter options to allow for runtime options
- update sandbox hash_set_many behaviour to be consistent
- ensure dets does a mkdir_p at startup incase directory doesn't exist

# 0.3.2
- Update nimble options to 1.x

# 0.3.1
- add some more json sandboxing
- update redis to remove uri from command options

# 0.3.0
- add con_cache
- add ets cache
- fix hash opts for redis

# 0.2.1
- Adds support for application configuration and runtime options

# 0.2.0
- Stop redis connection errors from crashing the app
- Fix hash functions for `Cache.Redis`
- Support runtime cache config
- Support redis JSON
- Add `strategy` option to `Cache.Redis` for poolboy

# 0.1.1
- Expose `pipeline` and `command` functions on redis adapters

# 0.1.0
- Initial Release
