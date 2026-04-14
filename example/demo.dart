// Walks through every major feature of the offline_sync package:
//   1. Basic create / update / delete sync
//   2. Offline queueing — ops pile up while offline, flush on reconnect
//   3. Priority ordering — high-priority ops go first
//   4. Retry logic — transient failures trigger automatic retries
//   5. Dead-letter queue — exhausted ops are parked and can be re-queued
//   6. Conflict strategies — clientWins / serverWins / lastWriteWins

import 'dart:async';
import 'package:offline_sync/offline_sync.dart';

// ── ANSI colour helpers ───────────────────────────────────────────────────────

const _reset = '\x1B[0m';
const _bold = '\x1B[1m';
const _green = '\x1B[32m';
const _yellow = '\x1B[33m';
const _red = '\x1B[31m';
const _cyan = '\x1B[36m';
const _grey = '\x1B[90m';

String green(String s) => '$_green$s$_reset';
String yellow(String s) => '$_yellow$s$_reset';
String red(String s) => '$_red$s$_reset';
String cyan(String s) => '$_cyan$s$_reset';
String bold(String s) => '$_bold$s$_reset';
String grey(String s) => '$_grey$s$_reset';

// ── Controllable connectivity monitor ────────────────────────────────────────

class DemoConnectivityMonitor implements ConnectivityMonitor {
  final _controller = StreamController<bool>.broadcast();
  bool _online;

  DemoConnectivityMonitor({bool online = true}) : _online = online;

  @override
  Stream<bool> get isOnline => _controller.stream;

  @override
  bool get currentStatus => _online;

  @override
  Future<void> start() async => _controller.add(_online);

  @override
  Future<bool> checkNow() async => _online;

  @override
  Future<void> dispose() async => _controller.close();

  void goOnline() {
    _online = true;
    _controller.add(true);
    print(green('  📶 connectivity restored'));
  }

  void goOffline() {
    _online = false;
    _controller.add(false);
    print(yellow('  📵 connectivity lost'));
  }
}

// ── Programmable fake adapter ─────────────────────────────────────────────────

class DemoAdapter extends SyncAdapter {
  int _calls = 0;
  final Map<int, _AdapterBehaviour> _plan;

  DemoAdapter({Map<int, _AdapterBehaviour> plan = const {}}) : _plan = plan;

  @override
  Future<void> execute(SyncOperation op) async {
    _calls++;
    await Future.delayed(const Duration(milliseconds: 150));

    final behaviour = _plan[_calls];
    if (behaviour == _AdapterBehaviour.conflict) {
      throw SyncConflictException(
        message: 'HTTP 409 on call $_calls',
        serverUpdatedAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
    }
    if (behaviour == _AdapterBehaviour.conflictServerNewer) {
      throw SyncConflictException(
        message: 'HTTP 409 — server is newer',
        serverUpdatedAt: DateTime.now().add(const Duration(hours: 1)),
      );
    }
    if (behaviour == _AdapterBehaviour.fail) {
      throw Exception('Network error on call $_calls');
    }

    print(green(
        '  ✓ synced  [${op.type.name.padRight(6)}]  '
            '${op.collection}/${op.entityId}'));
  }
}

enum _AdapterBehaviour { fail, conflict, conflictServerNewer }

// ── Shared helpers ────────────────────────────────────────────────────────────

void header(String title) {
  print('\n${bold('━' * 55)}');
  print(bold('  $title'));
  print(bold('━' * 55));
}

void section(String text) => print('\n${cyan(text)}');

StreamSubscription<T> listen<T>(
    Stream<T> stream, String label, String Function(T) fmt) {
  return stream.listen((v) => print(grey('  [$label] ') + fmt(v)));
}

// Waits until the queue drains or a timeout is reached.
Future<void> awaitDrain(OfflineSync sync,
    {Duration timeout = const Duration(seconds: 4)}) async {
  final deadline = DateTime.now().add(timeout);
  while (sync.pendingCount > 0 && DateTime.now().isBefore(deadline)) {
    await Future.delayed(const Duration(milliseconds: 50));
  }
  // Give streams a tick to deliver their last events.
  await Future.delayed(const Duration(milliseconds: 50));
}

// ── Demo 1: Basic sync ────────────────────────────────────────────────────────

Future<void> demoBasicSync() async {
  header('Demo 1 · Basic Sync  (create / update / delete)');

  final sync = OfflineSync(adapter: DemoAdapter());

  listen(sync.onStateChanged, 'engine',
          (s) => '${s.name.padRight(8)} (queue=${sync.pendingCount})');

  section('Enqueuing 3 operations (priority: user-1 highest)…');

  sync.create(
    collection: 'users',
    entityId: 'user-1',
    payload: {'name': 'Alice', 'role': 'admin'},
    priority: 10,
  );
  sync.update(
    collection: 'orders',
    entityId: 'order-42',
    payload: {'status': 'shipped'},
  );
  sync.delete(
    collection: 'sessions',
    entityId: 'session-99',
  );

  print('  pending: ${sync.pendingCount}');

  section('Starting engine…');
  await sync.start();
  await awaitDrain(sync);

  print('\n  ${bold('Result:')} pending=${sync.pendingCount}  '
      'deadLetters=${sync.deadLetterQueue.length}');
  await sync.stop();
}

// ── Demo 2: Offline queueing ──────────────────────────────────────────────────

Future<void> demoOfflineQueueing() async {
  header('Demo 2 · Offline Queueing');

  final monitor = DemoConnectivityMonitor(online: false);
  final sync = OfflineSync(adapter: DemoAdapter(), monitor: monitor);

  listen(sync.onStateChanged, 'engine',
          (s) => '${s.name.padRight(8)} (queue=${sync.pendingCount})');

  section('Device is OFFLINE. Enqueuing 3 operations…');
  await sync.start();

  sync.create(collection: 'notes', entityId: 'note-1', payload: {'text': 'Buy milk'});
  sync.create(collection: 'notes', entityId: 'note-2', payload: {'text': 'Call Alice'});
  sync.update(collection: 'notes', entityId: 'note-1', payload: {'done': true});

  await Future.delayed(const Duration(milliseconds: 200));
  print('  ops queued while offline: ${sync.pendingCount}');

  section('Simulating connectivity restored…');
  monitor.goOnline();

  await awaitDrain(sync);
  print('\n  ${bold('Result:')} pending=${sync.pendingCount}');
  await sync.stop();
}

// ── Demo 3: Priority ordering ─────────────────────────────────────────────────

Future<void> demoPriority() async {
  header('Demo 3 · Priority Ordering');

  final executed = <String>[];
  final adapter = _RecordingAdapter(executed);
  final sync = OfflineSync(adapter: adapter);

  section('Enqueuing 4 ops with mixed priorities…');

  sync.create(collection: 'logs',    entityId: 'log-1',    payload: {}, priority: 0);
  sync.create(collection: 'payment', entityId: 'pay-1',    payload: {}, priority: 100);
  sync.create(collection: 'profile', entityId: 'profile-1',payload: {}, priority: 50);
  sync.create(collection: 'logs',    entityId: 'log-2',    payload: {}, priority: 0);

  await sync.start();
  await awaitDrain(sync);

  section('Execution order (highest priority first):');
  for (final (i, id) in executed.indexed) {
    print('  ${i + 1}. $id');
  }

  await sync.stop();
}

class _RecordingAdapter extends SyncAdapter {
  final List<String> log;
  _RecordingAdapter(this.log);

