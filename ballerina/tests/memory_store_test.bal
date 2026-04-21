// Copyright (c) 2025, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/ai;
import ballerina/cache;
import ballerina/test;
import ballerinax/redis;

const string K1 = "key1";
const string K2 = "key2";
const string K3 = "key3";

const string KEY_PREFIX = "chat_memory";

const ai:ChatSystemMessage K1SM1 = {role: ai:SYSTEM, content: "You are a helpful assistant that is aware of the weather."};

const ai:ChatUserMessage K1M1 = {role: ai:USER, content: "Hello, my name is Alice. I'm from Seattle."};
final readonly & ai:ChatAssistantMessage k1m2 = {role: ai:ASSISTANT, content: "Hello Alice, what can I do for you?"};
const ai:ChatUserMessage K1M3 = {role: ai:USER, content: "I would like to know the weather today."};
final readonly & ai:ChatAssistantMessage K1M4 = {
    role: ai:ASSISTANT,
    content: "The weather in Seattle today is mostly cloudy with occasional showers and a high around 58°F."
};

const ai:ChatUserMessage K2M1 = {role: ai:USER, content: "Hello, my name is Bob."};

isolated redis:Client? modCl = ();

@test:BeforeSuite
function initClient() returns error? {
    lock {
        modCl = check new redis:Client(connection = {host: "localhost", port: 6379});
    }
}

function getClient() returns redis:Client {
    lock {
        return <redis:Client>modCl;
    }
}

function cleanupKeys() returns error? {
    redis:Client cl = getClient();
    _ = check cl->del([
        KEY_PREFIX + ":" + K1 + ":system",
        KEY_PREFIX + ":" + K1 + ":interactive",
        KEY_PREFIX + ":" + K2 + ":system",
        KEY_PREFIX + ":" + K2 + ":interactive",
        KEY_PREFIX + ":" + K3 + ":system",
        KEY_PREFIX + ":" + K3 + ":interactive"
    ]);
}

@test:Config {
    before: cleanupKeys
}
function testBasicStore() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl);

    check store.put(K1, K1SM1);
    check store.put(K1, K1M1);
    check store.put(K1, k1m2);
    check store.put(K2, K2M1);

    check assertFromRedis(cl, K1, [K1SM1], SYSTEM);
    check assertFromRedis(cl, K1, [K1M1, k1m2], INTERACTIVE);
    check assertFromRedis(cl, K1, [K1SM1, K1M1, k1m2]);

    check assertAllMessages(store, K1, [K1SM1, K1M1, k1m2]);
    check assertSystemMessage(store, K1, K1SM1);
    check assertInteractiveMessages(store, K1, [K1M1, k1m2]);

    check assertFromRedis(cl, K2, [], SYSTEM);
    check assertFromRedis(cl, K2, [K2M1], INTERACTIVE);
    check assertFromRedis(cl, K2, [K2M1]);

    check assertAllMessages(store, K2, [K2M1]);
    check assertSystemMessage(store, K2, ());
    check assertInteractiveMessages(store, K2, [K2M1]);

    check store.removeAll(K1);

    check assertFromRedis(cl, K1, [], SYSTEM);
    check assertFromRedis(cl, K1, [], INTERACTIVE);
    check assertFromRedis(cl, K1, []);

    check assertAllMessages(store, K1, []);
    check assertSystemMessage(store, K1, ());
    check assertInteractiveMessages(store, K1, []);

    check assertFromRedis(cl, K2, [], SYSTEM);
    check assertFromRedis(cl, K2, [K2M1], INTERACTIVE);
    check assertFromRedis(cl, K2, [K2M1]);

    check assertAllMessages(store, K2, [K2M1]);
    check assertSystemMessage(store, K2, ());
    check assertInteractiveMessages(store, K2, [K2M1]);

    // Add more messages to K1 after deletion.
    check store.put(K1, K1M3);

    check assertFromRedis(cl, K1, [], SYSTEM);
    check assertFromRedis(cl, K1, [K1M3], INTERACTIVE);
    check assertFromRedis(cl, K1, [K1M3]);

    check assertAllMessages(store, K1, [K1M3]);
    check assertSystemMessage(store, K1, ());
    check assertInteractiveMessages(store, K1, [K1M3]);
}

