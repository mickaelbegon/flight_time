import 'dart:async';

typedef VideoSeekCallback = Future<void> Function(Duration target);
typedef VideoSeekErrorCallback = void Function(
  Object error,
  StackTrace stackTrace,
);

class VideoSeekCoordinator {
  VideoSeekCoordinator({
    required VideoSeekCallback seek,
    required this.minimumInterval,
    VideoSeekErrorCallback? onError,
  })  : _seek = seek,
        _onError = onError,
        _clock = Stopwatch()..start();

  final VideoSeekCallback _seek;
  final VideoSeekErrorCallback? _onError;
  final Duration minimumInterval;
  final Stopwatch _clock;

  Duration? _pendingTarget;
  Duration? _lastDispatchTime;
  Future<void>? _activeSeek;
  Future<void>? _finalSeek;
  Timer? _throttleTimer;
  bool _disposed = false;
  bool _finalizing = false;

  int requestedSeekCount = 0;
  int dispatchedSeekCount = 0;
  int completedSeekCount = 0;
  int maxPendingSeekCount = 0;

  bool get isBusy =>
      _activeSeek != null ||
      _finalizing ||
      _pendingTarget != null ||
      _throttleTimer != null;

  Duration? get pendingTarget => _pendingTarget;

  void request(Duration target) {
    if (_disposed) return;

    requestedSeekCount++;
    _pendingTarget = target;
    maxPendingSeekCount = 1;
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
    _finalizing = true;
    _pendingTarget = null;
    _throttleTimer?.cancel();
    _throttleTimer = null;

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

      _lastDispatchTime = _clock.elapsed;
      dispatchedSeekCount++;
      await _seek(target);
      completedSeekCount++;
    } finally {
      _finalizing = false;
      _schedulePendingSeek();
    }
  }

  void _schedulePendingSeek() {
    if (_disposed ||
        _finalizing ||
        _pendingTarget == null ||
        _activeSeek != null ||
        _throttleTimer != null) {
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

    late final Future<void> operation;
    try {
      operation = _seek(target);
    } on Object catch (error, stackTrace) {
      _onError?.call(error, stackTrace);
      completedSeekCount++;
      _schedulePendingSeek();
      return;
    }

    _activeSeek = operation;
    operation.then<void>(
      (_) => _completeSeek(operation),
      onError: (Object error, StackTrace stackTrace) {
        _onError?.call(error, stackTrace);
        _completeSeek(operation);
      },
    );
  }

  void _completeSeek(Future<void> operation) {
    if (!identical(_activeSeek, operation)) return;

    _activeSeek = null;
    completedSeekCount++;
    _schedulePendingSeek();
  }

  void dispose() {
    _disposed = true;
    _pendingTarget = null;
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _clock.stop();
  }
}
