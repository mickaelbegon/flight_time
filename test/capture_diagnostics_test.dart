import 'package:flight_time/experimental_capture/capture_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdvertisedCaptureMode', () {
    const mode = AdvertisedCaptureMode(
      width: 1280,
      height: 720,
      minimumFps: 120,
      maximumFps: 240,
    );

    test('only accepts frame rates inside its exact advertised range', () {
      expect(mode.supports(60), isFalse);
      expect(mode.supports(120), isTrue);
      expect(mode.supports(240), isTrue);
      expect(mode.supports(241), isFalse);
    });
  });

  group('SlowMotionTimeline', () {
    const timeline = SlowMotionTimeline(captureFps: 240, playbackFps: 30);

    test('keeps capture time and playback time distinct', () {
      expect(timeline.captureTimeForFrame(240), const Duration(seconds: 1));
      expect(
          timeline.playbackPositionForFrame(240), const Duration(seconds: 8));
    });

    test('converts a playback position back to its capture frame', () {
      expect(
          timeline.captureFrameForPlaybackPosition(const Duration(seconds: 8)),
          240);
    });

    test('computes one second at 30, 60, 120 and 240 fps', () {
      for (final fps in [30, 60, 120, 240]) {
        final timeline = SlowMotionTimeline(captureFps: fps, playbackFps: 30);
        expect(timeline.captureTimeForFrame(fps), const Duration(seconds: 1));
      }
    });
  });

  group('CaptureTimingReport', () {
    test('computes an exact 240 fps sequence', () {
      final report = CaptureTimingReport.fromTimestamps(
        timestampsMicroseconds: [0, 4167, 8333, 12500, 16667],
        expectedFps: 240,
      );

      expect(report.frameCount, 5);
      expect(report.measuredFps, closeTo(240, 0.1));
      expect(report.medianIntervalMicroseconds, 4167);
      expect(report.estimatedDroppedFrames, 0);
    });

    test('estimates dropped frames from a timestamp gap', () {
      final report = CaptureTimingReport.fromTimestamps(
        timestampsMicroseconds: [0, 4167, 12500, 16667],
        expectedFps: 240,
      );

      expect(report.estimatedDroppedFrames, 1);
      expect(report.maximumIntervalMicroseconds, 8333);
    });

    test('rejects non-increasing timestamps', () {
      expect(
        () => CaptureTimingReport.fromTimestamps(
          timestampsMicroseconds: [0, 4167, 4167],
          expectedFps: 240,
        ),
        throwsArgumentError,
      );
    });
  });
}