@test:Config {
    before: cleanupKeys
}
function testRemoveSystemMessage() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl);

    check store.put(K1, K1SM1);
    check store.put(K1, K1M1);
    check store.put(K1, k1m2);
    check store.put(K2, K2M1);

    check store.removeChatSystemMessage(K1);

    check assertFromRedis(cl, K1, [], SYSTEM);
    check assertFromRedis(cl, K1, [K1M1, k1m2], INTERACTIVE);
    check assertFromRedis(cl, K1, [K1M1, k1m2]);

    check assertAllMessages(store, K1, [K1M1, k1m2]);
    check assertSystemMessage(store, K1, ());
    check assertInteractiveMessages(store, K1, [K1M1, k1m2]);

    check assertFromRedis(cl, K2, [], SYSTEM);
    check assertFromRedis(cl, K2, [K2M1], INTERACTIVE);
    check assertFromRedis(cl, K2, [K2M1]);

    check assertAllMessages(store, K2, [K2M1]);
    check assertSystemMessage(store, K2, ());
    check assertInteractiveMessages(store, K2, [K2M1]);

    check store.removeChatSystemMessage(K2);

    check assertFromRedis(cl, K2, [], SYSTEM);
    check assertFromRedis(cl, K2, [K2M1], INTERACTIVE);
    check assertFromRedis(cl, K2, [K2M1]);

    check assertAllMessages(store, K2, [K2M1]);
    check assertSystemMessage(store, K2, ());
    check assertInteractiveMessages(store, K2, [K2M1]);
}

@test:Config {
    before: cleanupKeys
}
function testRemoveInteractiveMessages() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl);

    check store.put(K1, K1SM1);
    check store.put(K1, K1M1);
    check store.put(K1, k1m2);
    check store.put(K2, K2M1);

    check store.removeChatInteractiveMessages(K1);

    check assertFromRedis(cl, K1, [K1SM1], SYSTEM);
    check assertFromRedis(cl, K1, [], INTERACTIVE);
    check assertFromRedis(cl, K1, [K1SM1]);

    check assertAllMessages(store, K1, [K1SM1]);
    check assertSystemMessage(store, K1, K1SM1);
    check assertInteractiveMessages(store, K1, []);

    check assertFromRedis(cl, K2, [], SYSTEM);
    check assertFromRedis(cl, K2, [K2M1], INTERACTIVE);
    check assertFromRedis(cl, K2, [K2M1]);

    check assertAllMessages(store, K2, [K2M1]);
    check assertSystemMessage(store, K2, ());
    check assertInteractiveMessages(store, K2, [K2M1]);

    check store.removeChatInteractiveMessages(K2);

    check assertFromRedis(cl, K1, [K1SM1], SYSTEM);
    check assertFromRedis(cl, K1, [], INTERACTIVE);
    check assertFromRedis(cl, K1, [K1SM1]);

    check assertAllMessages(store, K1, [K1SM1]);
    check assertSystemMessage(store, K1, K1SM1);
    check assertInteractiveMessages(store, K1, []);

    check assertFromRedis(cl, K2, [], SYSTEM);
    check assertFromRedis(cl, K2, [], INTERACTIVE);
    check assertFromRedis(cl, K2, []);

    check assertAllMessages(store, K2, []);
    check assertSystemMessage(store, K2, ());
    check assertInteractiveMessages(store, K2, []);
}

@test:Config {
    before: cleanupKeys
}
function testRemoveAllMessages() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl);

    check store.put(K1, K1SM1);
    check store.put(K1, K1M1);
    check store.put(K1, k1m2);
    check store.put(K2, K2M1);

    check store.removeAll(K1);

    check assertFromRedis(cl, K1, [], SYSTEM);
    check assertFromRedis(cl, K1, [], INTERACTIVE);
    check assertFromRedis(cl, K1, []);

    check assertAllMessages(store, K1, []);
    check assertSystemMessage(store, K1, ());
    check assertInteractiveMessages(store, K1, []);

    check assertFromRedis(cl, K2, [], SYSTEM);
    check assertFromRedis(cl, K2, [K2M1], INTERACTIVE);
    check assertFromRedis(cl, K2, [K2M1]);

    check assertAllMessages(store, K2, [K2M1]);
    check assertSystemMessage(store, K2, ());
    check assertInteractiveMessages(store, K2, [K2M1]);

    check store.removeAll(K2);

    check assertFromRedis(cl, K1, [], SYSTEM);
    check assertFromRedis(cl, K1, [], INTERACTIVE);
    check assertFromRedis(cl, K1, []);

    check assertAllMessages(store, K1, []);
    check assertSystemMessage(store, K1, ());
    check assertInteractiveMessages(store, K1, []);

    check assertFromRedis(cl, K2, [], SYSTEM);
    check assertFromRedis(cl, K2, [], INTERACTIVE);
    check assertFromRedis(cl, K2, []);

    check assertAllMessages(store, K2, []);
    check assertSystemMessage(store, K2, ());
    check assertInteractiveMessages(store, K2, []);
}

@test:Config {
    before: cleanupKeys
}
function testRemovingSubsetOfInteractiveMessages() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl);

    check store.put(K1, K1SM1);
    check store.put(K1, K1M1);
    check store.put(K1, k1m2);
    check store.put(K1, K1M3);
    check store.put(K1, K1M4);

    check store.removeChatInteractiveMessages(K1, 2);

    check assertFromRedis(cl, K1, [K1SM1], SYSTEM);
    check assertFromRedis(cl, K1, [K1M3, K1M4], INTERACTIVE);
    check assertFromRedis(cl, K1, [K1SM1, K1M3, K1M4]);

    check assertSystemMessage(store, K1, K1SM1);
    check assertInteractiveMessages(store, K1, [K1M3, K1M4]);
    check assertAllMessages(store, K1, [K1SM1, K1M3, K1M4]);
}

