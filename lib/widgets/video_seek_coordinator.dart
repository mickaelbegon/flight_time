import 'dart:async';

import 'package:flight_time/widgets/video_seek_metrics.dart';

typedef VideoSeekCallback = Future<void> Function(Duration target);
typedef VideoSeekErrorCallback = void Function(
  Object error,
  StackTrace stackTrace,
);
typedef VideoSeekMetricsCallback = void Function(
  VideoSeekMetricsSnapshot metrics,
);

class VideoSeekCoordinator {
  VideoSeekCoordinator({
    required VideoSeekCallback seek,
    required this.minimumInterval,
    this.debounceInterval = Duration.zero,
    this.operationTimeout,
    VideoSeekErrorCallback? onError,
    VideoSeekMetricsCallback? onMetrics,
    this.metricsWindow = const Duration(seconds: 1),
  })  : _seek = seek,
        _onError = onError,
        _onMetrics = onMetrics,
        _metrics = onMetrics == null ? null : VideoSeekMetrics(),
        _clock = Stopwatch()..start(),
        assert(debounceInterval >= Duration.zero),
        assert(operationTimeout == null || operationTimeout > Duration.zero),
        assert(metricsWindow > Duration.zero) {
    if (_metrics != null) {
      _metricsTimer = Timer.periodic(metricsWindow, (_) => _emitMetrics());
    }
  }

  final VideoSeekCallback _seek;
  final VideoSeekErrorCallback? _onError;
  final VideoSeekMetricsCallback? _onMetrics;
  final Duration minimumInterval;
  final Duration debounceInterval;
  final Duration? operationTimeout;
  final Duration metricsWindow;
  final Stopwatch _clock;
  final VideoSeekMetrics? _metrics;

  Duration? _pendingTarget;
  Duration? _lastDispatchTime;
  Duration? _lastCompletedTarget;
  Future<void>? _activeSeek;
  Future<void>? _finalSeek;
  Timer? _throttleTimer;
  Timer? _debounceTimer;
  Timer? _metricsTimer;
  bool _disposed = false;
  bool _finalizing = false;

  int requestedSeekCount = 0;
  int dispatchedSeekCount = 0;
  int completedSeekCount = 0;
  int coalescedSeekCount = 0;
  int maxPendingSeekCount = 0;

  bool get isBusy =>
      _activeSeek != null ||
      _finalizing ||
      _pendingTarget != null ||
      _throttleTimer != null ||
      _debounceTimer != null;

  Duration? get pendingTarget => _pendingTarget;

  void invalidateLastCompletedTarget() {
    _lastCompletedTarget = null;
  }

  void recordGestureUpdate() {
    _metrics?.recordGestureUpdate();
  }

  void recordTargetFrameChange() {
    _metrics?.recordTargetFrameChange();
  }

