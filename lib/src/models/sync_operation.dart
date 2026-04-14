import 'package:uuid/uuid.dart';

/// The type of operation to perform against the remote API.
enum SyncOperationType {
  /// Create a new remote record (HTTP POST).
  create,

  /// Update an existing remote record (HTTP PATCH/PUT).
  update,

  /// Delete a remote record (HTTP DELETE).
  delete,
}

/// The lifecycle status of a [SyncOperation] within the queue.
enum SyncStatus {
  /// Queued and waiting to be sent.
  pending,

  /// Currently being sent by [SyncEngine].
  syncing,

  /// Last attempt failed. Will be retried up to [SyncConfig.maxRetries].
  failed,

  /// Successfully synced. Safe to remove from the queue.
  done,
}

/// An immutable record of a single offline action that needs to be
/// synchronised with the remote server.
///
/// Operations are created via the named factories [SyncOperation.create],
/// [SyncOperation.update], and [SyncOperation.delete]. Each factory
/// automatically generates a unique [id] and sets [createdAt] to now.
///
/// ```dart
/// final op = SyncOperation.create(
///   collection: 'users',
///   entityId: 'user-1',
///   payload: {'name': 'Alice'},
/// );
/// ```
class SyncOperation {
  /// Unique identifier for this operation. Generated as UUID v4.
  final String id;

  /// Whether this is a create, update, or delete.
  final SyncOperationType type;

  /// The resource collection this operation targets (e.g. `'users'`).
  final String collection;

  /// The remote record's identifier. Used for update and delete operations.
  final String entityId;

  /// The data to send to the server. Empty map for delete operations.
  final Map<String, dynamic> payload;

  /// When the user performed this action offline.
  final DateTime createdAt;

  /// How many sync attempts have failed so far. Starts at 0.
  final int retries;

  /// Current lifecycle status of this operation.
  final SyncStatus status;

  /// Higher priority operations are synced first. Defaults to 0.
  final int priority;

  /// Creates a [SyncOperation] with all fields required.
  /// Prefer the named factories [create], [update], [delete].
  const SyncOperation({
    required this.id,
    required this.type,
    required this.collection,
    required this.entityId,
    required this.payload,
    required this.createdAt,
    this.retries = 0,
    this.status = SyncStatus.pending,
    this.priority = 0,
  });

  /// Creates a new [SyncOperation] of type [SyncOperationType.create].
  factory SyncOperation.create({
    required String collection,
    required String entityId,
    required Map<String, dynamic> payload,
    int priority = 0,
  }) {
    return SyncOperation(
      id: const Uuid().v4(),
      type: SyncOperationType.create,
      collection: collection,
      entityId: entityId,
      payload: payload,
      createdAt: DateTime.now(),
      priority: priority,
    );
  }

  /// Creates a new [SyncOperation] of type [SyncOperationType.update].
  factory SyncOperation.update({
    required String collection,
    required String entityId,
    required Map<String, dynamic> payload,
    int priority = 0,
  }) {
    return SyncOperation(
      id: const Uuid().v4(),
      type: SyncOperationType.update,
      collection: collection,
      entityId: entityId,
      payload: payload,
      createdAt: DateTime.now(),
      priority: priority,
    );
  }

  /// Creates a new [SyncOperation] of type [SyncOperationType.delete].
  /// [payload] is always empty for delete operations.
  factory SyncOperation.delete({
    required String collection,
    required String entityId,
    int priority = 0,
  }) {
    return SyncOperation(
      id: const Uuid().v4(),
      type: SyncOperationType.delete,
      collection: collection,
      entityId: entityId,
      payload: const {},
      createdAt: DateTime.now(),
      priority: priority,
    );
  }

  /// Returns a copy of this operation with the given fields replaced.
  /// Only [retries] and [status] can be changed — all other fields
  /// are immutable by design.
  SyncOperation copyWith({
    int? retries,
    SyncStatus? status,
  }) {
    return SyncOperation(
      id: id,
      type: type,
      collection: collection,
      entityId: entityId,
      payload: payload,
      createdAt: createdAt,
      retries: retries ?? this.retries,
      status: status ?? this.status,
      priority: priority,
    );
  }

  /// Serialises this operation to a JSON-compatible map.
  /// Used by [StorageAdapter] implementations to persist the queue.
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'collection': collection,
    'entityId': entityId,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    'retries': retries,
    'status': status.name,
    'priority': priority,
  };

  /// Deserialises a [SyncOperation] from a JSON-compatible map.
  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    return SyncOperation(
      id: json['id'] as String,
      type: SyncOperationType.values.byName(json['type'] as String),
      collection: json['collection'] as String,
      entityId: json['entityId'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      createdAt: DateTime.parse(json['createdAt'] as String),
      retries: json['retries'] as int,
      status: SyncStatus.values.byName(json['status'] as String),
      priority: json['priority'] as int,
    );
  }
}