@test:Config {
    before: cleanupKeys
}
function testSystemMessageOverwrite() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl);

    check store.put(K1, K1SM1);
    check store.put(K1, K1M1);
    check store.put(K1, k1m2);

    check assertSystemMessage(store, K1, K1SM1);
    check assertInteractiveMessages(store, K1, [K1M1, k1m2]);
    check assertAllMessages(store, K1, [K1SM1, K1M1, k1m2]);

    check assertFromRedis(cl, K1, [K1SM1], SYSTEM);
    check assertFromRedis(cl, K1, [K1M1, k1m2], INTERACTIVE);
    check assertFromRedis(cl, K1, [K1SM1, K1M1, k1m2]);

    final readonly & ai:ChatSystemMessage k1sm2 = {
        role: ai:SYSTEM,
        content: "You are a helpful assistant that is aware of sports."
    };
    check store.put(K1, k1sm2);

    check assertSystemMessage(store, K1, k1sm2);
    check assertInteractiveMessages(store, K1, [K1M1, k1m2]);
    check assertAllMessages(store, K1, [k1sm2, K1M1, k1m2]);

    check assertFromRedis(cl, K1, [k1sm2], SYSTEM);
    check assertFromRedis(cl, K1, [K1M1, k1m2], INTERACTIVE);
    check assertFromRedis(cl, K1, [k1sm2, K1M1, k1m2]);

    // Verify only one system message exists in Redis (set overwrites)
    string? systemJson = check cl->get(KEY_PREFIX + ":" + K1 + ":system");
    test:assertTrue(systemJson is string);
    ChatSystemMessageDatabaseMessage dbSystemMessage = check (<string>systemJson).fromJsonStringWithType();
    assertChatMessageEquals(transformFromSystemMessageDatabaseMessage(dbSystemMessage), k1sm2);
}

@test:Config {
    before: cleanupKeys
}
function testSystemMessageOverwriteWithPutAll() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl);

    final readonly & ai:ChatSystemMessage k1sm2 = {
        role: ai:SYSTEM,
        content: "You are a helpful assistant that is aware of sports."
    };
    check store.put(K1, [K1SM1, K1M1, k1m2, k1sm2]);
    check assertSystemMessage(store, K1, k1sm2);
    check assertFromRedis(cl, K1, [k1sm2, K1M1, k1m2]);

    // Verify only one system message value in Redis
    string? systemJson = check cl->get(KEY_PREFIX + ":" + K1 + ":system");
    test:assertTrue(systemJson is string);
    ChatSystemMessageDatabaseMessage dbSystemMessage = check (<string>systemJson).fromJsonStringWithType();
    assertChatMessageEquals(transformFromSystemMessageDatabaseMessage(dbSystemMessage), k1sm2);
}

@test:Config {
    before: cleanupKeys
}
function testPutWithDifferentMessageKinds() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl);

    final readonly & ai:ChatFunctionMessage funcMessage = {
        role: "function",
        name: "getWeather",
        id: "func1"
    };

    check store.put(K1, K1SM1);
    check store.put(K1, K1M1);
    check store.put(K1, k1m2);
    check store.put(K1, funcMessage);

    check assertFromRedis(cl, K1, [K1SM1], SYSTEM);
    check assertFromRedis(cl, K1, [K1M1, k1m2, funcMessage], INTERACTIVE);
    check assertFromRedis(cl, K1, [K1SM1, K1M1, k1m2, funcMessage]);

    check assertSystemMessage(store, K1, K1SM1);
    check assertInteractiveMessages(store, K1, [K1M1, k1m2, funcMessage]);
    check assertAllMessages(store, K1, [K1SM1, K1M1, k1m2, funcMessage]);
}

@test:Config {
    before: cleanupKeys
}
function testUpdateWithSystemMessageWhenInteractiveMessagesPresentOnStart() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl, 5);

    // Pre-populate Redis with interactive messages directly
    _ = check cl->rPush(KEY_PREFIX + ":" + K1 + ":interactive", [
        K1M1.toJsonString(),
        k1m2.toJsonString()
    ]);

    check store.put(K1, K1SM1);

    check assertFromRedis(cl, K1, [K1SM1], SYSTEM);
    check assertFromRedis(cl, K1, [K1M1, k1m2], INTERACTIVE);
    check assertFromRedis(cl, K1, [K1SM1, K1M1, k1m2]);

    check assertSystemMessage(store, K1, K1SM1);
    check assertInteractiveMessages(store, K1, [K1M1, k1m2]);
    check assertAllMessages(store, K1, [K1SM1, K1M1, k1m2]);
}

