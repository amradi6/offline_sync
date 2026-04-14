/// How [SyncEngine] resolves a conflict when [SyncAdapter.execute]
/// throws a [SyncConflictException].
enum SyncConflictStrategy {
  /// The client payload always wins.
  /// The operation is retried as-is until it succeeds or hits [SyncConfig.maxRetries].
  clientWins,

  /// The server state always wins.
  /// The operation is dropped immediately without retrying.
  serverWins,

  /// The most recently modified version wins.
  /// Requires [SyncConflictException.serverUpdatedAt] to be set.
  /// If the server version is newer, the operation is dropped.
  /// If the client version is newer, the operation is retried.
  lastWriteWins,
}

/// Thrown by [SyncAdapter.execute] to signal that the remote server
/// reported a conflict (e.g. HTTP 409 Conflict).
///
/// ```dart
/// if (response.statusCode == 409) {
///   throw SyncConflictException(
///     message: 'Record modified on server',
///     serverUpdatedAt: DateTime.parse(response.body['updatedAt']),
///   );
/// }
/// ```
class SyncConflictException implements Exception {
  /// Human-readable description of the conflict.
  final String? message;

  /// The server's current payload, if available.
  /// Useful for merging data in custom conflict resolution logic.
  final Map<String, dynamic>? serverPayload;

  /// When the server last modified this record.
  /// Required for [SyncConflictStrategy.lastWriteWins] to work correctly.
  final DateTime? serverUpdatedAt;

  const SyncConflictException({
    this.message,
    this.serverPayload,
    this.serverUpdatedAt,
  });

  @override
  String toString() =>
      'SyncConflictException: ${message ?? 'conflict detected'}';
}