Duration frameDurationForFps(double fps) {
  if (!fps.isFinite || fps <= 0) {
    throw ArgumentError.value(fps, 'fps', 'must be finite and greater than 0');
  }

  return Duration(microseconds: (Duration.microsecondsPerSecond / fps).round());
}

int totalFramesForDuration({
  required Duration duration,
  required double fps,
}) {
  if (!fps.isFinite || fps <= 0 || duration <= Duration.zero) return 0;

  return (duration.inMicroseconds * fps / Duration.microsecondsPerSecond)
      .floor();
}

Duration frameToDuration(int frame, double fps) {
  if (!fps.isFinite || fps <= 0) {
    throw ArgumentError.value(fps, 'fps', 'must be finite and greater than 0');
  }

  return Duration(
    microseconds: (frame * Duration.microsecondsPerSecond / fps).round(),
  );
}

int durationToFrame(Duration position, double fps) {
  if (!fps.isFinite || fps <= 0) return 0;

  return (position.inMicroseconds * fps / Duration.microsecondsPerSecond)
      .round();
}

int clampFrameIndex(int frame, int totalFrames) {
  if (totalFrames <= 0) return 0;
  return frame.clamp(0, totalFrames);
}

double normalizedVideoPosition({
  required Duration position,
  required Duration duration,
}) {
  final durationUs = duration.inMicroseconds;
  if (durationUs <= 0) return 0;

  return (position.inMicroseconds / durationUs).clamp(0.0, 1.0);
}

Duration videoPositionFromNormalized({
  required double normalizedPosition,
  required Duration duration,
}) {
  final durationUs = duration.inMicroseconds;
  if (durationUs <= 0) return Duration.zero;
  if (!normalizedPosition.isFinite) {
    throw ArgumentError.value(
      normalizedPosition,
      'normalizedPosition',
      'must be finite',
    );
  }

  final clampedPosition = normalizedPosition.clamp(0.0, 1.0);
  return Duration(microseconds: (clampedPosition * durationUs).round());
}

Duration stepVideoPosition({
  required Duration position,
  required Duration duration,
  required double fps,
  required int direction,
}) {
  final durationUs = duration.inMicroseconds;
  if (durationUs <= 0) return Duration.zero;

  final frameDurationUs = frameDurationForFps(fps).inMicroseconds;
  final targetUs = (position.inMicroseconds + direction * frameDurationUs)
      .clamp(0, durationUs);
  return Duration(microseconds: targetUs);
}
