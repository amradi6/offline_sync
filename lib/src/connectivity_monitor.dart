import 'dart:async';

/// Abstract interface for observing network connectivity changes.
///
/// Implement this class to bridge your platform's connectivity API
/// (e.g. `connectivity_plus` in Flutter) with [SyncEngine].
///
/// ```dart
/// class FlutterConnectivityMonitor implements ConnectivityMonitor {
///   final _connectivity = Connectivity();
///   final _controller = StreamController<bool>.broadcast();
///   bool _isOnline = false;
///
///   @override
///   Stream<bool> get isOnline => _controller.stream;
///
///   @override
///   bool get currentStatus => _isOnline;
///
///   @override
///   Future<void> start() async {
///     final result = await _connectivity.checkConnectivity();
///     _isOnline = result != ConnectivityResult.none;
///     _controller.add(_isOnline);
///     _connectivity.onConnectivityChanged.listen((result) {
///       final online = result != ConnectivityResult.none;
///       if (online != _isOnline) {
///         _isOnline = online;
///         _controller.add(_isOnline);
///       }
///     });
///   }
///
///   @override
///   Future<bool> checkNow() async {
///     final result = await _connectivity.checkConnectivity();
///     return result != ConnectivityResult.none;
///   }
///
///   @override
///   Future<void> dispose() => _controller.close();
/// }
/// ```
abstract class ConnectivityMonitor {
  /// A broadcast stream that emits `true` when the device comes online
  /// and `false` when it goes offline. Emits the current status on [start].
  Stream<bool> get isOnline;

  /// The last known connectivity status. Synchronous — safe to call anywhere.
  bool get currentStatus;

  /// Starts listening for connectivity changes and emits the initial status.
  Future<void> start();

  /// Performs an immediate connectivity check and returns the result.
  Future<bool> checkNow();

  /// Cancels all subscriptions and releases resources.
  Future<void> dispose();
}