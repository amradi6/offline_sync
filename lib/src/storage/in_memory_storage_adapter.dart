import 'storage_adapter.dart';
import '../models/sync_operation.dart';

class InMemoryStorageAdapter implements StorageAdapter {
  List<SyncOperation> _store = [];

  @override
  Future<List<SyncOperation>> load() async {
    return List.of(_store);
  }

  @override
  Future<void> save(List<SyncOperation> operations) async {
    _store = List.of(operations);
  }

  @override
  Future<void> clear() async {
    _store = [];
  }
}