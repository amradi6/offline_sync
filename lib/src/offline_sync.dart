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

/// The main entry point for the offline_sync package.
///
/// [OfflineSync] wires together [SyncQueue], [SyncEngine],
/// [ConnectivityMonitor], and [StorageAdapter] into a single
/// easy-to-use interface.
///
/// ## Quick start
///
/// ```dart
/// final sync = OfflineSync(adapter: MyApiAdapter());
/// await sync.start();
///
/// sync.create(
///   collection: 'todos',
///   entityId: 'todo-1',
///   payload: {'title': 'Buy milk'},
/// );
/// ```
///
/// ## With full configuration
///
/// ```dart
/// final sync = OfflineSync(
///   adapter: MyApiAdapter(),
///   monitor: FlutterConnectivityMonitor(),
///   storage: HiveStorageAdapter(box),
///   config: SyncConfig(
///     maxRetries: 5,
///     retryDelay: Duration(seconds: 3),
///     conflictStrategy: SyncConflictStrategy.serverWins,
///   ),
/// );
/// ```
///
/// ## Listening to events
///
/// ```dart
/// sync.onStateChanged.listen((state) => print('Engine: $state'));
/// sync.onDeadLetter.listen((op) => print('Gave up on: ${op.entityId}'));
/// sync.onConflict.listen((e) => print('Conflict: ${e.message}'));
/// ```
class OfflineSync {
  late final SyncEngine _engine;
  late final SyncQueue _queue;

  /// Creates an [OfflineSync] instance.
  ///
  /// - [adapter] — required. Your [SyncAdapter] implementation.
  /// - [monitor] — optional. Defaults to [AlwaysOnlineMonitor].
  /// - [storage] — optional. Defaults to [InMemoryStorageAdapter].
  /// - [config] — optional. Defaults to [SyncConfig] with sensible values.
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
  }

  // ── Streams ──────────────────────────────────────────────

  /// Emits [SyncEngineState] whenever the engine changes state.
  Stream<SyncEngineState> get onStateChanged => _engine.onStateChanged;

  /// Emits a [SyncOperation] when it is moved to the dead-letter queue
  /// after exhausting all retries.
  Stream<SyncOperation> get onDeadLetter => _engine.onDeadLetter;

  /// Emits a [SyncOperation] after each individual failed attempt,
  /// including the updated [SyncOperation.retries] count.
  Stream<SyncOperation> get onFailedAttempt => _engine.onFailedAttempt;

  /// Emits a [SyncConflictException] whenever the adapter reports a conflict.
  Stream<SyncConflictException> get onConflict => _engine.onConflict;

  // ── Status ───────────────────────────────────────────────

  /// The current state of the sync engine.
  SyncEngineState get state => _engine.state;

  /// The number of operations currently waiting in the queue.
  int get pendingCount => _engine.pendingCount;

  /// Operations that failed all retries and were removed from the queue.
  /// Call [retryDeadLetter] to re-enqueue them.
  List<SyncOperation> get deadLetterQueue => _engine.deadLetterQueue;

  // ── Lifecycle ────────────────────────────────────────────

  /// Starts the engine — loads persisted operations, begins watching
  /// connectivity, and flushes the queue if already online.
  Future<void> start() => _engine.start();

  /// Stops the engine and releases all resources.
  /// The instance cannot be restarted after calling [stop].
  Future<void> stop() => _engine.stop();

  // ── Enqueue helpers ──────────────────────────────────────

  /// Enqueues a raw [SyncOperation]. Prefer [create], [update],
  /// or [delete] for a more readable call site.
  void enqueue(SyncOperation operation) => _engine.enqueue(operation);

  /// Enqueues a create operation for [collection]/[entityId] with [payload].
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

  /// Enqueues an update operation for [collection]/[entityId] with [payload].
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

  /// Enqueues a delete operation for [collection]/[entityId].
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

  /// Re-enqueues all dead-lettered operations with zero retries
  /// and triggers an immediate flush if online.
  Future<void> retryDeadLetter() => _engine.retryDeadLetter();
}