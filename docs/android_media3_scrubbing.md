# Android Media3 scrubbing experiment

## Scope and tested stack

This branch evaluates seek scheduling for the existing Flutter replay. It does
not change native capture, the saved trial model, or the logical definition of
take-off and landing frames.

| Component | Previous replay branch | This experiment |
| --- | --- | --- |
| `video_player` | 2.10.1 | 2.14.0 |
| `video_player_android` | 2.9.1 | 2.12.0 |
| `video_player_platform_interface` | 6.6.0 | 6.9.0 |
| Media3 | 1.8.0 | 1.9.2 |

`video_player_android` 2.12.0 declares Media3 1.9.2 for
`media3-exoplayer`, `media3-exoplayer-hls`, `media3-exoplayer-dash`,
`media3-exoplayer-rtsp`, and `media3-exoplayer-smoothstreaming`. No application
dependency overrides that version. The APK debug build succeeds with this
configuration.

The Flutter/Dart toolchain used here is Flutter 3.44.0 / Dart 3.12.0. The
public `video_player` API accepts `VideoPlayerOptions.backBufferDurationMs`, so
no direct dependency on `video_player_android` is necessary.

## Scheduler configuration

The current Android default is intentionally explicit:

```text
back buffer: 5,000 ms
preview seek limit: 8 seeks/s (125 ms, safe Pixel baseline)
continuous preview: enabled (no gesture debounce)
final seek: exact logical target, always sent on release
```

The values are centralized in
`lib/widgets/video_replay_configuration.dart`. They can be compared without a
source change:

```bash
# B: new backend only
flutter run -d <pixel-id> \
  --dart-define=ANDROID_REPLAY_BACK_BUFFER_MS=0 \
  --dart-define=ANDROID_REPLAY_MAX_SEEKS_PER_SECOND=0

# C: new backend + five-second back buffer
flutter run -d <pixel-id> \
  --dart-define=ANDROID_REPLAY_BACK_BUFFER_MS=5000 \
  --dart-define=ANDROID_REPLAY_MAX_SEEKS_PER_SECOND=0

# D8 (default): back buffer + last-request-wins + safe preview cap
flutter run -d <pixel-id> \
  --dart-define=ANDROID_REPLAY_BACK_BUFFER_MS=5000 \
  --dart-define=ANDROID_REPLAY_MAX_SEEKS_PER_SECOND=8

# D30: back buffer + last-request-wins + 30 Hz preview cap
flutter run -d <pixel-id> \
  --dart-define=ANDROID_REPLAY_BACK_BUFFER_MS=5000 \
  --dart-define=ANDROID_REPLAY_MAX_SEEKS_PER_SECOND=30

# D60: back buffer + last-request-wins + 60 Hz preview cap
flutter run -d <pixel-id> \
  --dart-define=ANDROID_REPLAY_BACK_BUFFER_MS=5000 \
  --dart-define=ANDROID_REPLAY_MAX_SEEKS_PER_SECOND=60
```

Configuration A is reproduced by checking out the replay branch before commit
`f3edb53` (`video_player_android` 2.9.1), with the previous no-back-buffer
scheduler. It should be tested on the same Pixel, video and scenario as B-D.

`backBufferDurationMs` configures ExoPlayer `DefaultLoadControl` with retained
media before the current playback position, kept from a keyframe. It can help
with local reverse movement (`500 -> 510 -> 505`), but it does not make a
seek exact, nor does it prevent MediaCodec flushes. The option is passed only
on Android; other supported platforms keep their default behavior.

## What the Dart scheduler guarantees

```text
gesture / slider update
        ↓
logical target frame (authoritative for the jump analysis)
        ↓
only the newest pending player position is retained
        ↓
at most one platform seek is active
        ↓
preview seek at the configured rate
        ↓
one exact final seek when the gesture ends
```

The logical frame, converted with microsecond timing, is the source of truth.
The transient position returned by ExoPlayer is never used to redefine the
take-off or landing frame. A slow or dropped preview image during a rapid swipe
therefore cannot alter the scientific calculation.

The throttle is a scheduling control: no fixed delay is inserted after
`seekTo()` to make Android "catch up", and the active jog gesture is not
debounced. A timeout releases the coordinator if a platform seek never
resolves. There is never a queue of obsolete seeks.

