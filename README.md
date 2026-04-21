# Ballerina Redis-backed short-term chat message store connector

[![Build](https://github.com/ballerina-platform/module-ballerinax-ai.memory.redis/actions/workflows/ci.yml/badge.svg)](https://github.com/ballerina-platform/module-ballerinax-ai.memory.redis/actions/workflows/ci.yml)
[![GitHub Last Commit](https://img.shields.io/github/last-commit/ballerina-platform/module-ballerinax-ai.memory.redis.svg)](https://github.com/ballerina-platform/module-ballerinax-ai.memory.redis/commits/main)
[![GitHub Issues](https://img.shields.io/github/issues/ballerina-platform/ballerina-library/module/ai.memory.redis.svg?label=Open%20Issues)](https://github.com/ballerina-platform/ballerina-library/labels/module%2Fai.memory.redis)

## Overview

This module provides a Redis-backed short-term memory store to use with AI messages (e.g., with AI agents, model providers, etc.).

## Prerequisites

- A running Redis server (local or cloud-hosted)

## Quickstart

Follow the steps below to use this store in your Ballerina application:

1. Import the `ballerinax/ai.memory.redis` module.

```ballerina
import ballerinax/ai.memory.redis;
```

Optionally, import the `ballerina/ai` and/or `ballerinax/redis` module(s).

```ballerina
import ballerina/ai;
import ballerinax/redis;
```

2. Create the short-term memory store by passing either the connection configuration or a `redis:Client`.

    i. Using the connection configuration

    ```ballerina
    import ballerina/ai;
    import ballerinax/ai.memory.redis;

    configurable string host = ?;
    configurable int port = ?;

    ai:ShortTermMemoryStore store = check new redis:ShortTermMemoryStore({
        host, port
    });
    ```

    ii. Using an existing `redis:Client`

    ```ballerina
    import ballerina/ai;
    import ballerinax/redis;
    import ballerinax/ai.memory.redis as redisStore;

    configurable string host = ?;
    configurable int port = ?;

    redis:Client redisClient = check new redis:Client(connection = {host, port});
    ai:ShortTermMemoryStore store = check new redisStore:ShortTermMemoryStore(redisClient);
    ```

    Optionally, specify the maximum number of messages to store per key (`maxMessagesPerKey` - defaults to `20`), the configuration for the in-memory cache (`cacheConfig`), and a custom key prefix (`keyPrefix` - defaults to `"chat_memory"`).

    ```ballerina
    ai:ShortTermMemoryStore store = check new redis:ShortTermMemoryStore({
        host, port
    }, 10, {capacity: 10}, "my_app_memory");
    ```

## Build from the source

### Setting up the prerequisites

1. Download and install Java SE Development Kit (JDK) version 21. You can download it from either of the following sources:

    * [Oracle JDK](https://www.oracle.com/java/technologies/downloads/)
    * [OpenJDK](https://adoptium.net/)

   > **Note:** After installation, remember to set the `JAVA_HOME` environment variable to the directory where JDK was installed.

2. Download and install [Ballerina Swan Lake](https://ballerina.io/).

3. Download and install [Docker](https://www.docker.com/get-started).

   > **Note**: Ensure that the Docker daemon is running before executing any tests.

4. Export a GitHub personal access token with `read:packages` permission as follows:

    ```bash
    export packageUser=<Username>
    export packagePAT=<Personal access token>
    ```

### Build options

Execute the commands below to build from the source.

1. To build the package:

   ```bash
   ./gradlew clean build
   ```

2. To run the tests:

   ```bash
   ./gradlew clean test
   ```

3. To build without the tests:

   ```bash
   ./gradlew clean build -x test
   ```

4. To debug the package with a remote debugger:

   ```bash
   ./gradlew clean build -Pdebug=<port>
   ```

5. To debug with the Ballerina language:

   ```bash
   ./gradlew clean build -PbalJavaDebug=<port>
   ```

6. To publish the generated artifacts to the local Ballerina Central repository:

    ```bash
    ./gradlew clean build -PpublishToLocalCentral=true
    ```

7. To publish the generated artifacts to the Ballerina Central repository:

   ```bash
   ./gradlew clean build -PpublishToCentral=true
   ```

## Contribute to Ballerina

As an open-source project, Ballerina welcomes contributions from the community.

For more information, go to the [contribution guidelines](https://github.com/ballerina-platform/ballerina-lang/blob/master/CONTRIBUTING.md).

## Code of conduct

All the contributors are encouraged to read the [Ballerina Code of Conduct](https://ballerina.io/code-of-conduct).

## Useful links

* For more information go to the [`ai.memory.redis` package](https://central.ballerina.io/ballerinax/ai.memory.redis/latest).
* For example demonstrations of the usage, go to [Ballerina By Examples](https://ballerina.io/learn/by-example/).
* Chat live with us via our [Discord server](https://discord.gg/ballerinalang).
* Post all technical questions on Stack Overflow with the [#ballerina](https://stackoverflow.com/questions/tagged/ballerina) tag.
