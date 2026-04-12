import 'package:offline_sync/src/models/sync_operation.dart';

class SyncQueue {
  final List<SyncOperation> _operations = [];

  List<SyncOperation> getAll() {
    final sorted = List<SyncOperation>.from(_operations);
    sorted.sort((a, b) {
      final priorityCmp = b.priority.compareTo(a.priority);
      if (priorityCmp != 0) {
        return priorityCmp;
      }
      return b.createdAt.compareTo(a.createdAt);
    });
    return List.unmodifiable(sorted);
  }

  void add(SyncOperation operation) {
    final exists = _operations.any((op) => op.id == operation.id);
    if (!exists) {
      _operations.add(operation);
    }
  }

  void remove(String operationId) {
    _operations.removeWhere((op) => op.id == operationId);
  }

  void update(SyncOperation operation) {
    final index = _operations.indexWhere((op) => op.id == operation.id);
    if (index != -1) {
      _operations[index] = operation;
    }
  }

  void clear() => _operations.clear();

  int get length => _operations.length;

  bool get isEmpty => _operations.isEmpty;

  bool get isNotEmpty => _operations.isNotEmpty;
}
