#!/usr/bin/env python3
"""Inspect an experimental Nitro Camera recording outside the Flutter app.

This script deliberately reports the MP4 playback timeline separately from
the requested capture frame rate. A slow-motion MP4 can be nominally 30 fps
while containing frames captured at 120 or 240 fps.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path


def run(*args: str) -> str:
    return subprocess.run(args, check=True, text=True, capture_output=True).stdout


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("video", type=Path, help="MP4 captured by the experiment")
    result.add_argument(
        "--capture-fps",
        type=float,
        required=True,
        help="reported Camera2 capture FPS (for example 120 or 240)",
    )
    return result


def main() -> int:
    args = parser().parse_args()
    if args.capture_fps <= 0:
        parser().error("--capture-fps must be positive")
    if not args.video.is_file():
        parser().error(f"video does not exist: {args.video}")
    if shutil.which("ffprobe") is None or shutil.which("ffmpeg") is None:
        parser().error("ffprobe and ffmpeg must be available on PATH")

    probe = json.loads(
        run(
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-count_frames",
            "-show_entries",
            "stream=codec_name,width,height,avg_frame_rate,r_frame_rate,nb_read_frames,duration,bit_rate",
            "-of",
            "json",
            str(args.video),
        )
    )
    streams = probe.get("streams", [])
    if not streams:
        raise RuntimeError("no video stream found")
    stream = streams[0]

    # framemd5 hashes decoded frames. Consecutive identical hashes are only a
    # coarse diagnostic: a static scene can legitimately contain duplicates.
    framemd5 = run(
        "ffmpeg",
        "-v",
        "error",
        "-i",
        str(args.video),
        "-map",
        "0:v:0",
        "-f",
        "framemd5",
        "-",
    )
    hashes = []
    for line in framemd5.splitlines():
        if not line or line.startswith("#"):
            continue
        fields = [field.strip() for field in line.split(",")]
        if len(fields) >= 6:
            hashes.append(fields[-1])
    exact_duplicate_pairs = sum(
        before == after for before, after in zip(hashes, hashes[1:])
    )

    frame_count = int(stream.get("nb_read_frames") or len(hashes))
    report = {
        "file": str(args.video),
        "reportedCaptureFps": args.capture_fps,
        "captureDurationFromFrameCountSeconds": frame_count / args.capture_fps,
        "mp4PlaybackTimeline": {
            "codec": stream.get("codec_name"),
            "width": int(stream.get("width") or 0),
            "height": int(stream.get("height") or 0),
            "avgFrameRate": stream.get("avg_frame_rate"),
            "realFrameRate": stream.get("r_frame_rate"),
            "durationSeconds": float(stream.get("duration") or 0),
            "bitRate": int(stream.get("bit_rate") or 0),
            "frameCount": frame_count,
        },
        "decodedFrameHashDiagnostics": {
            "frameCount": len(hashes),
            "consecutiveExactDuplicatePairs": exact_duplicate_pairs,
            "warning": (
                "Exact decoded-frame hashes are a coarse indicator only; use a "
                "moving target and Camera2 timestamps to assess real capture FPS."
            ),
        },
    }
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        sys.stderr.write(error.stderr)
        raise SystemExit(error.returncode) from error