function assertAllMessages(ShortTermMemoryStore store, string key, ai:ChatMessage[] expected) returns error? {
    ai:ChatMessage[] actual = check store.getAll(key);
    int actualLength = actual.length();
    test:assertEquals(actualLength, expected.length());
    foreach var index in 0 ..< actualLength {
        assertChatMessageEquals(actual[index], expected[index]);
    }
}

function assertSystemMessage(ShortTermMemoryStore store, string key, ai:ChatSystemMessage? expected) returns error? {
    ai:ChatSystemMessage? actual = check store.getChatSystemMessage(key);
    if expected is () && actual is () {
        return;
    }

    if expected is () || actual is () {
        test:assertFail("Actual and expected ChatSystemMessage do not match");
    }

    assertChatMessageEquals(actual, expected);
}

function assertInteractiveMessages(ShortTermMemoryStore store, string key, ai:ChatInteractiveMessage[] expected) returns error? {
    ai:ChatInteractiveMessage[] actual = check store.getChatInteractiveMessages(key);
    int actualLength = actual.length();
    test:assertEquals(actualLength, expected.length());
    foreach var index in 0 ..< actualLength {
        assertChatMessageEquals(actual[index], expected[index]);
    }
}

enum MessageType {
    SYSTEM,
    INTERACTIVE,
    ALL
}

function assertFromRedis(redis:Client cl, string key, ai:ChatMessage[] expected,
        MessageType messageType = ALL) returns error? {
    ai:ChatMessage[] actualMessages = [];

    if messageType == SYSTEM || messageType == ALL {
        string|redis:Error? systemJson = cl->get(KEY_PREFIX + ":" + key + ":system");
        if systemJson is string {
            ChatSystemMessageDatabaseMessage|error dbMsg = systemJson.fromJsonStringWithType();
            if dbMsg is error {
                test:assertFail("Failed to parse system message from Redis: " + dbMsg.message());
            }
            actualMessages.push(transformFromDatabaseMessage(dbMsg));
        } else if systemJson is redis:Error {
            test:assertFail("Failed to read system message from Redis: " + systemJson.message());
        }
    }

    if messageType == INTERACTIVE || messageType == ALL {
        string[]|redis:Error interactiveJsonList = cl->lRange(KEY_PREFIX + ":" + key + ":interactive", 0, -1);
        if interactiveJsonList is redis:Error {
            test:assertFail("Failed to read interactive messages from Redis: " + interactiveJsonList.message());
        }
        foreach string msgJson in interactiveJsonList {
            ChatInteractiveMessageDatabaseMessage|error dbMsg = msgJson.fromJsonStringWithType();
            if dbMsg is error {
                test:assertFail("Failed to parse interactive message from Redis: " + dbMsg.message());
            }
            actualMessages.push(transformFromInteractiveMessageDatabaseMessage(dbMsg));
        }
    }

    int actualLength = actualMessages.length();
    test:assertEquals(actualLength, expected.length());
    foreach var index in 0 ..< actualLength {
        assertChatMessageEquals(actualMessages[index], expected[index]);
    }
}

isolated function assertChatMessageEquals(ai:ChatMessage actual, ai:ChatMessage expected) {
    if (actual is ai:ChatUserMessage && expected is ai:ChatUserMessage) ||
            (actual is ai:ChatSystemMessage && expected is ai:ChatSystemMessage) {
        test:assertEquals(actual.role, expected.role);
        assertContentEquals(actual.content, expected.content);
        test:assertEquals(actual.name, expected.name);
        return;
    }

    if actual is ai:ChatFunctionMessage && expected is ai:ChatFunctionMessage {
        test:assertEquals(actual.role, expected.role);
        test:assertEquals(actual.name, expected.name);
        test:assertEquals(actual.id, expected.id);
        return;
    }

    if actual is ai:ChatAssistantMessage && expected is ai:ChatAssistantMessage {
        test:assertEquals(actual.role, expected.role);
        test:assertEquals(actual.name, expected.name);
        test:assertEquals(actual.toolCalls, expected.toolCalls);
        return;
    }

    test:assertFail("Actual and expected ChatMessage types do not match");
}

isolated function assertContentEquals(ai:Prompt|string actual, ai:Prompt|string expected) {
    if actual is string && expected is string {
        test:assertEquals(actual, expected);
        return;
    }

    if actual is ai:Prompt && expected is ai:Prompt {
        test:assertEquals(actual.strings, expected.strings);
        test:assertEquals(actual.insertions, expected.insertions);
        return;
    }

    test:assertFail("Actual and expected content do not match");
}

// Cache tests

@test:Config {
    before: cleanupKeys
}
function testBasicStoreWithCache() returns error? {
    redis:Client cl = getClient();
    cache:CacheConfig cacheConfig = {
        capacity: 10,
        evictionFactor: 0.2
    };
    ShortTermMemoryStore store = check new (cl, cacheConfig = cacheConfig);

    check store.put(K1, K1SM1);
    check store.put(K1, K1M1);
    check store.put(K1, k1m2);
    check store.put(K2, K2M1);

    // First retrieval - should load from Redis and cache
    check assertAllMessages(store, K1, [K1SM1, K1M1, k1m2]);
    check assertInteractiveMessages(store, K1, [K1M1, k1m2]);

    // Second retrieval - should use cache
    check assertAllMessages(store, K1, [K1SM1, K1M1, k1m2]);
    check assertInteractiveMessages(store, K1, [K1M1, k1m2]);

    check assertAllMessages(store, K2, [K2M1]);
    check assertInteractiveMessages(store, K2, [K2M1]);
}

