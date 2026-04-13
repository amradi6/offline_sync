import 'dart:async';
import 'models/sync_operation.dart';
import 'sync_queue.dart';
import 'sync_adapter.dart';
import 'connectivity_monitor.dart';
import 'sync_config.dart';
import 'sync_conflict_strategy.dart';

enum SyncEngineState { idle, syncing, stopped }

class SyncEngine {
  final SyncQueue _queue;
  final SyncAdapter _adapter;
  final ConnectivityMonitor _monitor;
  final SyncConfig _config;

  final List<SyncOperation> _deadLetterQueue = [];
  SyncEngineState _state = SyncEngineState.idle;

  StreamSubscription<bool>? _connectivitySubscription;

  final StreamController<SyncEngineState> _stateController =
  StreamController<SyncEngineState>.broadcast();
  final StreamController<SyncOperation> _deadLetterController =
  StreamController<SyncOperation>.broadcast();
  final StreamController<SyncOperation> _failedAttemptController =
  StreamController<SyncOperation>.broadcast();
  final StreamController<SyncConflictException> _conflictController =
  StreamController<SyncConflictException>.broadcast();

  SyncEngine({
    required SyncQueue queue,
    required SyncAdapter adapter,
    required ConnectivityMonitor monitor,
    SyncConfig config = const SyncConfig(),
  })  : _queue = queue,
        _adapter = adapter,
        _monitor = monitor,
        _config = config;

  Stream<SyncEngineState> get onStateChanged => _stateController.stream;
  Stream<SyncOperation> get onDeadLetter => _deadLetterController.stream;
  Stream<SyncOperation> get onFailedAttempt => _failedAttemptController.stream;
  Stream<SyncConflictException> get onConflict => _conflictController.stream;

  SyncEngineState get state => _state;
  int get pendingCount => _queue.length;
  List<SyncOperation> get deadLetterQueue => List.unmodifiable(_deadLetterQueue);

  Future<void> start() async {
    await _queue.initialize();
    await _monitor.start();
    _connectivitySubscription = _monitor.isOnline.listen((isOnline) {
      if (isOnline && _state == SyncEngineState.idle) _flush();
    });
    final isOnline = await _monitor.checkNow();
    if (isOnline && _queue.isNotEmpty) _flush();
  }

  void enqueue(SyncOperation operation) {
    _queue.add(operation);
    if (_state == SyncEngineState.idle && _monitor.currentStatus) _flush();
  }

  Future<void> retryDeadLetter() async {
    for (final op in List.of(_deadLetterQueue)) {
      _deadLetterQueue.remove(op);
      _queue.add(op.copyWith(retries: 0, status: SyncStatus.pending));
    }
    if (_monitor.currentStatus) _flush();
  }

  Future<void> stop() async {
    await _connectivitySubscription?.cancel();
    await _monitor.dispose();
    _setState(SyncEngineState.stopped);
    await _stateController.close();
    await _deadLetterController.close();
    await _failedAttemptController.close();
    await _conflictController.close();
  }

  Future<void> _flush() async {
    if (_state == SyncEngineState.syncing || _queue.isEmpty) return;
    _setState(SyncEngineState.syncing);
    try {
      for (final op in _queue.getAll()) {
        await _processOperation(op);
      }
    } finally {
      _setState(SyncEngineState.idle);
    }
  }

  Future<void> _processOperation(SyncOperation op) async {
    _queue.update(op.copyWith(status: SyncStatus.syncing));

    try {
      await _adapter.execute(op);
      _queue.remove(op.id);
    } on SyncConflictException catch (conflict) {
      _conflictController.add(conflict);
      await _handleConflict(op, conflict);
    } catch (_) {
      await _handleFailure(op);
    }
  }

  Future<void> _handleConflict(
      SyncOperation op,
      SyncConflictException conflict,
      ) async {
    switch (_config.conflictStrategy) {
      case SyncConflictStrategy.clientWins:
      // Retry as-is — our payload takes priority.
        await _handleFailure(op);

      case SyncConflictStrategy.serverWins:
      // Drop the operation — server state is authoritative.
        _queue.remove(op.id);

      case SyncConflictStrategy.lastWriteWins:
        final serverTime = conflict.serverUpdatedAt;
        if (serverTime != null && serverTime.isAfter(op.createdAt)) {
          // Server is newer — drop ours.
          _queue.remove(op.id);
        } else {
          // Ours is newer — retry with our payload.
          await _handleFailure(op);
        }
    }
  }

  Future<void> _handleFailure(SyncOperation op) async {
    final updatedOp = op.copyWith(
      status: SyncStatus.failed,
      retries: op.retries + 1,
    );

    _failedAttemptController.add(updatedOp);

    if (updatedOp.retries >= _config.maxRetries) {
      _queue.remove(op.id);
      _deadLetterQueue.add(updatedOp);
      _deadLetterController.add(updatedOp);
    } else {
      _queue.update(updatedOp);
      if (_config.retryDelay > Duration.zero) {
        await Future.delayed(_config.retryDelay);
      }
    }
  }

  void _setState(SyncEngineState newState) {
    _state = newState;
    _stateController.add(newState);
  }
}