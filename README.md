# offline_sync

A backend-agnostic Dart package for queuing, persisting, and syncing
offline operations when connectivity is restored.

## Features

- Queue create, update, and delete operations while offline
- Automatically flush the queue when the device comes back online
- Configurable retry logic with dead-letter queue for exhausted operations
- Three conflict resolution strategies: `clientWins`, `serverWins`, `lastWriteWins`
- Pluggable storage — bring your own Hive, SQLite, or SharedPreferences adapter
- Pluggable connectivity — bring your own `connectivity_plus` bridge
- Pure Dart — no Flutter dependency, works in any Dart environment

## Installation

```yaml
dependencies:
  offline_sync:
    path: ../offline_sync  # or pub.dev version once published
```

## Quick start

### 1. Implement SyncAdapter

```dart
class MyApiAdapter extends SyncAdapter {
  @override
  Future<void> execute(SyncOperation operation) async {
    switch (operation.type) {
      case SyncOperationType.create:
        await api.post(operation.collection, operation.payload);
      case SyncOperationType.update:
        await api.patch(
          operation.collection,
          operation.entityId,
          operation.payload,
        );
      case SyncOperationType.delete:
        await api.delete(operation.collection, operation.entityId);
    }

    // Signal a conflict
    if (response.statusCode == 409) {
      throw SyncConflictException(
        message: 'Conflict',
        serverUpdatedAt: DateTime.parse(response.body['updatedAt']),
      );
    }
  }
}
```

### 2. Create and start OfflineSync

```dart
final sync = OfflineSync(adapter: MyApiAdapter());
await sync.start();
```

### 3. Enqueue operations

```dart
sync.create(
  collection: 'todos',
  entityId: 'todo-1',
  payload: {'title': 'Buy milk', 'done': false},
);

sync.update(
  collection: 'todos',
  entityId: 'todo-1',
  payload: {'done': true},
  priority: 5,
);

sync.delete(
  collection: 'todos',
  entityId: 'todo-1',
);
```

### 4. Listen to events

```dart
sync.onStateChanged.listen((state) {
  print('Engine state: ${state.name}');
});

sync.onDeadLetter.listen((op) {
  print('Failed permanently: ${op.collection}/${op.entityId}');
});

sync.onConflict.listen((e) {
  print('Conflict detected: ${e.message}');
});

sync.onFailedAttempt.listen((op) {
  print('Attempt ${op.retries} failed for ${op.entityId}');
});
```

## Configuration

```dart
final sync = OfflineSync(
  adapter: MyApiAdapter(),
  config: SyncConfig(
    maxRetries: 5,
    retryDelay: Duration(seconds: 3),
    conflictStrategy: SyncConflictStrategy.lastWriteWins,
  ),
);
```

| Option | Default | Description |
|---|---|---|
| `maxRetries` | `3` | Attempts before moving op to dead-letter queue |
| `retryDelay` | `2s` | Wait between retry attempts |
| `conflictStrategy` | `clientWins` | How to resolve `SyncConflictException` |

## Conflict strategies

| Strategy | Behaviour |
|---|---|
| `clientWins` | Retries with the same payload until success or max retries |
| `serverWins` | Drops the operation immediately |
| `lastWriteWins` | Compares `serverUpdatedAt` vs `createdAt` — newest wins |

## Flutter connectivity

```dart
class FlutterConnectivityMonitor implements ConnectivityMonitor {
  final _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();
  bool _isOnline = false;

  @override
  Stream<bool> get isOnline => _controller.stream;

  @override
  bool get currentStatus => _isOnline;

  @override
  Future<void> start() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = result != ConnectivityResult.none;
    _controller.add(_isOnline);
    _connectivity.onConnectivityChanged.listen((result) {
      final online = result != ConnectivityResult.none;
      if (online != _isOnline) {
        _isOnline = online;
        _controller.add(_isOnline);
      }
    });
  }

  @override
  Future<bool> checkNow() async {
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  @override
  Future<void> dispose() => _controller.close();
}

// Then inject it:
final sync = OfflineSync(
  adapter: MyApiAdapter(),
  monitor: FlutterConnectivityMonitor(),
);
```

## Custom storage (Hive example)

```dart
class HiveStorageAdapter implements StorageAdapter {
  final Box _box;
  HiveStorageAdapter(this._box);

  @override
  Future<List<SyncOperation>> load() async {
    final raw = _box.get('queue', defaultValue: []) as List;
    return raw
        .map((e) => SyncOperation.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<void> save(List<SyncOperation> operations) async {
    await _box.put('queue', operations.map((e) => e.toJson()).toList());
  }

  @override
  Future<void> clear() => _box.delete('queue');
}
```

## Dead-letter queue

Operations that fail more than `maxRetries` times are moved to the
dead-letter queue and removed from the sync queue. You can inspect
and retry them manually:

```dart
print('Failed ops: ${sync.deadLetterQueue.length}');
await sync.retryDeadLetter();
```

## API reference

| Member | Description |
|---|---|
| `start()` | Starts the engine and flushes if online |
| `stop()` | Stops the engine and releases resources |
| `create(...)` | Enqueues a create operation |
| `update(...)` | Enqueues an update operation |
| `delete(...)` | Enqueues a delete operation |
| `enqueue(op)` | Enqueues a raw `SyncOperation` |
| `retryDeadLetter()` | Re-enqueues all dead-lettered operations |
| `pendingCount` | Number of operations in the queue |
| `deadLetterQueue` | Unmodifiable list of exhausted operations |
| `onStateChanged` | Stream of `SyncEngineState` changes |
| `onDeadLetter` | Stream of permanently failed operations |
| `onFailedAttempt` | Stream of individual failed attempts |
| `onConflict` | Stream of conflict exceptions |