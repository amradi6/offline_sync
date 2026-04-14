import 'storage_adapter.dart';
import '../models/sync_operation.dart';

/// A [StorageAdapter] that keeps operations in memory only.
///
/// This is the default adapter used by [SyncQueue]. It does not
/// survive app restarts — use it for testing or when persistence
/// is not required.
///
/// For production use, provide a persistent adapter backed by
/// Hive, SQLite, or SharedPreferences.
class InMemoryStorageAdapter implements StorageAdapter {
  List<SyncOperation> _store = [];

  @override
  Future<List<SyncOperation>> load() async => List.of(_store);

  @override
  Future<void> save(List<SyncOperation> operations) async {
    _store = List.of(operations);
  }

  @override
  Future<void> clear() async => _store = [];
}