# Introduction to ElixirCache

ElixirCache is a standardized and testable caching library for Elixir applications. It provides a consistent interface for various cache backends, allowing you to seamlessly switch between different storage mechanisms while maintaining the same API.

## Key Features

- **Multiple Cache Adapters**: Support for ETS, DETS, Redis, Agent, and ConCache
- **Standardized Interface**: Common API for all adapters
- **Test Isolation**: Sandbox adapter for isolated testing
- **Telemetry Integration**: Built-in metrics and telemetry events
- **Feature-rich**: Support for TTL, JSON operations, and more advanced features

## When to Use ElixirCache

ElixirCache is ideal for:

- Caching frequently accessed data to reduce database load
- Temporary storage of computation results
- Session storage
- Implementing distributed caching across multiple nodes
- Applications requiring different caching strategies in different environments

## Getting Started

Check out our [installation guide](tutorials/installation.md) to begin using ElixirCache in your projects.
