import 'package:flight_time/widgets/velocity_jog_scrubber_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = VelocityJogScrubberConfig();

  group('FrameDeltaAccumulator', () {
    test('preserves small movements until a whole frame is crossed', () {
      final accumulator = FrameDeltaAccumulator();

      expect(accumulator.add(0.2), 0);
      expect(accumulator.add(0.3), 0);
      expect(accumulator.add(0.49), 0);
      expect(accumulator.add(0.02), 1);
      expect(accumulator.fractionalFrames, closeTo(0.01, 1e-10));
    });

    test('accumulates negative movement symmetrically', () {
      final accumulator = FrameDeltaAccumulator();

      expect(accumulator.add(-0.6), 0);
      expect(accumulator.add(-0.5), -1);
      expect(accumulator.fractionalFrames, closeTo(-0.1, 1e-10));
    });
  });

  group('velocity mapping', () {
    test('moves one frame per precisionPixelsPerFrame at low speed', () {
      for (final fps in [30.0, 60.0, 120.0, 240.0]) {
        expect(
          framesForPixelDelta(
            pixelDelta: config.precisionPixelsPerFrame,
            velocityPxPerSecond: 0,
            fps: fps,
            config: config,
          ),
          closeTo(1, 1e-10),
        );
      }
    });

    test('accelerates progressively with swipe velocity', () {
      final slow = secondsPerPixel(
        velocityPxPerSecond: 100,
        fps: 240,
        config: config,
      );
      final medium = secondsPerPixel(
        velocityPxPerSecond: 900,
        fps: 240,
        config: config,
      );
      final fast = secondsPerPixel(
        velocityPxPerSecond: 1800,
        fps: 240,
        config: config,
      );

      expect(slow, lessThan(medium));
      expect(medium, lessThan(fast));
      expect(fast, closeTo(config.maxSecondsPerPixel, 1e-12));
    });

    test('is continuous at both acceleration thresholds', () {
      const epsilon = 1e-6;
      for (final threshold in [
        config.accelerationStartVelocity,
        config.accelerationFullVelocity,
      ]) {
        final before = secondsPerPixel(
          velocityPxPerSecond: threshold - epsilon,
          fps: 240,
          config: config,
        );
        final after = secondsPerPixel(
          velocityPxPerSecond: threshold + epsilon,
          fps: 240,
          config: config,
        );
        expect((after - before).abs(), lessThan(1e-8));
      }
    });

    test('has equivalent temporal travel at high speed for every fps', () {
      for (final fps in [30.0, 60.0, 120.0, 240.0]) {
        final frameDelta = framesForPixelDelta(
          pixelDelta: 100,
          velocityPxPerSecond: config.accelerationFullVelocity,
          fps: fps,
          config: config,
        );
        expect(frameDelta / fps, closeTo(0.3, 1e-10));
      }
    });

    test('supports direction inversion', () {
      final forward = framesForPixelDelta(
        pixelDelta: 18,
        velocityPxPerSecond: 0,
        fps: 240,
      );
      final reversed = framesForPixelDelta(
        pixelDelta: 18,
        velocityPxPerSecond: 0,
        fps: 240,
        reverseDirection: true,
      );

      expect(reversed, -forward);
    });
  });

  test('smoothVelocity applies exponential smoothing', () {
    expect(
      smoothVelocity(
        previousVelocity: 100,
        sampledVelocity: 500,
        hasPreviousSample: true,
        config: config,
      ),
      200,
    );
  });
}
