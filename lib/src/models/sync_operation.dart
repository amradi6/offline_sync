import 'package:uuid/uuid.dart';

enum SyncOperationType { create, update, delete }

enum SyncStatus { pending, syncing, failed, done }

class SyncOperation {
  final String id;
  final SyncOperationType type;
  final String collection;
  final String entityId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retries;
  final SyncStatus status;
  final int priority;

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