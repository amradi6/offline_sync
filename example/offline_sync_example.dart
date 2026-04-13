import 'package:offline_sync/offline_sync.dart';

class FakeApiAdapter extends SyncAdapter {
  int _callCount = 0;

  @override
  Future<void> execute(SyncOperation operation) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _callCount++;

    // Simulate a conflict on the 2nd call
    if (_callCount == 2) {
      throw SyncConflictException(
        message: 'Record was modified on server',
        serverUpdatedAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
    }

    // Simulate a network failure on the 3rd call
    if (_callCount == 3) {
      throw Exception('Network error');
    }

    print('  synced [${operation.type.name}] '
        '${operation.collection}/${operation.entityId}');
  }
}

void main() async {
  final sync = OfflineSync(
    adapter: FakeApiAdapter(),
    config: SyncConfig(
      maxRetries: 2,
      retryDelay: Duration.zero,
      conflictStrategy: SyncConflictStrategy.lastWriteWins,
    ),
  );

  sync.onStateChanged.listen((state) {
    print('state → ${state.name}  (${sync.pendingCount} pending)');
  });

  sync.onConflict.listen((conflict) {
    print('conflict → ${conflict.message}');
  });

  sync.onFailedAttempt.listen((op) {
    print('failed attempt → ${op.collection}/${op.entityId} '
        '(retry ${op.retries})');
  });

  sync.onDeadLetter.listen((op) {
    print('dead letter → ${op.collection}/${op.entityId} gave up');
  });

  // Using the facade directly — no SyncOperation boilerplate
  sync.create(
    collection: 'users',
    entityId: 'user-1',
    payload: {'name': 'Alice'},
    priority: 5,
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

  print('queued ${sync.pendingCount} operations\n');

  await sync.start();
  await Future.delayed(const Duration(seconds: 3));
  await sync.stop();

  print('\nfinal pending: ${sync.pendingCount}');
  print('dead letters: ${sync.deadLetterQueue.length}');
}