@test:Config {
    before: cleanupKeys
}
function testBasicStoreWithCacheWithPutAll() returns error? {
    redis:Client cl = getClient();
    cache:CacheConfig cacheConfig = {
        capacity: 10,
        evictionFactor: 0.2
    };
    ShortTermMemoryStore store = check new (cl, cacheConfig = cacheConfig);

    check store.put(K1, [K1SM1, K1M1, k1m2]);
    check store.put(K2, K2M1);

    check assertAllMessages(store, K1, [K1SM1, K1M1, k1m2]);
    check assertInteractiveMessages(store, K1, [K1M1, k1m2]);

    check assertAllMessages(store, K1, [K1SM1, K1M1, k1m2]);
    check assertInteractiveMessages(store, K1, [K1M1, k1m2]);

    check assertAllMessages(store, K2, [K2M1]);
    check assertInteractiveMessages(store, K2, [K2M1]);
}

@test:Config {
    before: cleanupKeys
}
function testCacheUpdateOnPut() returns error? {
    redis:Client cl = getClient();
    cache:CacheConfig cacheConfig = {
        capacity: 10,
        evictionFactor: 0.2
    };
    ShortTermMemoryStore store = check new (cl, cacheConfig = cacheConfig);

    check store.put(K1, K1SM1);
    check store.put(K1, K1M1);

    // Load into cache
    check assertAllMessages(store, K1, [K1SM1, K1M1]);

    // Add more messages - cache should be updated
    check store.put(K1, k1m2);
    check store.put(K1, K1M3);

    // Verify cache reflects the updates
    check assertAllMessages(store, K1, [K1SM1, K1M1, k1m2, K1M3]);
    check assertInteractiveMessages(store, K1, [K1M1, k1m2, K1M3]);
}

@test:Config {
    before: cleanupKeys
}
function testCacheUpdateWithPutAll() returns error? {
    redis:Client cl = getClient();
    cache:CacheConfig cacheConfig = {
        capacity: 10,
        evictionFactor: 0.2
    };
    ShortTermMemoryStore store = check new (cl, cacheConfig = cacheConfig);

    check store.put(K1, [K1SM1, K1M1]);
    check assertAllMessages(store, K1, [K1SM1, K1M1]);

    check store.put(K1, [k1m2, K1M3]);

    check assertAllMessages(store, K1, [K1SM1, K1M1, k1m2, K1M3]);
    check assertInteractiveMessages(store, K1, [K1M1, k1m2, K1M3]);
}

@test:Config {
    before: cleanupKeys
}
function testCacheSystemMessageUpdate() returns error? {
    redis:Client cl = getClient();
    cache:CacheConfig cacheConfig = {
        capacity: 10,
        evictionFactor: 0.2
    };
    ShortTermMemoryStore store = check new (cl, cacheConfig = cacheConfig);

    check store.put(K1, K1SM1);
    check store.put(K1, K1M1);

    check assertSystemMessage(store, K1, K1SM1);
    check assertAllMessages(store, K1, [K1SM1, K1M1]);

    final readonly & ai:ChatSystemMessage k1sm2 = {
        role: ai:SYSTEM,
        content: "You are a helpful assistant that is aware of sports."
    };
    check store.put(K1, k1sm2);

    check assertSystemMessage(store, K1, k1sm2);
    check assertAllMessages(store, K1, [k1sm2, K1M1]);
}

@test:Config {
    before: cleanupKeys
}
function testCacheSystemMessageUpdateOnPutAll() returns error? {
    redis:Client cl = getClient();
    cache:CacheConfig cacheConfig = {
        capacity: 10,
        evictionFactor: 0.2
    };
    ShortTermMemoryStore store = check new (cl, cacheConfig = cacheConfig);

    check store.put(K1, [K1SM1, K1M1]);

    check assertSystemMessage(store, K1, K1SM1);
    check assertAllMessages(store, K1, [K1SM1, K1M1]);

    final readonly & ai:ChatSystemMessage k1sm2 = {
        role: ai:SYSTEM,
        content: "You are a helpful assistant that is aware of sports."
    };
    check store.put(K1, [k1sm2, k1m2]);

    check assertSystemMessage(store, K1, k1sm2);
    check assertAllMessages(store, K1, [k1sm2, K1M1, k1m2]);
}

