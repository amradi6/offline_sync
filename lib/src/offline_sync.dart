import 'dart:async';
import 'models/sync_operation.dart';
import 'sync_queue.dart';
import 'sync_adapter.dart';
import 'sync_engine.dart';
import 'sync_config.dart';
import 'sync_conflict_strategy.dart';
import 'connectivity_monitor.dart';
import 'always_online_monitor.dart';
import 'storage/storage_adapter.dart';

class OfflineSync {
  late final SyncEngine _engine;
  late final SyncQueue _queue;

  OfflineSync({
    required SyncAdapter adapter,
    ConnectivityMonitor? monitor,
    StorageAdapter? storage,
    SyncConfig config = const SyncConfig(),
  }) {
    _queue = SyncQueue(storage: storage);
    _engine = SyncEngine(
      queue: _queue,
      adapter: adapter,
      monitor: monitor ?? AlwaysOnlineMonitor(),
      config: config,
    );
    _queue.initialize();
  }

  // ── Streams ──────────────────────────────────────────────

  Stream<SyncEngineState> get onStateChanged => _engine.onStateChanged;
  Stream<SyncOperation> get onDeadLetter => _engine.onDeadLetter;
  Stream<SyncOperation> get onFailedAttempt => _engine.onFailedAttempt;
  Stream<SyncConflictException> get onConflict => _engine.onConflict;

  // ── Status ───────────────────────────────────────────────

  SyncEngineState get state => _engine.state;
  int get pendingCount => _engine.pendingCount;
  List<SyncOperation> get deadLetterQueue => _engine.deadLetterQueue;

  // ── Lifecycle ────────────────────────────────────────────

  Future<void> start() => _engine.start();
  Future<void> stop() => _engine.stop();

  // ── Operations ───────────────────────────────────────────

  void enqueue(SyncOperation operation) => _engine.enqueue(operation);

  void create({
    required String collection,
    required String entityId,
    required Map<String, dynamic> payload,
    int priority = 0,
  }) {
    _engine.enqueue(SyncOperation.create(
      collection: collection,
      entityId: entityId,
      payload: payload,
      priority: priority,
    ));
  }

  void update({
    required String collection,
    required String entityId,
    required Map<String, dynamic> payload,
    int priority = 0,
  }) {
    _engine.enqueue(SyncOperation.update(
      collection: collection,
      entityId: entityId,
      payload: payload,
      priority: priority,
    ));
  }

  void delete({
    required String collection,
    required String entityId,
    int priority = 0,
  }) {
    _engine.enqueue(SyncOperation.delete(
      collection: collection,
      entityId: entityId,
      priority: priority,
    ));
  }

  Future<void> retryDeadLetter() => _engine.retryDeadLetter();
}