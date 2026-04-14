import '../models/sync_operation.dart';

/// Interface for persisting the sync queue across app restarts.
///
/// Implement this class to back [SyncQueue] with any storage mechanism
/// — Hive, SQLite, SharedPreferences, a file, etc.
///
/// ```dart
/// class HiveStorageAdapter implements StorageAdapter {
///   final Box _box;
///   HiveStorageAdapter(this._box);
///
///   @override
///   Future<List<SyncOperation>> load() async {
///     final raw = _box.get('queue', defaultValue: []) as List;
///     return raw
///       .map((e) => SyncOperation.fromJson(Map<String, dynamic>.from(e)))
///       .toList();
///   }
///
///   @override
///   Future<void> save(List<SyncOperation> operations) async {
///     await _box.put('queue', operations.map((e) => e.toJson()).toList());
///   }
///
///   @override
///   Future<void> clear() => _box.delete('queue');
/// }
/// ```
abstract class StorageAdapter {
  /// Loads all previously persisted operations.
  /// Called once by [SyncQueue] on first use.
  Future<List<SyncOperation>> load();

  /// Persists the full current queue state.
  /// Called after every mutation (add, remove, update).
  Future<void> save(List<SyncOperation> operations);

  /// Deletes all persisted operations.
  Future<void> clear();
}