## Debug metrics and manual protocol

Debug builds print at most one aggregate line per second while scrubbing:

```text
Scrub metrics: gesture updates: …/s; target frames: …/s;
seek requests: …/s; seek completed: …/s; coalesced: …;
mean seek: … ms; median seek: … ms; p95 seek: … ms; max seek: … ms
```

Metrics are disabled in release builds. Record the output for each A-D run on
the Pixel 8a, then compare the same 30, 60, 120 and 240 fps videos and these
scenarios:

1. stepping `500 -> 501 -> 502 -> 503`;
2. local reversal `500 -> 510 -> 505 -> 515 -> 500`;
3. slow 10-20-frame scrub;
4. rapid traversal across several hundred frames;
5. abrupt direction change, then release.

For each run, verify that the final displayed target and the logical selected
frame agree. Compare the completed/requested ratio and seek-duration percentiles
alongside visual responsiveness; a high request rate alone is not a win if it
causes stale MediaCodec callbacks or a frozen preview.

No device metric is claimed yet for this branch: the debug APK was installed
and launched on the connected Pixel 8a, but the manual A-D replay gestures
could not be exercised from this environment. The protocol above makes the
comparison reproducible on the same device and videos.

## Media3 capability status

| Feature | Media3 1.9.2 | `video_player_android` 2.12.0 | Application |
| --- | --- | --- | --- |
| `ExoPlayer.setScrubbingModeEnabled` | supported | not exposed | not enabled |
| `ScrubbingModeParameters` | supported | not exposed | not configurable |
| `SeekParameters` / exact seek selection | supported | not exposed | not configurable |
| `backBufferDurationMs` | supported through load control | exposed | enabled on Android (5 s default) |

The actual plugin Pigeon API still forwards `seekTo` in **milliseconds**:
`Duration.inMilliseconds` reaches `ExoPlayer.seekTo(long)`. The Dart model uses
microseconds for its frame arithmetic, but Android rendering cannot represent a
sub-millisecond seek target through this plugin API.

An app-local `MethodChannel` cannot realistically toggle scrubbing mode on the
ExoPlayer instance already owned privately by `video_player_android`. The
minimal next phase is an upstream contribution or a maintained plugin patch:

```text
VideoPlayerController
  -> video_player platform interface / Pigeon
  -> video_player_android player instance
  -> ExoPlayer.setScrubbingModeEnabled(playerId, enabled)
```

Enable it for the active drag and turn it off only after the exact final seek.
Any exact-seek policy should be benchmarked separately because decoding from a
preceding keyframe may cost more than a normal preview seek.

## Result and recommendation

```text
video_player:
before: 2.10.1
after:  2.14.0

video_player_android:
before: 2.9.1
after:  2.12.0

Media3:
before: 1.8.0
after:  1.9.2 (declared by the Android backend, without app override)

backBufferDurationMs:
effect observed: enabled and ready for A-D comparison; no on-device latency
measurement recorded yet.

last-request-wins:
effect observed: unit-tested; only one active seek and one replaceable pending
target remain.

60 Hz throttle:
effect observed: on the Pixel 8a it displays a few preview frames, then the
hardware decoder stops updating. The default is therefore 8 Hz; 30/60 remain
explicit benchmark configurations.

scrubbing mode Media3:
available: yes
exposed by video_player: no
activated currently: no
```

Recommendation: **C/D must be benchmarked before declaring an upgrade
sufficient**. The upgrade enables an important back-buffer control, but cannot
by itself solve high-frequency decoder flushes. The first Pixel 8a D60 run was
unstable, so the default stays at 8 Hz. If the measured D30/D60 runs remain
unstable, choose **D. a small native `video_player_android` extension is
recommended**, rather than sending more Dart `seekTo()` calls.

## References

- [Media3 1.9.2 release notes](https://developer.android.com/jetpack/androidx/releases/media3#1.9.2)
- [ExoPlayer scrubbing API](https://developer.android.com/reference/androidx/media3/exoplayer/ExoPlayer#setScrubbingModeEnabled(boolean))
- [ScrubbingModeParameters](https://developer.android.com/reference/androidx/media3/exoplayer/ScrubbingModeParameters)
- [Flutter video_player source](https://github.com/flutter/packages/tree/main/packages/video_player)
