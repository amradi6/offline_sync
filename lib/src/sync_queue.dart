import 'models/sync_operation.dart';
import 'storage/storage_adapter.dart';
import 'storage/in_memory_storage_adapter.dart';

class SyncQueue {
  final StorageAdapter _storage;
  final List<SyncOperation> _operations = [];
  bool _loaded = false;

  SyncQueue({StorageAdapter? storage})
    : _storage = storage ?? InMemoryStorageAdapter();

  /// Must be called once before using the queue.
  Future<void> initialize() async => _ensureLoaded();

  Future<void>? _initFuture;

  Future<void> _ensureLoaded() {
    return _initFuture ??= _doLoad();
  }

  Future<void> _doLoad() async {
    final persisted = await _storage.load();
    _operations.addAll(persisted);
    _loaded = true;
  }

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

  Future<void> add(SyncOperation operation) async {
    await _ensureLoaded();
    final exists = _operations.any((op) => op.id == operation.id);
    if (!exists) {
      _operations.add(operation);
      await _persist();
    }
  }

  Future<void> remove(String operationId) async {
    await _ensureLoaded();
    _operations.removeWhere((op) => op.id == operationId);
    await _persist();
  }

  Future<void> update(SyncOperation operation) async {
    await _ensureLoaded();
    final index = _operations.indexWhere((op) => op.id == operation.id);
    if (index != -1) {
      _operations[index] = operation;
      await _persist();
    }
  }

  Future<void> clear() async {
    _operations.clear();
    await _storage.clear();
  }

  int get length => _operations.length;

  bool get isEmpty => _operations.isEmpty;

  bool get isNotEmpty => _operations.isNotEmpty;

  Future<void> _persist() => _storage.save(List.unmodifiable(_operations));
}