  void request(Duration target, {bool debounce = false}) {
    if (_disposed) return;

    requestedSeekCount++;
    if (_pendingTarget != null) _recordCoalescedRequest();
    _pendingTarget = target;
    maxPendingSeekCount = 1;

    if (debounce && debounceInterval > Duration.zero) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounceInterval, () {
        _debounceTimer = null;
        _schedulePendingSeek();
      });
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = null;
    _schedulePendingSeek();
  }

  Future<void> requestFinal(Duration target) async {
    if (_disposed) return;

    final previousFinalSeek = _finalSeek;
    if (previousFinalSeek != null) {
      try {
        await previousFinalSeek;
      } on Object {
        // The newest final target still has to be attempted.
      }
    }
    if (_disposed) return;

    final operation = _performFinalSeek(target);
    _finalSeek = operation;
    try {
      await operation;
    } finally {
      if (identical(_finalSeek, operation)) _finalSeek = null;
    }
  }

  Future<void> _performFinalSeek(Duration target) async {
    requestedSeekCount++;
    if (_pendingTarget != null) _recordCoalescedRequest();
    _finalizing = true;
    _pendingTarget = null;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;

    try {
      final activeSeek = _activeSeek;
      if (activeSeek != null) {
        try {
          await activeSeek;
        } on Object {
          // A stale failed seek must not prevent the exact final seek.
        }
      }
      if (_disposed) return;

      if (_lastCompletedTarget == target) return;

      await _waitForDispatchWindow();
      if (_disposed) return;

      _lastDispatchTime = _clock.elapsed;
      dispatchedSeekCount++;
      _metrics?.recordSeekRequest();
      final startedAt = _clock.elapsed;
      await _seekWithTimeout(target);
      _lastCompletedTarget = target;
      completedSeekCount++;
      _metrics?.recordSeekCompleted(_clock.elapsed - startedAt);
    } finally {
      _finalizing = false;
      _schedulePendingSeek();
    }
  }

  Future<void> _seekWithTimeout(Duration target) {
    final operation = _seek(target);
    final timeout = operationTimeout;
    return timeout == null ? operation : operation.timeout(timeout);
  }

  Future<void> _waitForDispatchWindow() async {
    final lastDispatchTime = _lastDispatchTime;
    if (lastDispatchTime == null || minimumInterval <= Duration.zero) return;

    final elapsedSinceDispatch = _clock.elapsed - lastDispatchTime;
    final remainingDelay = minimumInterval - elapsedSinceDispatch;
    if (remainingDelay > Duration.zero) {
      await Future<void>.delayed(remainingDelay);
    }
  }

  void _schedulePendingSeek() {
    if (_disposed ||
        _finalizing ||
        _pendingTarget == null ||
        _activeSeek != null ||
        _throttleTimer != null ||
        _debounceTimer != null) {
      return;
    }

    final lastDispatchTime = _lastDispatchTime;
    if (lastDispatchTime == null || minimumInterval <= Duration.zero) {
      _dispatchPendingSeek();
      return;
    }

    final elapsedSinceDispatch = _clock.elapsed - lastDispatchTime;
    final remainingDelay = minimumInterval - elapsedSinceDispatch;
    if (remainingDelay <= Duration.zero) {
      _dispatchPendingSeek();
      return;
    }

    _throttleTimer = Timer(remainingDelay, () {
      _throttleTimer = null;
      _dispatchPendingSeek();
    });
  }

  void _dispatchPendingSeek() {
    if (_disposed || _finalizing || _activeSeek != null) return;

    final target = _pendingTarget;
    if (target == null) return;
    _pendingTarget = null;
    _lastDispatchTime = _clock.elapsed;
    dispatchedSeekCount++;
    _metrics?.recordSeekRequest();
    final startedAt = _clock.elapsed;

    late final Future<void> operation;
    try {
      operation = _seekWithTimeout(target);
    } on Object catch (error, stackTrace) {
      _onError?.call(error, stackTrace);
      completedSeekCount++;
      _schedulePendingSeek();
      return;
    }

    _activeSeek = operation;
    operation.then<void>(
      (_) => _completeSeek(
        operation,
        target: target,
        succeeded: true,
        duration: _clock.elapsed - startedAt,
      ),
      onError: (Object error, StackTrace stackTrace) {
        _onError?.call(error, stackTrace);
        _completeSeek(
          operation,
          target: target,
          succeeded: false,
          duration: _clock.elapsed - startedAt,
        );
      },
    );
  }

  void _completeSeek(
    Future<void> operation, {
    required Duration target,
    required bool succeeded,
    required Duration duration,
  }) {
    if (!identical(_activeSeek, operation)) return;

    _activeSeek = null;
    if (succeeded) {
      _lastCompletedTarget = target;
      _metrics?.recordSeekCompleted(duration);
    }
    completedSeekCount++;
    _schedulePendingSeek();
  }

  void dispose() {
    _disposed = true;
    _pendingTarget = null;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _metricsTimer?.cancel();
    _metricsTimer = null;
    _clock.stop();
  }

  void _emitMetrics() {
    final metrics = _metrics;
    if (_disposed || metrics == null) return;

    final snapshot = metrics.takeSnapshot();
    if (!snapshot.isEmpty) _onMetrics?.call(snapshot);
  }

  void _recordCoalescedRequest() {
    coalescedSeekCount++;
    _metrics?.recordCoalescedRequest();
  }
}
