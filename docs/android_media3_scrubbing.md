# Android Media3 scrubbing: phase 2 note

## Current stack

The resolved playback stack for this branch is:

- `video_player` 2.10.1;
- `video_player_android` 2.9.1;
- AndroidX Media3 1.8.0.

Media3 1.8.0 includes `ExoPlayer.setScrubbingModeEnabled`,
`ScrubbingModeParameters`, and `SeekParameters`. Scrubbing mode is intended for
short periods with many frequent seeks and can reduce decoder resets or flushes.

The current Flutter plugin does not expose those APIs. Its Pigeon interface
only forwards `seekTo`, and the Dart Android implementation converts the target
with `Duration.inMilliseconds` before calling `ExoPlayer.seekTo(long)`.
Consequently, the Dart application cannot enable Media3 scrubbing mode or
select `SeekParameters.EXACT` for the plugin-owned player instance.

## Smallest robust phase 2

The narrowest native change is an upstream contribution or a maintained plugin
patch, rather than an application MethodChannel that tries to reach private
plugin state:

```text
VideoPlayerController
  -> video_player platform interface / Pigeon
  -> video_player_android player instance
  -> ExoPlayer.setScrubbingModeEnabled(true or false)
```

Add a per-player Pigeon method such as
`setScrubbingModeEnabled(playerId, enabled)`. Enable it when the jog drag starts
and disable it only after the exact final seek. If exact seeking is also added,
save the previous seek parameters, set `SeekParameters.EXACT` for the final
selection, then restore the previous value.

This should be benchmarked on real Android hardware. Exact seeks may decode
from an earlier keyframe and can be expensive, while Media3 scrubbing mode is
an unstable API and intentionally consumes more resources during interaction.

## References

- [Media3 1.8.0 release notes](https://developer.android.com/jetpack/androidx/releases/media3#1.8.0)
- [ExoPlayer scrubbing API](https://developer.android.com/reference/androidx/media3/exoplayer/ExoPlayer#setScrubbingModeEnabled(boolean))
- [ScrubbingModeParameters](https://developer.android.com/reference/androidx/media3/exoplayer/ScrubbingModeParameters)
- [Flutter video_player source](https://github.com/flutter/packages/tree/main/packages/video_player)
