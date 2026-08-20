class VideoSeekMetricsSnapshot {
  const VideoSeekMetricsSnapshot({
    required this.gestureUpdates,
    required this.targetFrameChanges,
    required this.seekRequests,
    required this.seekCompleted,
    required this.coalescedRequests,
    required this.meanSeekDuration,
    required this.medianSeekDuration,
    required this.p95SeekDuration,
    required this.maximumSeekDuration,
  });

  final int gestureUpdates;
  final int targetFrameChanges;
  final int seekRequests;
  final int seekCompleted;
  final int coalescedRequests;
  final Duration? meanSeekDuration;
  final Duration? medianSeekDuration;
  final Duration? p95SeekDuration;
  final Duration? maximumSeekDuration;

  bool get isEmpty =>
      gestureUpdates == 0 &&
      targetFrameChanges == 0 &&
      seekRequests == 0 &&
      seekCompleted == 0 &&
      coalescedRequests == 0;

  String formatForDebugLog() {
    String formatDuration(Duration? value) {
      if (value == null) return 'n/a';
      return '${value.inMicroseconds / Duration.microsecondsPerMillisecond}'
          ' ms';
    }

    return 'Scrub metrics: '
        'gesture updates: $gestureUpdates/s; '
        'target frames: $targetFrameChanges/s; '
        'seek requests: $seekRequests/s; '
        'seek completed: $seekCompleted/s; '
        'coalesced: $coalescedRequests; '
        'mean seek: ${formatDuration(meanSeekDuration)}; '
        'median seek: ${formatDuration(medianSeekDuration)}; '
        'p95 seek: ${formatDuration(p95SeekDuration)}; '
        'max seek: ${formatDuration(maximumSeekDuration)}';
  }
}

class VideoSeekMetrics {
  int _gestureUpdates = 0;
  int _targetFrameChanges = 0;
  int _seekRequests = 0;
  int _seekCompleted = 0;
  int _coalescedRequests = 0;
  final List<Duration> _seekDurations = <Duration>[];

  void recordGestureUpdate() => _gestureUpdates++;

  void recordTargetFrameChange() => _targetFrameChanges++;

  void recordSeekRequest() => _seekRequests++;

  void recordCoalescedRequest() => _coalescedRequests++;

  void recordSeekCompleted(Duration duration) {
    _seekCompleted++;
    _seekDurations.add(duration);
  }

  VideoSeekMetricsSnapshot takeSnapshot() {
    final durations = List<Duration>.of(_seekDurations)..sort();
    final snapshot = VideoSeekMetricsSnapshot(
      gestureUpdates: _gestureUpdates,
      targetFrameChanges: _targetFrameChanges,
      seekRequests: _seekRequests,
      seekCompleted: _seekCompleted,
      coalescedRequests: _coalescedRequests,
      meanSeekDuration: _meanDuration(durations),
      medianSeekDuration: _percentile(durations, 0.5),
      p95SeekDuration: _percentile(durations, 0.95),
      maximumSeekDuration: durations.isEmpty ? null : durations.last,
    );
    _gestureUpdates = 0;
    _targetFrameChanges = 0;
    _seekRequests = 0;
    _seekCompleted = 0;
    _coalescedRequests = 0;
    _seekDurations.clear();
    return snapshot;
  }

  Duration? _meanDuration(List<Duration> durations) {
    if (durations.isEmpty) return null;

    final totalMicroseconds = durations.fold<int>(
      0,
      (total, duration) => total + duration.inMicroseconds,
    );
    return Duration(microseconds: totalMicroseconds ~/ durations.length);
  }

  Duration? _percentile(List<Duration> sortedDurations, double percentile) {
    if (sortedDurations.isEmpty) return null;

    final index = ((sortedDurations.length - 1) * percentile).ceil();
    return sortedDurations[index];
  }
}
