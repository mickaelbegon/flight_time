import 'dart:math' as math;

/// A mode explicitly requested by the experiment user.
///
/// It is deliberately distinct from the capability advertised by Android and
/// from the mode ultimately negotiated by the camera session.
class CaptureRequest {
  const CaptureRequest({
    required this.width,
    required this.height,
    required this.fps,
  })  : assert(width > 0),
        assert(height > 0),
        assert(fps > 0);

  final int width;
  final int height;
  final int fps;

  String get label => '$width×$height @ $fps fps';
}

/// An exact resolution and frame-rate range advertised by Camera2.
class AdvertisedCaptureMode {
  const AdvertisedCaptureMode({
    required this.width,
    required this.height,
    required this.minimumFps,
    required this.maximumFps,
  })  : assert(width > 0),
        assert(height > 0),
        assert(minimumFps > 0),
        assert(maximumFps >= minimumFps);

  final int width;
  final int height;
  final int minimumFps;
  final int maximumFps;

  bool supports(int fps) => fps >= minimumFps && fps <= maximumFps;

  String get label => '$width×$height @ $minimumFps–$maximumFps fps';
}

/// The capture configuration selected by the native backend.
///
/// [captureFps] is a reported configuration value. It must not be presented
/// as a measured FPS until timestamps have been collected.
class NegotiatedCaptureMode {
  const NegotiatedCaptureMode({
    required this.request,
    required this.width,
    required this.height,
    required this.captureFps,
    required this.playbackFps,
    required this.isSlowMotion,
  })  : assert(width > 0),
        assert(height > 0),
        assert(captureFps > 0),
        assert(playbackFps > 0);

  final CaptureRequest request;
  final int width;
  final int height;
  final int captureFps;
  final int playbackFps;
  final bool isSlowMotion;

  SlowMotionTimeline get timeline => SlowMotionTimeline(
        captureFps: captureFps,
        playbackFps: playbackFps,
      );
}

/// Converts between physical capture frames and an encoded playback timeline.
class SlowMotionTimeline {
  const SlowMotionTimeline({
    required this.captureFps,
    required this.playbackFps,
  })  : assert(captureFps > 0),
        assert(playbackFps > 0);

  final int captureFps;
  final int playbackFps;

  Duration captureTimeForFrame(int frame) {
    if (frame < 0) {
      throw ArgumentError.value(frame, 'frame', 'must not be negative');
    }
    return Duration(
      microseconds:
          (frame * Duration.microsecondsPerSecond / captureFps).round(),
    );
  }

  Duration playbackPositionForFrame(int frame) {
    if (frame < 0) {
      throw ArgumentError.value(frame, 'frame', 'must not be negative');
    }
    return Duration(
      microseconds:
          (frame * Duration.microsecondsPerSecond / playbackFps).round(),
    );
  }

  int captureFrameForPlaybackPosition(Duration position) {
    if (position.isNegative) return 0;
    return (position.inMicroseconds *
            playbackFps /
            Duration.microsecondsPerSecond)
        .round();
  }
}

/// Summary calculated from native sensor timestamps after a recording.
class CaptureTimingReport {
  const CaptureTimingReport({
    required this.frameCount,
    required this.measuredFps,
    required this.meanIntervalMicroseconds,
    required this.medianIntervalMicroseconds,
    required this.standardDeviationMicroseconds,
    required this.minimumIntervalMicroseconds,
    required this.maximumIntervalMicroseconds,
    required this.estimatedDroppedFrames,
  });

  factory CaptureTimingReport.fromTimestamps({
    required Iterable<int> timestampsMicroseconds,
    required int expectedFps,
  }) {
    if (expectedFps <= 0) {
      throw ArgumentError.value(expectedFps, 'expectedFps', 'must be positive');
    }

    final timestamps = timestampsMicroseconds.toList(growable: false);
    if (timestamps.length < 2) {
      return CaptureTimingReport(
        frameCount: timestamps.length,
        measuredFps: 0,
        meanIntervalMicroseconds: 0,
        medianIntervalMicroseconds: 0,
        standardDeviationMicroseconds: 0,
        minimumIntervalMicroseconds: 0,
        maximumIntervalMicroseconds: 0,
        estimatedDroppedFrames: 0,
      );
    }

    final intervals = <int>[];
    for (var index = 1; index < timestamps.length; index++) {
      final interval = timestamps[index] - timestamps[index - 1];
      if (interval <= 0) {
        throw ArgumentError.value(
          timestampsMicroseconds,
          'timestampsMicroseconds',
          'must be strictly increasing',
        );
      }
      intervals.add(interval);
    }

    final mean =
        intervals.reduce((left, right) => left + right) / intervals.length;
    final sortedIntervals = [...intervals]..sort();
    final middle = sortedIntervals.length ~/ 2;
    final median = sortedIntervals.length.isOdd
        ? sortedIntervals[middle].toDouble()
        : (sortedIntervals[middle - 1] + sortedIntervals[middle]) / 2;
    final variance = intervals
            .map((interval) => math.pow(interval - mean, 2))
            .reduce((left, right) => left + right) /
        intervals.length;
    final expectedInterval = Duration.microsecondsPerSecond / expectedFps;
    final droppedFrames = intervals.fold<int>(0, (total, interval) {
      if (interval < expectedInterval * 1.5) return total;
      return total + math.max(0, (interval / expectedInterval).round() - 1);
    });

    return CaptureTimingReport(
      frameCount: timestamps.length,
      measuredFps: (timestamps.length - 1) *
          Duration.microsecondsPerSecond /
          (timestamps.last - timestamps.first),
      meanIntervalMicroseconds: mean,
      medianIntervalMicroseconds: median,
      standardDeviationMicroseconds: math.sqrt(variance),
      minimumIntervalMicroseconds: sortedIntervals.first,
      maximumIntervalMicroseconds: sortedIntervals.last,
      estimatedDroppedFrames: droppedFrames,
    );
  }

  final int frameCount;
  final double measuredFps;
  final double meanIntervalMicroseconds;
  final double medianIntervalMicroseconds;
  final double standardDeviationMicroseconds;
  final int minimumIntervalMicroseconds;
  final int maximumIntervalMicroseconds;
  final int estimatedDroppedFrames;
}
