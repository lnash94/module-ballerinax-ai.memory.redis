# Ballerina Redis Short-Term Memory Store

## Overview

This Ballerina module provides a Redis-backed short-term memory store for AI chat messages. It implements the `ai:ShortTermMemoryStore` interface, enabling AI agents and model providers to persist conversation history using Redis as the storage backend.

## Features

- **Redis-backed storage**: Persistent storage of chat messages using Redis data structures
- **Configurable message limits**: Set the maximum number of interactive messages per session key (default: 20)
- **In-memory caching**: Optional cache layer for improved read performance (default capacity: 20)
- **Flexible initialization**: Use either a connection configuration or a pre-created Redis client

## Prerequisites

- [Ballerina Swan Lake](https://ballerina.io/downloads/)
- A running Redis server (local or remote)

## Getting Started

### Configuration-based Setup

```ballerina
import ballerinax/ai.memory.redis;

redis:ShortTermMemoryStore store = check new (
    connection = {
        host: "localhost",
        port: 6379
    }
);
```

### Client-based Setup

```ballerina
import ballerinax/ai.memory.redis;
import ballerinax/redis as redisClient;

redisClient:Client cl = check new (
    connection = {
        host: "localhost",
        port: 6379
    }
);

redis:ShortTermMemoryStore store = check new (cl);
```

## Customization

### Message Capacity

```ballerina
redis:ShortTermMemoryStore store = check new (
    connection = {host: "localhost", port: 6379},
    maxMessagesPerKey = 50
);
```

### Cache Configuration

```ballerina
import ballerina/cache;

redis:ShortTermMemoryStore store = check new (
    connection = {host: "localhost", port: 6379},
    cacheConfig = {capacity: 30, evictionFactor: 0.2}
);
```

### Key Prefix

```ballerina
redis:ShortTermMemoryStore store = check new (
    connection = {host: "localhost", port: 6379},
    keyPrefix = "my_app_memory"
);
```

## Building from Source

### Prerequisites

- JDK 21
- [Ballerina Swan Lake](https://ballerina.io/downloads/)
- Docker (for running tests)

### Build

```bash
bal build
```

### Run Tests

Start a Redis server (e.g., using Docker):

```bash
docker run -d -p 6379:6379 --name redis-test redis:7-alpine
```

Then run:

```bash
bal test
```

## Community

- [Discord](https://discord.gg/ballerinalang)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/ballerina) (tag: `ballerina`)

## License

This module is available under the [Apache 2.0 License](LICENSE).
