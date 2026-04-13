import '../models/sync_operation.dart';

abstract class StorageAdapter {
  /// Load all persisted operations on startup.
  Future<List<SyncOperation>> load();

  /// Persist the full queue state after every mutation.
  Future<void> save(List<SyncOperation> operations);

  /// Clear all persisted data.
  Future<void> clear();
}