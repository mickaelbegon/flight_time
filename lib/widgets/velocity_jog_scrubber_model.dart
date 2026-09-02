import 'dart:math' as math;

class VelocityJogScrubberConfig {
  const VelocityJogScrubberConfig({
    this.precisionPixelsPerFrame = 18.0,
    this.accelerationStartVelocity = 150.0,
    this.accelerationFullVelocity = 1800.0,
    this.maxSecondsPerPixel = 0.003,
    this.velocitySmoothingAlpha = 0.25,
    this.accelerationExponent = 1.5,
    this.maxDecoderUpdatesPerSecond = 60,
    this.inertiaMinimumVelocity = 700.0,
    this.inertiaMaximumVelocity = 2400.0,
    this.inertiaStopVelocity = 45.0,
    this.inertiaDrag = 0.015,
    this.inertiaMaximumDuration = const Duration(milliseconds: 650),
    this.hapticMinimumInterval = const Duration(milliseconds: 40),
  })  : assert(precisionPixelsPerFrame > 0),
        assert(accelerationStartVelocity >= 0),
        assert(accelerationFullVelocity > accelerationStartVelocity),
        assert(maxSecondsPerPixel > 0),
        assert(
          velocitySmoothingAlpha > 0 && velocitySmoothingAlpha <= 1,
        ),
        assert(accelerationExponent > 0),
        assert(maxDecoderUpdatesPerSecond > 0),
        assert(inertiaMinimumVelocity >= 0),
        assert(inertiaMaximumVelocity >= inertiaMinimumVelocity),
        assert(inertiaStopVelocity >= 0),
        assert(inertiaDrag > 0 && inertiaDrag < 1);

  final double precisionPixelsPerFrame;
  final double accelerationStartVelocity;
  final double accelerationFullVelocity;
  final double maxSecondsPerPixel;
  final double velocitySmoothingAlpha;
  final double accelerationExponent;
  final double maxDecoderUpdatesPerSecond;
  final double inertiaMinimumVelocity;
  final double inertiaMaximumVelocity;
  final double inertiaStopVelocity;
  final double inertiaDrag;
  final Duration inertiaMaximumDuration;
  final Duration hapticMinimumInterval;

  Duration get decoderUpdateInterval => Duration(
        microseconds:
            (Duration.microsecondsPerSecond / maxDecoderUpdatesPerSecond)
                .round(),
      );
}

double secondsPerPixel({
  required double velocityPxPerSecond,
  required double fps,
  VelocityJogScrubberConfig config = const VelocityJogScrubberConfig(),
}) {
  if (!fps.isFinite || fps <= 0) {
    throw ArgumentError.value(fps, 'fps', 'must be finite and greater than 0');
  }

  final precisionSecondsPerPixel = 1 / (fps * config.precisionPixelsPerFrame);
  final speed = velocityPxPerSecond.abs();
  final normalizedSpeed = ((speed - config.accelerationStartVelocity) /
          (config.accelerationFullVelocity - config.accelerationStartVelocity))
      .clamp(0.0, 1.0);
  final curvedSpeed = math
      .pow(
        normalizedSpeed,
        config.accelerationExponent,
      )
      .toDouble();

  return precisionSecondsPerPixel +
      (config.maxSecondsPerPixel - precisionSecondsPerPixel) * curvedSpeed;
}

double framesForPixelDelta({
  required double pixelDelta,
  required double velocityPxPerSecond,
  required double fps,
  bool reverseDirection = false,
  VelocityJogScrubberConfig config = const VelocityJogScrubberConfig(),
}) {
  final direction = reverseDirection ? -1.0 : 1.0;
  return pixelDelta *
      secondsPerPixel(
        velocityPxPerSecond: velocityPxPerSecond,
        fps: fps,
        config: config,
      ) *
      fps *
      direction;
}

double smoothVelocity({
  required double previousVelocity,
  required double sampledVelocity,
  required bool hasPreviousSample,
  VelocityJogScrubberConfig config = const VelocityJogScrubberConfig(),
}) {
  if (!hasPreviousSample) return sampledVelocity;
  return previousVelocity * (1 - config.velocitySmoothingAlpha) +
      sampledVelocity * config.velocitySmoothingAlpha;
}

class FrameDeltaAccumulator {
  double _fractionalFrames = 0;

  double get fractionalFrames => _fractionalFrames;

  int add(double frameDelta) {
    if (!frameDelta.isFinite) return 0;

    _fractionalFrames += frameDelta;
    final wholeFrames = _fractionalFrames.truncate();
    _fractionalFrames -= wholeFrames;
    return wholeFrames;
  }

  void reset() {
    _fractionalFrames = 0;
  }
}
