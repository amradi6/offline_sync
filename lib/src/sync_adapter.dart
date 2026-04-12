import 'models/sync_operation.dart';

abstract class SyncAdapter {
  /// Called by SyncEngine for each operation it dequeues.
  /// Throw any exception to signal failure — the engine will handle retries.
  Future<void> execute(SyncOperation operation);
}
