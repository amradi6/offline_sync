import 'dart:async';
import 'package:test/test.dart';
import 'package:offline_sync/offline_sync.dart';

// ── Fakes ────────────────────────────────────────────────────────────────────

class FakeAdapter extends SyncAdapter {
  final List<SyncOperation> executed = [];
  Exception? throwOn;
  SyncConflictException? conflictOn;
  int _callCount = 0;

  @override
  Future<void> execute(SyncOperation operation) async {
    _callCount++;
    if (conflictOn != null) throw conflictOn!;
    if (throwOn != null) throw throwOn!;
    executed.add(operation);
  }

  int get callCount => _callCount;
}

class FakeMonitor extends ConnectivityMonitor {
  final StreamController<bool> _controller =
  StreamController<bool>.broadcast();
  bool _isOnline;

  FakeMonitor({bool online = true}) : _isOnline = online;

  @override
  Stream<bool> get isOnline => _controller.stream;

  @override
  bool get currentStatus => _isOnline;

  @override
  Future<void> start() async {
    _controller.add(_isOnline);
  }

  @override
  Future<bool> checkNow() async => _isOnline;

  @override
  Future<void> dispose() async => _controller.close();

  void goOnline() {
    _isOnline = true;
    _controller.add(true);
  }

  void goOffline() {
    _isOnline = false;
    _controller.add(false);
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

SyncOperation makeOp({
  String collection = 'users',
  String entityId = 'u1',
  int priority = 0,
}) =>
    SyncOperation.create(
      collection: collection,
      entityId: entityId,
      payload: {'name': 'test'},
      priority: priority,
    );

SyncEngine makeEngine({
  FakeAdapter? adapter,
  FakeMonitor? monitor,
  SyncConfig config = const SyncConfig(retryDelay: Duration.zero),
}) {
  final queue = SyncQueue();
  return SyncEngine(
    queue: queue,
    adapter: adapter ?? FakeAdapter(),
    monitor: monitor ?? FakeMonitor(),
    config: config,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── basic sync ───────────────────────────────────────────

  group('basic sync', () {
    test('flushes queue when started online', () async {
      final adapter = FakeAdapter();
      final engine = makeEngine(adapter: adapter);

      engine.enqueue(makeOp(entityId: 'u1'));
      engine.enqueue(makeOp(entityId: 'u2'));

      await engine.start();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(adapter.executed.length, 2);
      expect(engine.pendingCount, 0);

      await engine.stop();
    });

    test('does not flush when started offline', () async {
      final adapter = FakeAdapter();
      final monitor = FakeMonitor(online: false);
      final engine = makeEngine(adapter: adapter, monitor: monitor);

      engine.enqueue(makeOp());

      await engine.start();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(adapter.executed.length, 0);
      expect(engine.pendingCount, 1);

      await engine.stop();
    });

    test('flushes when connectivity is restored', () async {
      final adapter = FakeAdapter();
      final monitor = FakeMonitor(online: false);
      final engine = makeEngine(adapter: adapter, monitor: monitor);

      engine.enqueue(makeOp());
      await engine.start();

      expect(adapter.executed.length, 0);

      monitor.goOnline();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(adapter.executed.length, 1);
      expect(engine.pendingCount, 0);

      await engine.stop();
    });

    test('syncs in priority order', () async {
      final adapter = FakeAdapter();
      final engine = makeEngine(adapter: adapter);

      engine.enqueue(makeOp(entityId: 'low', priority: 0));
      engine.enqueue(makeOp(entityId: 'high', priority: 10));
      engine.enqueue(makeOp(entityId: 'mid', priority: 5));

      await engine.start();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(adapter.executed[0].entityId, 'high');
      expect(adapter.executed[1].entityId, 'mid');
      expect(adapter.executed[2].entityId, 'low');

      await engine.stop();
    });

    test('enqueue while online triggers immediate sync', () async {
      final adapter = FakeAdapter();
      final engine = makeEngine(adapter: adapter);

      await engine.start();
      await Future.delayed(const Duration(milliseconds: 10));

      engine.enqueue(makeOp());
      await Future.delayed(const Duration(milliseconds: 50));

      expect(adapter.executed.length, 1);

      await engine.stop();
    });
  });

  // ── state changes ────────────────────────────────────────

  group('state', () {
    test('emits syncing then idle during flush', () async {
      final engine = makeEngine();
      final states = <SyncEngineState>[];
      engine.onStateChanged.listen(states.add);

      engine.enqueue(makeOp());
      await engine.start();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(states, contains(SyncEngineState.syncing));
      expect(states.last, SyncEngineState.idle);

      await engine.stop();
    });

    test('emits stopped on stop()', () async {
      final engine = makeEngine();
      final states = <SyncEngineState>[];
      engine.onStateChanged.listen(states.add);

      await engine.start();
      await engine.stop();

      expect(states.last, SyncEngineState.stopped);
    });
  });

  // ── retry logic ──────────────────────────────────────────

  group('retry', () {
    test('retries failed operation up to maxRetries', () async {
      final adapter = FakeAdapter()..throwOn = Exception('network error');
      final engine = makeEngine(
        adapter: adapter,
        config: const SyncConfig(maxRetries: 3, retryDelay: Duration.zero),
      );

      final attempts = <SyncOperation>[];
      engine.onFailedAttempt.listen(attempts.add);

      engine.enqueue(makeOp());
      await engine.start();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(attempts.length, 3);
      expect(attempts.last.retries, 3);

      await engine.stop();
    });

    test('moves to dead letter after maxRetries exceeded', () async {
      final adapter = FakeAdapter()..throwOn = Exception('always fails');
      final engine = makeEngine(
        adapter: adapter,
        config: const SyncConfig(maxRetries: 2, retryDelay: Duration.zero),
      );

      final deadLetters = <SyncOperation>[];
      engine.onDeadLetter.listen(deadLetters.add);

      engine.enqueue(makeOp());
      await engine.start();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(deadLetters.length, 1);
      expect(engine.pendingCount, 0);
      expect(engine.deadLetterQueue.length, 1);

      await engine.stop();
    });

    test('retryDeadLetter re-enqueues with zero retries', () async {
      final adapter = FakeAdapter()..throwOn = Exception('fail');
      final engine = makeEngine(
        adapter: adapter,
        config: const SyncConfig(maxRetries: 1, retryDelay: Duration.zero),
      );

      engine.enqueue(makeOp());
      await engine.start();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(engine.deadLetterQueue.length, 1);

      // Now fix the adapter and retry
      adapter.throwOn = null;
      await engine.retryDeadLetter();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(engine.deadLetterQueue.length, 0);
      expect(engine.pendingCount, 0);
      expect(adapter.executed.length, 1);

      await engine.stop();
    });
  });

  // ── conflict handling ────────────────────────────────────

  group('conflict', () {
    test('clientWins retries the operation', () async {
      final adapter = FakeAdapter()
        ..conflictOn = const SyncConflictException(message: 'conflict');
      final conflicts = <SyncConflictException>[];
      final engine = makeEngine(
        adapter: adapter,
        config: const SyncConfig(
          maxRetries: 2,
          retryDelay: Duration.zero,
          conflictStrategy: SyncConflictStrategy.clientWins,
        ),
      );

      engine.onConflict.listen(conflicts.add);
      engine.enqueue(makeOp());

      await engine.start();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(conflicts.length, greaterThan(0));
      expect(engine.deadLetterQueue.length, 1);

      await engine.stop();
    });

    test('serverWins drops the operation immediately', () async {
      final adapter = FakeAdapter()
        ..conflictOn = const SyncConflictException(message: 'conflict');
      final engine = makeEngine(
        adapter: adapter,
        config: const SyncConfig(
          conflictStrategy: SyncConflictStrategy.serverWins,
        ),
      );

      engine.enqueue(makeOp());
      await engine.start();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(engine.pendingCount, 0);
      expect(engine.deadLetterQueue.length, 0);

      await engine.stop();
    });

    test('lastWriteWins drops op when server is newer', () async {
      final adapter = FakeAdapter()
        ..conflictOn = SyncConflictException(
          message: 'conflict',
          serverUpdatedAt: DateTime.now().add(const Duration(hours: 1)),
        );
      final engine = makeEngine(
        adapter: adapter,
        config: const SyncConfig(
          conflictStrategy: SyncConflictStrategy.lastWriteWins,
        ),
      );

      engine.enqueue(makeOp());
      await engine.start();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(engine.pendingCount, 0);
      expect(engine.deadLetterQueue.length, 0);

      await engine.stop();
    });

    test('lastWriteWins retries when client is newer', () async {
      final adapter = FakeAdapter()
        ..conflictOn = SyncConflictException(
          message: 'conflict',
          serverUpdatedAt: DateTime.now().subtract(const Duration(hours: 1)),
        );
      final conflicts = <SyncConflictException>[];
      final engine = makeEngine(
        adapter: adapter,
        config: const SyncConfig(
          maxRetries: 1,
          retryDelay: Duration.zero,
          conflictStrategy: SyncConflictStrategy.lastWriteWins,
        ),
      );

      engine.onConflict.listen(conflicts.add);
      engine.enqueue(makeOp());

      await engine.start();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(conflicts.length, greaterThan(0));
      expect(engine.deadLetterQueue.length, 1);

      await engine.stop();
    });
  });
}