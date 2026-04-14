import 'dart:async';
import 'connectivity_monitor.dart';

/// A [ConnectivityMonitor] that always reports the device as online.
///
/// Used as the default monitor in [OfflineSync] and [SyncEngine]
/// when no custom monitor is provided. Suitable for:
///
/// - Pure Dart environments where platform connectivity APIs are unavailable.
/// - Testing and example apps.
/// - Apps that don't need offline support but still want queued syncing.
///
/// For real offline detection in Flutter, implement [ConnectivityMonitor]
/// using `connectivity_plus` and inject it via [OfflineSync].
class AlwaysOnlineMonitor implements ConnectivityMonitor {
  final _controller = StreamController<bool>.broadcast();

  @override
  bool currentStatus = true;

  @override
  Stream<bool> get isOnline => _controller.stream;

  @override
  Future<void> start() async => _controller.add(true);

  @override
  Future<bool> checkNow() async => true;

  @override
  Future<void> dispose() async => _controller.close();
}