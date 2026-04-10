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
        if interactiveJsonList is string[] {
            foreach string msgJson in interactiveJsonList {
                ChatInteractiveMessageDatabaseMessage|error dbMsg = msgJson.fromJsonStringWithType();
                if dbMsg is error {
                    test:assertFail("Failed to parse interactive message from Redis: " + dbMsg.message());
                }
                actualMessages.push(transformFromInteractiveMessageDatabaseMessage(dbMsg));
            }
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
