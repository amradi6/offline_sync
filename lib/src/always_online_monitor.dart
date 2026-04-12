import 'dart:async';
import 'connectivity_monitor.dart';

class AlwaysOnlineMonitor implements ConnectivityMonitor {
  final _controller = StreamController<bool>.broadcast();

  @override
  bool currentStatus = true;

  @override
  Stream<bool> get isOnline => _controller.stream;

  @override
  Future<void> start() async {
    _controller.add(true);
  }

  @override
  Future<bool> checkNow() async => true;

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}