@test:Config {
    before: cleanupKeys
}
function testCacheInvalidationOnRemoveAll() returns error? {
    redis:Client cl = getClient();
    cache:CacheConfig cacheConfig = {
        capacity: 10,
        evictionFactor: 0.2
    };
    ShortTermMemoryStore store = check new (cl, cacheConfig = cacheConfig);

    check store.put(K1, K1SM1);
    check store.put(K1, K1M1);
    check store.put(K1, k1m2);

    check assertAllMessages(store, K1, [K1SM1, K1M1, k1m2]);

    check store.removeAll(K1);

    check assertAllMessages(store, K1, []);
    check assertSystemMessage(store, K1, ());
    check assertInteractiveMessages(store, K1, []);
}

@test:Config {
    before: cleanupKeys
}
function testCacheInvalidationOnRemoveInteractiveMessages() returns error? {
    redis:Client cl = getClient();
    cache:CacheConfig cacheConfig = {
        capacity: 10,
        evictionFactor: 0.2
    };
    ShortTermMemoryStore store = check new (cl, cacheConfig = cacheConfig);

    check store.put(K1, K1SM1);
    check store.put(K1, K1M1);
    check store.put(K1, k1m2);
    check store.put(K1, K1M3);

    check assertAllMessages(store, K1, [K1SM1, K1M1, k1m2, K1M3]);

    check store.removeChatInteractiveMessages(K1);

    check assertAllMessages(store, K1, [K1SM1]);
    check assertSystemMessage(store, K1, K1SM1);
    check assertInteractiveMessages(store, K1, []);
}

@test:Config {
    before: cleanupKeys
}
function testCacheInvalidationOnRemoveSubsetOfInteractiveMessages() returns error? {
    redis:Client cl = getClient();
    cache:CacheConfig cacheConfig = {
        capacity: 10,
        evictionFactor: 0.2
    };
    ShortTermMemoryStore store = check new (cl, cacheConfig = cacheConfig);

    check store.put(K1, K1SM1);
    check store.put(K1, K1M1);
    check store.put(K1, k1m2);
    check store.put(K1, K1M3);
    check store.put(K1, K1M4);

    check assertAllMessages(store, K1, [K1SM1, K1M1, k1m2, K1M3, K1M4]);

    check store.removeChatInteractiveMessages(K1, 2);

    check assertAllMessages(store, K1, [K1SM1, K1M3, K1M4]);
    check assertInteractiveMessages(store, K1, [K1M3, K1M4]);
}

@test:Config {
    before: cleanupKeys
}
function testCacheUpdateOnRemoveSystemMessage() returns error? {
    redis:Client cl = getClient();
    cache:CacheConfig cacheConfig = {
        capacity: 10,
        evictionFactor: 0.2
    };
    ShortTermMemoryStore store = check new (cl, cacheConfig = cacheConfig);

    check store.put(K1, K1SM1);
    check store.put(K1, K1M1);
    check store.put(K1, k1m2);

    check assertAllMessages(store, K1, [K1SM1, K1M1, k1m2]);
    check assertSystemMessage(store, K1, K1SM1);

    check store.removeChatSystemMessage(K1);

    check assertAllMessages(store, K1, [K1M1, k1m2]);
    check assertSystemMessage(store, K1, ());
    check assertInteractiveMessages(store, K1, [K1M1, k1m2]);
}

@test:Config {
    before: cleanupKeys
}
function testCacheWithMultipleKeys() returns error? {
    redis:Client cl = getClient();
    cache:CacheConfig cacheConfig = {
        capacity: 10,
        evictionFactor: 0.2
    };
    ShortTermMemoryStore store = check new (cl, cacheConfig = cacheConfig);

    check store.put(K1, K1SM1);
    check store.put(K1, K1M1);
    check store.put(K1, k1m2);

    check store.put(K2, K2M1);

    check assertAllMessages(store, K1, [K1SM1, K1M1, k1m2]);
    check assertAllMessages(store, K2, [K2M1]);

    check store.removeAll(K1);

    check assertAllMessages(store, K1, []);
    check assertAllMessages(store, K2, [K2M1]);
}

@test:Config {
    before: cleanupKeys
}
function testCacheWithSmallCapacity() returns error? {
    redis:Client cl = getClient();
    cache:CacheConfig cacheConfig = {
        capacity: 2,
        evictionFactor: 0.5
    };
    ShortTermMemoryStore store = check new (cl, cacheConfig = cacheConfig);

    check store.put(K1, K1M1);
    check store.put(K2, K2M1);
    check store.put(K3, K1M3);

    check assertAllMessages(store, K1, [K1M1]);
    check assertAllMessages(store, K2, [K2M1]);

    check assertAllMessages(store, K3, [K1M3]);

    check assertAllMessages(store, K1, [K1M1]);
    check assertAllMessages(store, K2, [K2M1]);
    check assertAllMessages(store, K3, [K1M3]);
}

