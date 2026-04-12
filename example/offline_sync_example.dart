import 'package:offline_sync/offline_sync.dart';

class FakeApiAdapter extends SyncAdapter {
  @override
  Future<void> execute(SyncOperation operation) async {
    await Future.delayed(const Duration(milliseconds: 300));
    print(
      '  synced: [${operation.type.name}] '
      '${operation.collection}/${operation.entityId}',
    );
  }
}

void main() async {
  final queue = SyncQueue();
  final adapter = FakeApiAdapter();
  final monitor = AlwaysOnlineMonitor();
  final engine = SyncEngine(queue: queue, adapter: adapter, monitor: monitor);

  engine.onStateChanged.listen((state) {
    print('engine state → ${state.name}  (${engine.pendingCount} pending)');
  });

  queue.add(
    SyncOperation.create(
      collection: 'users',
      entityId: 'user-1',
      payload: {'name': 'Alice', 'email': 'alice@example.com'},
    ),
  );

  queue.add(
    SyncOperation.update(
      collection: 'users',
      entityId: 'user-2',
      payload: {'name': 'Bob Updated'},
      priority: 10,
    ),
  );

  queue.add(SyncOperation.delete(collection: 'orders', entityId: 'order-99'));

  print('queued ${engine.pendingCount} operations');
  print('starting engine...\n');

  await engine.start();
  await Future.delayed(const Duration(seconds: 2));
  await engine.stop();

  print('\ndone. remaining in queue: ${engine.pendingCount}');
}
