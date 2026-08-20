import 'package:flight_time/widgets/video_playback_timing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('frameDurationForFps', () {
    const expectedDurationsUs = [
      (fps: 30.0, durationUs: 33333),
      (fps: 60.0, durationUs: 16667),
      (fps: 120.0, durationUs: 8333),
      (fps: 240.0, durationUs: 4167),
    ];

    for (final entry in expectedDurationsUs) {
      test('${entry.fps.toInt()} fps', () {
        expect(
          frameDurationForFps(entry.fps),
          Duration(microseconds: entry.durationUs),
        );
      });
    }

    test('rejects invalid frame rates', () {
      expect(() => frameDurationForFps(0), throwsArgumentError);
      expect(() => frameDurationForFps(double.nan), throwsArgumentError);
    });
  });

  group('frame and duration conversions', () {
    const expectedFrameOneUs = [
      (fps: 30.0, durationUs: 33333),
      (fps: 60.0, durationUs: 16667),
      (fps: 120.0, durationUs: 8333),
      (fps: 240.0, durationUs: 4167),
    ];

    for (final entry in expectedFrameOneUs) {
      test('${entry.fps.toInt()} fps', () {
        expect(
          frameToDuration(1, entry.fps),
          Duration(microseconds: entry.durationUs),
        );
        expect(durationToFrame(frameToDuration(1, entry.fps), entry.fps), 1);
      });
    }

    test('converts frame two at 240 fps without accumulating rounding', () {
      expect(frameToDuration(2, 240), const Duration(microseconds: 8333));
    });

    test('computes and clamps the last frame', () {
      expect(
        totalFramesForDuration(duration: const Duration(seconds: 2), fps: 240),
        480,
      );
      expect(clampFrameIndex(-1, 480), 0);
      expect(clampFrameIndex(481, 480), 480);
    });

    test('handles invalid fps and zero duration', () {
      expect(
        totalFramesForDuration(duration: Duration.zero, fps: 240),
        0,
      );
      expect(
        totalFramesForDuration(duration: const Duration(seconds: 1), fps: 0),
        0,
      );
      expect(durationToFrame(const Duration(seconds: 1), 0), 0);
      expect(() => frameToDuration(1, 0), throwsArgumentError);
    });
  });

  group('normalized position conversions', () {
    const duration = Duration(seconds: 2);

    test('converts a position to a normalized value and back', () {
      const position = Duration(microseconds: 8333);
      final normalized = normalizedVideoPosition(
        position: position,
        duration: duration,
      );

      expect(normalized, closeTo(0.0041665, 1e-10));
      expect(
        videoPositionFromNormalized(
          normalizedPosition: normalized,
          duration: duration,
        ),
        position,
      );
    });

    test('clamps positions to the video bounds', () {
      expect(
        normalizedVideoPosition(
          position: const Duration(microseconds: -1),
          duration: duration,
        ),
        0,
      );
      expect(
        normalizedVideoPosition(
          position: const Duration(seconds: 3),
          duration: duration,
        ),
        1,
      );
      expect(
        videoPositionFromNormalized(
          normalizedPosition: -0.1,
          duration: duration,
        ),
        Duration.zero,
      );
      expect(
        videoPositionFromNormalized(
          normalizedPosition: 1.1,
          duration: duration,
        ),
        duration,
      );
    });

    test('handles a zero or uninitialized duration', () {
      expect(
        normalizedVideoPosition(
          position: const Duration(seconds: 1),
          duration: Duration.zero,
        ),
        0,
      );
      expect(
        videoPositionFromNormalized(
          normalizedPosition: 0.5,
          duration: Duration.zero,
        ),
        Duration.zero,
      );
    });
  });

  group('stepVideoPosition', () {
    const duration = Duration(seconds: 2);
    const start = Duration(seconds: 1);
    const expectedStepsUs = [
      (fps: 30.0, durationUs: 33333),
      (fps: 60.0, durationUs: 16667),
      (fps: 120.0, durationUs: 8333),
      (fps: 240.0, durationUs: 4167),
    ];

    for (final entry in expectedStepsUs) {
      test('steps at ${entry.fps.toInt()} fps', () {
        expect(
          stepVideoPosition(
            position: start,
            duration: duration,
            fps: entry.fps,
            direction: 1,
          ),
          Duration(microseconds: start.inMicroseconds + entry.durationUs),
        );
        expect(
          stepVideoPosition(
            position: start,
            duration: duration,
            fps: entry.fps,
            direction: -1,
          ),
          Duration(microseconds: start.inMicroseconds - entry.durationUs),
        );
      });
    }

    test('clamps steps at the beginning and end', () {
      expect(
        stepVideoPosition(
          position: Duration.zero,
          duration: duration,
          fps: 240,
          direction: -1,
        ),
        Duration.zero,
      );
      expect(
        stepVideoPosition(
          position: duration,
          duration: duration,
          fps: 240,
          direction: 1,
        ),
        duration,
      );
    });

    test('handles a zero duration', () {
      expect(
        stepVideoPosition(
          position: Duration.zero,
          duration: Duration.zero,
          fps: 240,
          direction: 1,
        ),
        Duration.zero,
      );
    });
  });
}
