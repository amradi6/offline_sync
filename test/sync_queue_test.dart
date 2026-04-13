import 'package:test/test.dart';
import 'package:offline_sync/offline_sync.dart';

void main() {
  late SyncQueue queue;

  setUp(() {
    queue = SyncQueue();
  });

  // ── add ─────────────────────────────────────────────────

  group('add', () {
    test('adds an operation to the queue', () async {
      final op = SyncOperation.create(
        collection: 'users',
        entityId: 'u1',
        payload: {'name': 'Alice'},
      );

      await queue.add(op);

      expect(queue.length, 1);
      expect(queue.isEmpty, false);
      expect(queue.isNotEmpty, true);
    });

    test('ignores duplicate operation ids', () async {
      final op = SyncOperation.create(
        collection: 'users',
        entityId: 'u1',
        payload: {'name': 'Alice'},
      );

      await queue.add(op);
      await queue.add(op); // same op twice

      expect(queue.length, 1);
    });

    test('allows multiple different operations', () async {
      await queue.add(SyncOperation.create(
        collection: 'users',
        entityId: 'u1',
        payload: {},
      ));
      await queue.add(SyncOperation.create(
        collection: 'users',
        entityId: 'u2',
        payload: {},
      ));

      expect(queue.length, 2);
    });
  });

  // ── remove ───────────────────────────────────────────────

  group('remove', () {
    test('removes an operation by id', () async {
      final op = SyncOperation.create(
        collection: 'users',
        entityId: 'u1',
        payload: {},
      );

      await queue.add(op);
      await queue.remove(op.id);

      expect(queue.length, 0);
      expect(queue.isEmpty, true);
    });

    test('does nothing when id does not exist', () async {
      await queue.add(SyncOperation.create(
        collection: 'users',
        entityId: 'u1',
        payload: {},
      ));

      await queue.remove('non-existent-id');

      expect(queue.length, 1);
    });
  });

  // ── update ───────────────────────────────────────────────

  group('update', () {
    test('updates an existing operation', () async {
      final op = SyncOperation.create(
        collection: 'users',
        entityId: 'u1',
        payload: {},
      );

      await queue.add(op);
      final updated = op.copyWith(retries: 2, status: SyncStatus.failed);
      await queue.update(updated);

      final result = queue.getAll().first;
      expect(result.retries, 2);
      expect(result.status, SyncStatus.failed);
    });

    test('does nothing when operation does not exist', () async {
      final op = SyncOperation.create(
        collection: 'users',
        entityId: 'u1',
        payload: {},
      );

      // update without adding first — should not throw
      await expectLater(queue.update(op), completes);
      expect(queue.length, 0);
    });
  });

  // ── getAll ───────────────────────────────────────────────

  group('getAll', () {
    test('returns operations sorted by priority descending', () async {
      final low = SyncOperation.create(
        collection: 'users',
        entityId: 'u1',
        payload: {},
        priority: 0,
      );
      final high = SyncOperation.create(
        collection: 'users',
        entityId: 'u2',
        payload: {},
        priority: 10,
      );

      await queue.add(low);
      await queue.add(high);

      final all = queue.getAll();
      expect(all.first.priority, 10);
      expect(all.last.priority, 0);
    });

    test('sorts by createdAt ascending when priority is equal', () async {
      final first = SyncOperation.create(
        collection: 'users',
        entityId: 'u1',
        payload: {},
      );

      await Future.delayed(const Duration(milliseconds: 5));

      final second = SyncOperation.create(
        collection: 'users',
        entityId: 'u2',
        payload: {},
      );

      await queue.add(second);
      await queue.add(first);

      final all = queue.getAll();
      expect(all.first.entityId, 'u1'); // older first
      expect(all.last.entityId, 'u2');
    });

    test('returns unmodifiable list', () async {
      final op = SyncOperation.create(
        collection: 'users',
        entityId: 'u1',
        payload: {},
      );

      await queue.add(op);

      final all = queue.getAll();
      final extra = SyncOperation.create(
        collection: 'users',
        entityId: 'u2',
        payload: {},
      );

      expect(() => (all as dynamic).add(extra), throwsUnsupportedError);
    });

    test('returns empty list when queue is empty', () {
      expect(queue.getAll(), isEmpty);
    });
  });

  // ── clear ────────────────────────────────────────────────

  group('clear', () {
    test('removes all operations', () async {
      await queue.add(SyncOperation.create(
        collection: 'users',
        entityId: 'u1',
        payload: {},
      ));
      await queue.add(SyncOperation.create(
        collection: 'users',
        entityId: 'u2',
        payload: {},
      ));

      await queue.clear();

      expect(queue.length, 0);
      expect(queue.isEmpty, true);
    });
  });

  // ── persistence ──────────────────────────────────────────

  group('persistence', () {
    test('restores operations from storage on initialize', () async {
      final storage = InMemoryStorageAdapter();
      final op = SyncOperation.create(
        collection: 'users',
        entityId: 'u1',
        payload: {'name': 'Alice'},
      );

      // Persist directly to storage
      await storage.save([op]);

      // New queue instance using same storage
      final restoredQueue = SyncQueue(storage: storage);
      await restoredQueue.initialize();

      expect(restoredQueue.length, 1);
      expect(restoredQueue.getAll().first.entityId, 'u1');
    });

    test('persists new operations across queue instances', () async {
      final storage = InMemoryStorageAdapter();
      final q1 = SyncQueue(storage: storage);

      await q1.add(SyncOperation.create(
        collection: 'users',
        entityId: 'u1',
        payload: {},
      ));

      // Simulate app restart with same storage
      final q2 = SyncQueue(storage: storage);
      await q2.initialize();

      expect(q2.length, 1);
    });

    test('clear also wipes storage', () async {
      final storage = InMemoryStorageAdapter();
      final q1 = SyncQueue(storage: storage);

      await q1.add(SyncOperation.create(
        collection: 'users',
        entityId: 'u1',
        payload: {},
      ));
      await q1.clear();

      final q2 = SyncQueue(storage: storage);
      await q2.initialize();

      expect(q2.length, 0);
    });
  });
}