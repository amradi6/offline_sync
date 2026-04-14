import 'models/sync_operation.dart';

/// Interface between [SyncEngine] and your remote API.
///
/// Implement this class to define how each [SyncOperation] is sent
/// to your backend. The engine calls [execute] for every operation
/// it dequeues and uses the outcome to decide what to do next:
///
/// - Returns normally → operation succeeded, removed from queue.
/// - Throws [SyncConflictException] → conflict resolution strategy applied.
/// - Throws anything else → failure, retry logic applied.
///
/// ```dart
/// class MyApiAdapter extends SyncAdapter {
///   @override
///   Future<void> execute(SyncOperation operation) async {
///     switch (operation.type) {
///       case SyncOperationType.create:
///         await api.post(operation.collection, operation.payload);
///       case SyncOperationType.update:
///         await api.patch(operation.collection, operation.entityId, operation.payload);
///       case SyncOperationType.delete:
///         await api.delete(operation.collection, operation.entityId);
///     }
///   }
/// }
/// ```
abstract class SyncAdapter {
  /// Executes a single [operation] against the remote API.
  ///
  /// Throw [SyncConflictException] to trigger conflict resolution.
  /// Throw any other exception to signal a retriable failure.
  Future<void> execute(SyncOperation operation);
}
