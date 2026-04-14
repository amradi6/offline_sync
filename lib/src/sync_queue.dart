import 'models/sync_operation.dart';
import 'storage/storage_adapter.dart';
import 'storage/in_memory_storage_adapter.dart';

/// An ordered, persistent queue of [SyncOperation]s waiting to be synced.
///
/// Operations are sorted by [SyncOperation.priority] (descending) and
/// [SyncOperation.createdAt] (ascending) so that high-priority and older
/// operations are processed first.
///
/// The queue persists its state through a [StorageAdapter]. By default it
/// uses [InMemoryStorageAdapter], which does not survive app restarts.
/// Provide a custom adapter (e.g. Hive, SQLite) for true persistence.
///
/// ```dart
/// final queue = SyncQueue(storage: MyHiveAdapter());
/// await queue.initialize();
/// await queue.add(SyncOperation.create(...));
/// ```
class SyncQueue {
  final StorageAdapter _storage;
  final List<SyncOperation> _operations = [];
  bool _loaded = false;
  Future<void>? _initFuture;

  /// Creates a [SyncQueue] backed by the given [storage].
  /// Defaults to [InMemoryStorageAdapter] if none is provided.
  SyncQueue({StorageAdapter? storage})
      : _storage = storage ?? InMemoryStorageAdapter();

  /// Loads persisted operations from [StorageAdapter] into memory.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  /// Called automatically on first use if not called explicitly.
  Future<void> initialize() => _ensureLoaded();

  /// Returns all operations sorted by priority then creation time.
  /// Returns an empty list if the queue has not been initialised yet.
  List<SyncOperation> getAll() {
    if (!_loaded) return [];
    final sorted = List<SyncOperation>.from(_operations);
    sorted.sort((a, b) {
      final priorityCmp = b.priority.compareTo(a.priority);
      if (priorityCmp != 0) return priorityCmp;
      return a.createdAt.compareTo(b.createdAt);
    });
    return List.unmodifiable(sorted);
  }

  /// Adds [operation] to the queue and persists the change.
  /// Silently ignores duplicates — operations with the same [id]
  /// are never added twice.
  Future<void> add(SyncOperation operation) async {
    await _ensureLoaded();
    final exists = _operations.any((op) => op.id == operation.id);
    if (!exists) {
      _operations.add(operation);
      await _persist();
    }
  }

  /// Removes the operation with the given [operationId] and persists.
  /// Does nothing if no operation with that id exists.
  Future<void> remove(String operationId) async {
    await _ensureLoaded();
    _operations.removeWhere((op) => op.id == operationId);
    await _persist();
  }

  /// Replaces an existing operation in-place and persists.
  /// Matched by [SyncOperation.id]. Does nothing if not found.
  Future<void> update(SyncOperation operation) async {
    await _ensureLoaded();
    final index = _operations.indexWhere((op) => op.id == operation.id);
    if (index != -1) {
      _operations[index] = operation;
      await _persist();
    }
  }

  /// Removes all operations from memory and storage.
  Future<void> clear() async {
    _operations.clear();
    await _storage.clear();
  }

  /// The number of operations currently in the queue.
  int get length => _operations.length;

  /// Whether the queue has no pending operations.
  bool get isEmpty => _operations.isEmpty;

  /// Whether the queue has at least one pending operation.
  bool get isNotEmpty => _operations.isNotEmpty;

  Future<void> _ensureLoaded() {
    return _initFuture ??= _doLoad();
  }

  Future<void> _doLoad() async {
    final persisted = await _storage.load();
    _operations.addAll(persisted);
    _loaded = true;
  }

  Future<void> _persist() => _storage.save(List.unmodifiable(_operations));
}