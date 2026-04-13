import 'sync_conflict_strategy.dart';

class SyncConfig {
  final int maxRetries;
  final Duration retryDelay;
  final SyncConflictStrategy conflictStrategy;

  const SyncConfig({
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 2),
    this.conflictStrategy = SyncConflictStrategy.clientWins,
  });
}