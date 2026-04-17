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
import ballerinax/redis;

# Represents a distinct error type for memory store errors.
public type Error distinct ai:MemoryError;


type CachedMessages record {|
    readonly & ai:ChatSystemMessage systemMessage?;
    (readonly & ai:ChatInteractiveMessage)[] interactiveMessages;
|};

# Represents a Redis-backed short-term memory store for messages.
@display{label:"Redis Short Term Memory Store"}
public isolated class ShortTermMemoryStore {
    *ai:ShortTermMemoryStore;

    private final redis:Client redisClient;
    private final cache:Cache? cache;
    private final int maxMessagesPerKey;
    private final string keyPrefix;

    # Initializes the Redis-backed short-term memory store.
    #
    # + redisClient - The Redis client or connection configuration to connect to the Redis server
    # + maxMessagesPerKey - The maximum number of interactive messages to store per key
    # + cacheConfig - The cache configuration for in-memory caching of messages
    # + keyPrefix - The prefix for Redis keys used to store chat messages (default: "chat_memory")
    # + returns - An error if the initialization fails
    public isolated function init(redis:Client|redis:ConnectionConfig redisClient,
            int maxMessagesPerKey = 20,
            cache:CacheConfig? cacheConfig = (),
            string keyPrefix = "chat_memory") returns Error? {
        self.keyPrefix = keyPrefix;
        if redisClient is redis:Client {
            self.redisClient = redisClient;
        } else {
            redis:Client|redis:Error initializedClient;
            redis:SecureSocket? secureSocket = redisClient.secureSocket;
            if secureSocket is redis:SecureSocket {
                initializedClient = new redis:Client(
                    connection = redisClient.connection,
                    connectionPooling = redisClient.connectionPooling,
                    isClusterConnection = redisClient.isClusterConnection,
                    secureSocket = secureSocket
                );
            } else {
                initializedClient = new redis:Client(
                    connection = redisClient.connection,
                    connectionPooling = redisClient.connectionPooling,
                    isClusterConnection = redisClient.isClusterConnection
                );
            }
            if initializedClient is redis:Error {
                return error("Failed to create Redis client: " + initializedClient.message(), initializedClient);
            }
            self.redisClient = initializedClient;
        }
        self.maxMessagesPerKey = maxMessagesPerKey;
        self.cache = cacheConfig is () ? () : new (cacheConfig);
    }

    private isolated function systemKey(string key) returns string {
        return self.keyPrefix + ":" + key + ":system";
    }

    private isolated function interactiveKey(string key) returns string {
        return self.keyPrefix + ":" + key + ":interactive";
    }

    # Retrieves the system message, if it was provided, for a given key.
    #
    # + key - The key associated with the memory
    # + return - A copy of the message if it was specified, nil if it was not, or an
    # `Error` error if the operation fails
    public isolated function getChatSystemMessage(string key) returns ai:ChatSystemMessage|Error? {
        lock {
            CachedMessages? cacheEntry = self.getCacheEntry(key);
            if cacheEntry is CachedMessages {
                return cacheEntry.systemMessage;
            }
        }

        string|redis:Error? systemMessageJson = self.redisClient->get(self.systemKey(key));

        if systemMessageJson is () {
            return ();
        }

        if systemMessageJson is redis:Error {
            return error("Failed to retrieve system message: " + systemMessageJson.message(), systemMessageJson);
        }

        ChatSystemMessageDatabaseMessage|error dbMessage = systemMessageJson.fromJsonStringWithType();
        if dbMessage is error {
            return error("Failed to parse chat message from Redis: " + dbMessage.message(), dbMessage);
        }

        // We intentionally don't populate the cache when just the system message is fetched
        // to avoid having to load interactive messages as well.
        return transformFromSystemMessageDatabaseMessage(dbMessage);
    }

    # Retrieves all stored interactive chat messages (i.e., all chat messages except the system
    # message) for a given key.
    #
    # + key - The key associated with the memory
    # + return - A copy of the messages, or an `Error` error if the operation fails
    public isolated function getChatInteractiveMessages(string key) returns ai:ChatInteractiveMessage[]|Error {
        lock {
            CachedMessages? cacheEntry = self.getCacheEntry(key);
            if cacheEntry is CachedMessages {
                return cacheEntry.interactiveMessages.clone();
            }
        }

        do {
            final var allMessages = check self.cacheFromRedis(key);
            if allMessages is readonly & ai:ChatInteractiveMessage[] {
                return allMessages;
            }
            var [_, ...interactiveMessages] = allMessages;
            return interactiveMessages;
        } on fail Error err {
            return error("Failed to retrieve chat messages: " + err.message(), err);
        }
    }

    # Retrieves all stored chat messages for a given key.
    #
    # + key - The key associated with the memory
    # + return - A copy of the messages, or an `Error` error if the operation fails
    public isolated function getAll(string key)
            returns [ai:ChatSystemMessage, ai:ChatInteractiveMessage...]|ai:ChatInteractiveMessage[]|Error {
        lock {
            CachedMessages? cacheEntry = self.getCacheEntry(key);
            if cacheEntry is CachedMessages {
                final readonly & ai:ChatSystemMessage? systemMessage = cacheEntry.systemMessage;
                if systemMessage is ai:ChatSystemMessage {
                    return [systemMessage, ...cacheEntry.interactiveMessages].clone();
                }
                return cacheEntry.interactiveMessages.clone();
            }
        }

        do {
            final var allMessages = check self.cacheFromRedis(key);
            return allMessages;
        } on fail Error err {
            return error("Failed to retrieve chat messages: " + err.message(), err);
        }
    }

    # Adds one or more chat messages to the memory store for a given key.
    #
    # + key - The key associated with the memory
    # + message - The `ChatMessage` message or messages to store. If multiple
    #             `ChatSystemMessage` values are provided in an array, only the last one is
    #             persisted; earlier system messages in the array are discarded.
    # + return - nil on success, or an `Error` if the operation fails
    public isolated function put(string key, ai:ChatMessage|ai:ChatMessage[] message) returns Error? {
        if message is ai:ChatMessage[] {
            return self.putAll(key, message);
        }
        ChatMessageDatabaseMessage dbMessage = transformToDatabaseMessage(message);
        if dbMessage is ChatSystemMessageDatabaseMessage {
            string|redis:Error setResult = self.redisClient->set(self.systemKey(key), dbMessage.toJsonString());
            if setResult is redis:Error {
                return error("Failed to set system message: " + setResult.message(), setResult);
            }
        } else {
            int|redis:Error pushResult = self.redisClient->rPush(self.interactiveKey(key), [dbMessage.toJsonString()]);
            if pushResult is redis:Error {
                return error("Failed to add chat message: " + pushResult.message(), pushResult);
            }
            if pushResult > self.maxMessagesPerKey {
                string|redis:Error trimResult = self.redisClient->lTrim(self.interactiveKey(key), 0, self.maxMessagesPerKey - 1);
                if trimResult is redis:Error {
                    self.removeCacheEntry(key);
                }
                return error(string `Cannot add more messages.`
                    + string ` Maximum limit '${self.maxMessagesPerKey}' exceeded for key '${key}'`);
            }
        }

        final readonly & ai:ChatMessage immutableMessage = mapToImmutableMessage(message);
        lock {
            CachedMessages? cacheEntry = self.getCacheEntry(key);
            if cacheEntry is () {
                return;
            }
            if immutableMessage is ai:ChatSystemMessage {
                cacheEntry.systemMessage = immutableMessage;
            } else {
                cacheEntry.interactiveMessages.push(immutableMessage);
            }
        }
    }

    private isolated function putAll(string key, ai:ChatMessage[] messages) returns Error? {
        if messages.length() == 0 {
            return;
        }

        final var [newSystemMessages, newInteractiveMessages] = partitionMessagesByType(messages);
        final readonly & ai:ChatSystemMessage? finalChatSystemMessage = getLatestSystemMessage(newSystemMessages);
        if finalChatSystemMessage is ai:ChatSystemMessage {
            ChatMessageDatabaseMessage dbMessage = transformToDatabaseMessage(finalChatSystemMessage);
            string|redis:Error setResult = self.redisClient->set(self.systemKey(key), dbMessage.toJsonString());
            if setResult is redis:Error {
                return error("Failed to set system message: " + setResult.message(), setResult);
            }
        }

        // Insert interactive messages in batch
        if newInteractiveMessages.length() > 0 {
            ai:ChatInteractiveMessage[] oldInteractiveMessages = check self.getChatInteractiveMessages(key);
            int currentCount = oldInteractiveMessages.length();
            int incoming = newInteractiveMessages.length();

            if currentCount + incoming > self.maxMessagesPerKey {
                return error(string `Cannot add more messages.`
                    + string ` Maximum limit '${self.maxMessagesPerKey}' exceeded for key '${key}'`);
            }

            string[] jsonValues = from ai:ChatInteractiveMessage msg in newInteractiveMessages
                let ChatMessageDatabaseMessage dbMsg = transformToDatabaseMessage(msg)
                select dbMsg.toJsonString();

            int|redis:Error pushResult = self.redisClient->rPush(self.interactiveKey(key), jsonValues);
            if pushResult is redis:Error {
                return error("Failed batch insert of interactive messages: " + pushResult.message(), pushResult);
            }
        }

        final ai:ChatInteractiveMessage[] & readonly immutableInteractiveMessages = from ai:ChatInteractiveMessage message
            in newInteractiveMessages
            select <readonly & ai:ChatInteractiveMessage>mapToImmutableMessage(message);
        self.updateCache(key, finalChatSystemMessage, immutableInteractiveMessages);
    }

    private isolated function updateCache(string key, readonly & ai:ChatSystemMessage? systemMessage,
            readonly & ai:ChatInteractiveMessage[] interactiveMessages) {
        lock {
            CachedMessages? cacheEntry = self.getCacheEntry(key);
            if cacheEntry is () {
                return;
            }
            if systemMessage is ai:ChatSystemMessage {
                cacheEntry.systemMessage = systemMessage;
            }
            cacheEntry.interactiveMessages.push(...interactiveMessages);
        }
        return;
    }

    # Removes the system chat message, if specified, for a given key.
    #
    # + key - The key associated with the memory
    # + return - nil on success or if there is no system chat message against the key,
    # or an `Error` error if the operation fails
    public isolated function removeChatSystemMessage(string key) returns Error? {
        int|redis:Error deleteResult = self.redisClient->del([self.systemKey(key)]);
        if deleteResult is redis:Error {
            self.removeCacheEntry(key);
            return error("Failed to delete existing system message: " + deleteResult.message(), deleteResult);
        }

        lock {
            CachedMessages? cacheEntry = self.getCacheEntry(key);
            if cacheEntry is CachedMessages {
                if cacheEntry.hasKey("systemMessage") {
                    cacheEntry.systemMessage = ();
                }
            }
        }
    }

    # Removes all stored interactive chat messages (i.e., all chat messages except the system
    # message) for a given key.
    #
    # + key - The key associated with the memory
    # + count - Optional number of messages to remove, starting from the first interactive message in;
    # if not provided, removes all messages
    # + return - nil on success, or an `Error` error if the operation fails
    public isolated function removeChatInteractiveMessages(string key, int? count = ()) returns Error? {
        if count is () {
            int|redis:Error result = self.redisClient->del([self.interactiveKey(key)]);
            if result is redis:Error {
                self.removeCacheEntry(key);
                return error("Failed to delete chat messages: " + result.message(), result);
            }
        } else {
            // lTrim keeps elements from startPos to stopPos, removing others.
            // To remove first `count` elements, keep from index `count` to -1 (last element).
            string|redis:Error result = self.redisClient->lTrim(self.interactiveKey(key), count, -1);
            if result is redis:Error {
                self.removeCacheEntry(key);
                return error("Failed to delete chat messages: " + result.message(), result);
            }
        }

        lock {
            CachedMessages? cacheEntry = self.getCacheEntry(key);
            if cacheEntry is CachedMessages {
                ai:ChatInteractiveMessage[] interactiveMessages = cacheEntry.interactiveMessages;
                if count is () || count >= interactiveMessages.length() {
                    interactiveMessages.removeAll();
                } else {
                    foreach int i in 0 ..< count {
                        _ = interactiveMessages.shift();
                    }
                }
            }
        }
    }

    # Removes all stored chat messages for a given key.
    #
    # + key - The key associated with the memory
    # + return - nil on success, or an `Error` error if the operation fails
    public isolated function removeAll(string key) returns Error? {
        int|redis:Error result = self.redisClient->del([self.systemKey(key), self.interactiveKey(key)]);
        if result is redis:Error {
            self.removeCacheEntry(key);
            return error("Failed to delete chat messages: " + result.message(), result);
        }
        self.removeCacheEntry(key);
    }

    # Checks if the memory store is full for a given key.
    #
    # + key - The key associated with the memory
    # + return - true if the memory store is full, false otherwise, or an `Error` error if the operation fails
    public isolated function isFull(string key) returns boolean|Error {
        int|redis:Error count = self.redisClient->lLen(self.interactiveKey(key));
        if count is redis:Error {
            return error("Failed to get message count: " + count.message(), count);
        }
        return count >= self.maxMessagesPerKey;
    }

    private isolated function cacheFromRedis(string key)
            returns readonly & ([ai:ChatSystemMessage, ai:ChatInteractiveMessage...]|ai:ChatInteractiveMessage[])|Error {
        do {
            // Retrieve system message
            (ai:ChatSystemMessage & readonly)? systemMessage = ();
            string|redis:Error? systemMessageJson = self.redisClient->get(self.systemKey(key));
            if systemMessageJson is redis:Error {
                return error("Failed to retrieve system message: " + systemMessageJson.message(), systemMessageJson);
            }
            if systemMessageJson is string {
                ChatSystemMessageDatabaseMessage|error dbMessage = systemMessageJson.fromJsonStringWithType();
                if dbMessage is error {
                    return error("Failed to parse system message from Redis: " + dbMessage.message(), dbMessage);
                }
                systemMessage = transformFromSystemMessageDatabaseMessage(dbMessage);
            }

            // Retrieve interactive messages
            (ai:ChatInteractiveMessage & readonly)[] interactiveMessages = [];
            string[]|redis:Error interactiveJsonList = self.redisClient->lRange(self.interactiveKey(key), 0, -1);
            if interactiveJsonList is redis:Error {
                return error("Failed to retrieve interactive messages: " + interactiveJsonList.message(),
                    interactiveJsonList);
            }
            foreach string msgJson in interactiveJsonList {
                ChatInteractiveMessageDatabaseMessage|error dbMessage = msgJson.fromJsonStringWithType();
                if dbMessage is error {
                    return error("Failed to parse chat message from Redis: " + dbMessage.message(), dbMessage);
                }
                interactiveMessages.push(transformFromInteractiveMessageDatabaseMessage(dbMessage));
            }

            final ai:ChatInteractiveMessage[] & readonly immutableInteractiveMessages =
                interactiveMessages.cloneReadOnly();
            lock {
                cache:Cache? cache = self.cache;
                if cache !is () && !cache.hasKey(key) {
                    check cache.put(
                        key, <CachedMessages>{systemMessage, interactiveMessages: [...immutableInteractiveMessages]});
                }
            }

            if systemMessage is () {
                return immutableInteractiveMessages;
            }
            return [systemMessage, ...interactiveMessages];
        } on fail error err {
            return error("Failed to retrieve chat messages: " + err.message(), err);
        }
    }

    private isolated function removeCacheEntry(string key) {
        lock {
            cache:Cache? cache = self.cache;
            if cache !is () && cache.hasKey(key) {
                cache:Error? err = cache.invalidate(key);
                if err is cache:Error {
                    // Ignore, as this is for non-existent key
                }
            }
        }
    }

    private isolated function getCacheEntry(string key) returns CachedMessages? {
        lock {
            cache:Cache? cache = self.cache;
            if cache is () || !cache.hasKey(key) {
                return ();
            }

            any|cache:Error cacheEntry = cache.get(key);
            if cacheEntry is cache:Error {
                return ();
            }

            // Since we have sole control over what is stored in the cache, this use of
            // `checkpanic` is safe.
            return checkpanic cacheEntry.ensureType();
        }
    }

    # Retrieves the maximum number of interactive messages that can be stored for each key.
    #
    # + return - The configured capacity of the message store per key
    public isolated function getCapacity() returns int {
        return self.maxMessagesPerKey;
    }
}

isolated function partitionMessagesByType(ai:ChatMessage[] messages)
    returns [ai:ChatSystemMessage[], ai:ChatInteractiveMessage[]] {
    ai:ChatSystemMessage[] systemMsgs = [];
    ai:ChatInteractiveMessage[] interactiveMsgs = [];
    foreach ai:ChatMessage msg in messages {
        if msg is ai:ChatSystemMessage {
            systemMsgs.push(msg);
        } else if msg is ai:ChatInteractiveMessage {
            interactiveMsgs.push(msg);
        }
    }
    return [systemMsgs, interactiveMsgs];
}

isolated function getLatestSystemMessage(ai:ChatSystemMessage[] systemMessages)
    returns readonly & ai:ChatSystemMessage? {
    if systemMessages.length() == 0 {
        return;
    }
    ai:ChatSystemMessage lastSystemMessage = systemMessages[systemMessages.length() - 1];
    return <readonly & ai:ChatSystemMessage>mapToImmutableMessage(lastSystemMessage);
}
