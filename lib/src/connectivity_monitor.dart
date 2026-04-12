import 'dart:async';

abstract class ConnectivityMonitor {
  Stream<bool> get isOnline;
  bool get currentStatus;
  Future<void> start();
  Future<bool> checkNow();
  Future<void> dispose();
}