@test:Config {
    before: cleanupKeys
}
function testSystemMessageRetrievalDoesNotPopulateCache() returns error? {
    redis:Client cl = getClient();
    cache:CacheConfig cacheConfig = {
        capacity: 10,
        evictionFactor: 0.2
    };
    ShortTermMemoryStore store = check new (cl, cacheConfig = cacheConfig);

    check store.put(K1, K1SM1);
    check store.put(K1, K1M1);
    check store.put(K1, k1m2);

    // Retrieve only system message - should NOT populate cache
    check assertSystemMessage(store, K1, K1SM1);

    // Add more messages
    check store.put(K1, K1M3);

    // Retrieve all messages - should load from Redis and include K1M3
    check assertAllMessages(store, K1, [K1SM1, K1M1, k1m2, K1M3]);
}

// isFull() tests

@test:Config {
    before: cleanupKeys
}
function testIsFullReturnsFalseWhenEmpty() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl, 3);

    boolean full = check store.isFull(K1);
    test:assertFalse(full);
}

@test:Config {
    before: cleanupKeys
}
function testIsFullReturnsFalseWhenBelowLimit() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl, 3);

    check store.put(K1, K1M1);
    check store.put(K1, k1m2);

    boolean full = check store.isFull(K1);
    test:assertFalse(full);
}

@test:Config {
    before: cleanupKeys
}
function testIsFullReturnsTrueWhenAtLimit() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl, 2);

    check store.put(K1, K1M1);
    check store.put(K1, k1m2);

    boolean full = check store.isFull(K1);
    test:assertTrue(full);
}

@test:Config {
    before: cleanupKeys
}
function testIsFullWithCache() returns error? {
    redis:Client cl = getClient();
    cache:CacheConfig cacheConfig = {capacity: 10, evictionFactor: 0.2};
    ShortTermMemoryStore store = check new (cl, 2, cacheConfig);

    check store.put(K1, K1M1);
    check store.put(K1, k1m2);

    // Load into cache first
    _ = check store.getAll(K1);

    // isFull reads the list length directly from Redis via LLEN, not from the cache
    boolean full = check store.isFull(K1);
    test:assertTrue(full);
}

// getCapacity() tests

@test:Config {}
function testGetCapacityReturnsDefaultValue() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl);

    test:assertEquals(store.getCapacity(), 20);
}

@test:Config {}
function testGetCapacityReturnsCustomValue() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl, 5);

    test:assertEquals(store.getCapacity(), 5);
}

// Custom keyPrefix tests

@test:Config {}
function testCustomKeyPrefixStoresUnderCorrectRedisKey() returns error? {
    redis:Client cl = getClient();
    string customPrefix = "test_prefix";
    ShortTermMemoryStore store = check new (cl, keyPrefix = customPrefix);

    check store.put(K1, K1SM1);
    check store.put(K1, K1M1);

    string? systemJson = check cl->get(customPrefix + ":" + K1 + ":system");
    test:assertTrue(systemJson is string);

    string[] interactiveList = check cl->lRange(customPrefix + ":" + K1 + ":interactive", 0, -1);
    test:assertEquals(interactiveList.length(), 1);

    _ = check cl->del([customPrefix + ":" + K1 + ":system", customPrefix + ":" + K1 + ":interactive"]);
}

@test:Config {}
function testTwoStoresWithDifferentPrefixesAreIsolated() returns error? {
    redis:Client cl = getClient();
    string prefixA = "prefix_a";
    string prefixB = "prefix_b";
    ShortTermMemoryStore storeA = check new (cl, keyPrefix = prefixA);
    ShortTermMemoryStore storeB = check new (cl, keyPrefix = prefixB);

    check storeA.put(K1, K1M1);
    check storeB.put(K1, K2M1);

    check assertInteractiveMessages(storeA, K1, [K1M1]);
    check assertInteractiveMessages(storeB, K1, [K2M1]);

    _ = check cl->del([prefixA + ":" + K1 + ":interactive", prefixB + ":" + K1 + ":interactive"]);
}

// maxMessagesPerKey limit enforcement tests

@test:Config {
    before: cleanupKeys
}
function testPutFailsWhenMaxMessagesExceeded() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl, 2);

    check store.put(K1, K1M1);
    check store.put(K1, k1m2);

    Error? result = store.put(K1, K1M3);
    test:assertTrue(result is Error);
}

@test:Config {
    before: cleanupKeys
}
function testPutAllFailsWhenMaxMessagesExceeded() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl, 2);

    check store.put(K1, K1M1);

    // 1 existing + 2 incoming = 3 > limit of 2
    Error? result = store.put(K1, [k1m2, K1M3]);
    test:assertTrue(result is Error);
}

