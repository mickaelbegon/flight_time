import 'dart:io';

import 'package:video_player/video_player.dart';

/// Amount of decoded media retained behind the current Android position.
///
/// This can help with short back-and-forth seeks near the current position. It
/// does not make seeks frame accurate and does not remove the need to
/// coalesce them before they reach the Android decoder.
const androidReplayBackBufferDurationMs = int.fromEnvironment(
  'ANDROID_REPLAY_BACK_BUFFER_MS',
  defaultValue: 5000,
);

/// Maximum number of preview seeks sent to the Android player per second.
///
/// Pass `--dart-define=ANDROID_REPLAY_MAX_SEEKS_PER_SECOND=0` to benchmark
/// last-request-wins without an explicit rate limit, or set it to 30 or 60 for
/// explicit experiments. Eight seeks per second is the safe Pixel baseline:
/// `seekTo` completion does not wait for a decoded frame.
const androidReplayMaximumSeeksPerSecond = int.fromEnvironment(
  'ANDROID_REPLAY_MAX_SEEKS_PER_SECOND',
  defaultValue: 8,
);

const androidReplaySeekTimeout = Duration(seconds: 1);

Duration androidReplaySeekMinimumInterval() {
  if (androidReplayMaximumSeeksPerSecond <= 0) return Duration.zero;

  return Duration(
    microseconds:
        Duration.microsecondsPerSecond ~/ androidReplayMaximumSeeksPerSecond,
  );
}

VideoPlayerOptions replayVideoPlayerOptions() {
  return VideoPlayerOptions(
    backBufferDurationMs:
        Platform.isAndroid ? androidReplayBackBufferDurationMs : null,
  );
}
