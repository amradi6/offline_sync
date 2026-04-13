enum SyncConflictStrategy {
  /// Client always wins — retries with the same payload, ignoring server state.
  clientWins,

  /// Server always wins — drops the operation without retrying.
  serverWins,

  /// Last write wins — compares createdAt timestamps, newest one wins.
  lastWriteWins,
}

/// Thrown by SyncAdapter to signal a conflict (e.g. HTTP 409).
class SyncConflictException implements Exception {
  final String? message;

  /// Optional server payload for lastWriteWins comparison.
  final Map<String, dynamic>? serverPayload;
  final DateTime? serverUpdatedAt;

  const SyncConflictException({
    this.message,
    this.serverPayload,
    this.serverUpdatedAt,
  });

  @override
  String toString() => 'SyncConflictException: ${message ?? 'conflict detected'}';
}