@test:Config {
    before: cleanupKeys
}
function testPutAllCapacityExceededDoesNotOverwriteSystemMessage() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl, 2);

    // Pre-seed an existing system message and one interactive message
    check store.put(K1, K1SM1);
    check store.put(K1, K1M1);

    // putAll with a new system message + 2 interactive messages (1 existing + 2 incoming = 3 > limit of 2)
    final readonly & ai:ChatSystemMessage newSystem = {
        role: ai:SYSTEM,
        content: "You are a new system."
    };
    Error? result = store.put(K1, [newSystem, k1m2, K1M3]);
    test:assertTrue(result is Error);

    // System key must still hold original K1SM1 — must not be overwritten
    check assertSystemMessage(store, K1, K1SM1);
    check assertFromRedis(cl, K1, [K1SM1], SYSTEM);

    // Interactive messages must be unchanged
    check assertInteractiveMessages(store, K1, [K1M1]);
    check assertFromRedis(cl, K1, [K1M1], INTERACTIVE);
}

// Operations on non-existent keys

@test:Config {
    before: cleanupKeys
}
function testGetAllOnNonExistentKey() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl);

    check assertAllMessages(store, K3, []);
}

@test:Config {
    before: cleanupKeys
}
function testRemoveAllOnNonExistentKey() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl);

    Error? result = store.removeAll(K3);
    test:assertTrue(result is ());
}

@test:Config {
    before: cleanupKeys
}
function testRemoveSystemMessageOnNonExistentKey() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl);

    Error? result = store.removeChatSystemMessage(K3);
    test:assertTrue(result is ());
}

@test:Config {
    before: cleanupKeys
}
function testRemoveInteractiveOnNonExistentKey() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl);

    Error? result = store.removeChatInteractiveMessages(K3);
    test:assertTrue(result is ());
}

// removeChatInteractiveMessages count edge cases

@test:Config {
    before: cleanupKeys
}
function testRemoveInteractiveWithCountZero() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl);

    check store.put(K1, K1M1);
    check store.put(K1, k1m2);

    check store.removeChatInteractiveMessages(K1, 0);

    check assertInteractiveMessages(store, K1, [K1M1, k1m2]);
    check assertFromRedis(cl, K1, [K1M1, k1m2], INTERACTIVE);
}

@test:Config {
    before: cleanupKeys
}
function testRemoveInteractiveWithCountExceedingLength() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl);

    check store.put(K1, K1M1);
    check store.put(K1, k1m2);

    // count=10 exceeds 2 actual messages — should remove all
    check store.removeChatInteractiveMessages(K1, 10);

    check assertInteractiveMessages(store, K1, []);
    check assertFromRedis(cl, K1, [], INTERACTIVE);
}

// put() with empty array

@test:Config {
    before: cleanupKeys
}
function testPutAllWithEmptyArray() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl);

    check store.put(K1, K1M1);
    check store.put(K1, []);

    check assertAllMessages(store, K1, [K1M1]);
    check assertFromRedis(cl, K1, [K1M1]);
}

// ai:Prompt content type tests

isolated function createTestPrompt(string[] & readonly strings, anydata[] & readonly insertions)
        returns readonly & ai:Prompt => isolated object ai:Prompt {
    public final string[] & readonly strings = strings;
    public final anydata[] & readonly insertions = insertions;
};

@test:Config {
    before: cleanupKeys
}
function testPutAndGetUserMessageWithPromptContent() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl);

    string[] & readonly strings = ["Hello, my name is ", "."];
    anydata[] & readonly insertions = ["Alice"];
    final readonly & ai:Prompt prompt = createTestPrompt(strings, insertions);
    final readonly & ai:ChatUserMessage msgWithPrompt = {role: ai:USER, content: prompt};

    check store.put(K1, msgWithPrompt);

    check assertInteractiveMessages(store, K1, [msgWithPrompt]);
    check assertFromRedis(cl, K1, [msgWithPrompt], INTERACTIVE);
}

@test:Config {
    before: cleanupKeys
}
function testPutAndGetSystemMessageWithPromptContent() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl);

    string[] & readonly strings = ["You are a ", " assistant."];
    anydata[] & readonly insertions = ["helpful"];
    final readonly & ai:Prompt prompt = createTestPrompt(strings, insertions);
    final readonly & ai:ChatSystemMessage sysMsgWithPrompt = {role: ai:SYSTEM, content: prompt};

    check store.put(K1, sysMsgWithPrompt);

    check assertSystemMessage(store, K1, sysMsgWithPrompt);
    check assertFromRedis(cl, K1, [sysMsgWithPrompt], SYSTEM);
}

// name field on messages

@test:Config {
    before: cleanupKeys
}
function testPutAndGetMessageWithNameField() returns error? {
    redis:Client cl = getClient();
    ShortTermMemoryStore store = check new (cl);

    final readonly & ai:ChatSystemMessage namedSystem = {role: ai:SYSTEM, content: "You are helpful.", name: "system_v2"};
    final readonly & ai:ChatUserMessage namedUser = {role: ai:USER, content: "Hi there", name: "alice"};

    check store.put(K1, namedSystem);
    check store.put(K1, namedUser);

    check assertSystemMessage(store, K1, namedSystem);
    check assertInteractiveMessages(store, K1, [namedUser]);
    check assertFromRedis(cl, K1, [namedSystem], SYSTEM);
    check assertFromRedis(cl, K1, [namedUser], INTERACTIVE);
}
