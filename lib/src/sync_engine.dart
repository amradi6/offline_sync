import 'dart:async';
import 'models/sync_operation.dart';
import 'sync_queue.dart';
import 'sync_adapter.dart';
import 'connectivity_monitor.dart';

enum SyncEngineState { idle, syncing, stopped }

class SyncEngine {
  final SyncQueue _queue;
  final SyncAdapter _adapter;
  final ConnectivityMonitor _monitor;

  SyncEngineState _state = SyncEngineState.idle;
  StreamSubscription<bool>? _connectivitySubscription;
  final StreamController<SyncEngineState> _stateController =
      StreamController<SyncEngineState>.broadcast();

  SyncEngine({
    required SyncQueue queue,
    required SyncAdapter adapter,
    required ConnectivityMonitor monitor,
  }) : _queue = queue,
       _adapter = adapter,
       _monitor = monitor;

  Stream<SyncEngineState> get onStateChanged => _stateController.stream;

  SyncEngineState get state => _state;

  int get pendingCount => _queue.length;

  Future<void> start() async {
    await _monitor.start();

    _connectivitySubscription = _monitor.isOnline.listen((isOnline) {
      if (isOnline && _state == SyncEngineState.idle) {
        _flush();
      }
    });

    final isOnline = await _monitor.checkNow();
    if (isOnline && _queue.isNotEmpty) {
      _flush();
    }
  }

  void enqueue(SyncOperation operation) {
    _queue.add(operation);

    if (_state == SyncEngineState.idle && _monitor.currentStatus) {
      _flush();
    }
  }

  Future<void> stop() async {
    await _connectivitySubscription?.cancel();
    await _monitor.dispose();
    _setState(SyncEngineState.stopped);
    await _stateController.close();
  }

  Future<void> _flush() async {
    if (_state == SyncEngineState.syncing || _queue.isEmpty) return;

    _setState(SyncEngineState.syncing);

    try {
      final operations = _queue.getAll();

      for (final op in operations) {
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
    } catch (_) {
      _queue.update(
        op.copyWith(status: SyncStatus.failed, retries: op.retries + 1),
      );
    }
  }

  void _setState(SyncEngineState newState) {
    _state = newState;
    _stateController.add(newState);
  }
}
