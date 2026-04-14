import 'sync_conflict_strategy.dart';

/// Configuration options for [SyncEngine].
///
/// Pass a [SyncConfig] when constructing [OfflineSync] or [SyncEngine]
/// to customise retry behaviour and conflict resolution.
///
/// ```dart
/// final sync = OfflineSync(
///   adapter: MyAdapter(),
///   config: SyncConfig(
///     maxRetries: 5,
///     retryDelay: Duration(seconds: 3),
///     conflictStrategy: SyncConflictStrategy.serverWins,
///   ),
/// );
/// ```
class SyncConfig {
  /// Maximum number of times a failed operation is retried
  /// before being moved to the dead-letter queue. Defaults to 3.
  final int maxRetries;

  /// How long to wait before retrying a failed operation.
  /// Defaults to 2 seconds.
  final Duration retryDelay;

  /// How to resolve conflicts when [SyncAdapter] throws
  /// [SyncConflictException]. Defaults to [SyncConflictStrategy.clientWins].
  final SyncConflictStrategy conflictStrategy;

  const SyncConfig({
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 2),
    this.conflictStrategy = SyncConflictStrategy.clientWins,
  });
}