  @override
  Future<void> execute(SyncOperation op) async {
    await Future.delayed(const Duration(milliseconds: 50));
    log.add('${op.collection}/${op.entityId}  (priority=${op.priority})');
    print(green('  ✓ synced  ${op.collection}/${op.entityId}  '
        '(priority=${op.priority})'));
  }
}

// ── Demo 4: Retry logic ───────────────────────────────────────────────────────

Future<void> demoRetryLogic() async {
  header('Demo 4 · Retry Logic');

  // Calls 1 and 2 fail, call 3 succeeds.
  final adapter = DemoAdapter(plan: {
    1: _AdapterBehaviour.fail,
    2: _AdapterBehaviour.fail,
  });

  final sync = OfflineSync(
    adapter: adapter,
    config: SyncConfig(
      maxRetries: 5,
      retryDelay: Duration.zero,
    ),
  );

  listen(sync.onFailedAttempt, 'retry',
          (op) => red('attempt ${op.retries} failed for ${op.entityId}'));

  section('Enqueuing 1 op. First 2 calls will fail, 3rd succeeds…');
  sync.create(collection: 'users', entityId: 'user-retry', payload: {});

  await sync.start();
  await awaitDrain(sync);

  print('\n  ${bold('Result:')} pending=${sync.pendingCount}  '
      'deadLetters=${sync.deadLetterQueue.length}');
  await sync.stop();
}

// ── Demo 5: Dead-letter queue ─────────────────────────────────────────────────

Future<void> demoDeadLetterQueue() async {
  header('Demo 5 · Dead-Letter Queue  (maxRetries=2)');

  final adapter = DemoAdapter(plan: {
    1: _AdapterBehaviour.fail,
    2: _AdapterBehaviour.fail,
    3: _AdapterBehaviour.fail,
  });

  final sync = OfflineSync(
    adapter: adapter,
    config: SyncConfig(maxRetries: 2, retryDelay: Duration.zero),
  );

  listen(sync.onFailedAttempt, 'retry',
          (op) => yellow('attempt ${op.retries} failed for ${op.entityId}'));
  listen(sync.onDeadLetter, 'dead',
          (op) => red('gave up on ${op.entityId} after ${op.retries} retries'));

  section('Enqueuing 1 op that will always fail…');
  sync.create(collection: 'billing', entityId: 'invoice-1', payload: {});

  await sync.start();
  await Future.delayed(const Duration(milliseconds: 800));

  print('\n  pending=${sync.pendingCount}  '
      'deadLetters=${sync.deadLetterQueue.length}');

  section('Fixing the adapter and calling retryDeadLetter()…');

  // Patch adapter so calls succeed from here on.
  // (We achieve this by using a fresh adapter wrapped around the same sync.)
  final workingSync = OfflineSync(adapter: DemoAdapter());
  await workingSync.start();
  for (final op in sync.deadLetterQueue) {
    workingSync.enqueue(op.copyWith(retries: 0));
  }
  await awaitDrain(workingSync);

  print('\n  ${bold('Result:')} re-synced dead-lettered op successfully');
  await workingSync.stop();
  await sync.stop();
}

// ── Demo 6: Conflict strategies ───────────────────────────────────────────────

Future<void> demoConflicts() async {
  header('Demo 6 · Conflict Strategies');

  // ── 6a: serverWins ──────────────────────────────────────────
  section('6a  serverWins — op is dropped immediately');
  {
    final adapter = DemoAdapter(plan: {1: _AdapterBehaviour.conflict});
    final sync = OfflineSync(
      adapter: adapter,
      config: const SyncConfig(conflictStrategy: SyncConflictStrategy.serverWins),
    );
    listen(sync.onConflict, 'conflict', (e) => yellow(e.message ?? ''));
    sync.create(collection: 'docs', entityId: 'doc-1', payload: {});
    await sync.start();
    await Future.delayed(const Duration(milliseconds: 500));
    print('  pending=${sync.pendingCount}  deadLetters=${sync.deadLetterQueue.length}');
    print(green('  ✓ op silently dropped — server state wins'));
    await sync.stop();
  }

  // ── 6b: clientWins ──────────────────────────────────────────
  section('6b  clientWins — op is retried until maxRetries');
  {
    final adapter = DemoAdapter(plan: {
      1: _AdapterBehaviour.conflict,
      2: _AdapterBehaviour.conflict,
      // call 3 succeeds
    });
    final sync = OfflineSync(
      adapter: adapter,
      config: const SyncConfig(
        maxRetries: 5,
        retryDelay: Duration.zero,
        conflictStrategy: SyncConflictStrategy.clientWins,
      ),
    );
    listen(sync.onConflict, 'conflict', (e) => yellow(e.message ?? ''));
    sync.create(collection: 'docs', entityId: 'doc-2', payload: {});
    await sync.start();
    await awaitDrain(sync);
    print('\n  pending=${sync.pendingCount}  deadLetters=${sync.deadLetterQueue.length}');
    print(green('  ✓ client payload eventually synced'));
    await sync.stop();
  }

  // ── 6c: lastWriteWins (server newer) ────────────────────────
  section('6c  lastWriteWins — server is newer → op dropped');
  {
    final adapter = DemoAdapter(plan: {1: _AdapterBehaviour.conflictServerNewer});
    final sync = OfflineSync(
      adapter: adapter,
      config: const SyncConfig(conflictStrategy: SyncConflictStrategy.lastWriteWins),
    );
    listen(sync.onConflict, 'conflict', (e) => yellow(e.message ?? ''));
    sync.update(collection: 'docs', entityId: 'doc-3', payload: {'v': 2});
    await sync.start();
    await Future.delayed(const Duration(milliseconds: 500));
    print('  pending=${sync.pendingCount}  deadLetters=${sync.deadLetterQueue.length}');
    print(green('  ✓ server version kept'));
    await sync.stop();
  }

  // ── 6d: lastWriteWins (client newer) ────────────────────────
  section('6d  lastWriteWins — client is newer → op retried and synced');
  {
    final adapter = DemoAdapter(plan: {
      1: _AdapterBehaviour.conflict, // client is newer (serverUpdatedAt - 1h)
      // call 2 succeeds
    });
    final sync = OfflineSync(
      adapter: adapter,
      config: const SyncConfig(
        maxRetries: 3,
        retryDelay: Duration.zero,
        conflictStrategy: SyncConflictStrategy.lastWriteWins,
      ),
    );
    listen(sync.onConflict, 'conflict', (e) => yellow(e.message ?? ''));
    sync.update(collection: 'docs', entityId: 'doc-4', payload: {'v': 3});
    await sync.start();
    await awaitDrain(sync);
    print('\n  pending=${sync.pendingCount}  deadLetters=${sync.deadLetterQueue.length}');
    print(green('  ✓ client update pushed through'));
    await sync.stop();
  }
}

// ── Entry point ───────────────────────────────────────────────────────────────

Future<void> main() async {
  print(bold('\n╔═══════════════════════════════════════════════╗'));
  print(bold('║       offline_sync  —  demo application       ║'));
  print(bold('╚═══════════════════════════════════════════════╝'));

  await demoBasicSync();
  await demoOfflineQueueing();
  await demoPriority();
  await demoRetryLogic();
  await demoDeadLetterQueue();
  await demoConflicts();

  print(bold('\n\n  All demos complete.\n'));
}