import 'dart:async';

import 'package:flight_time/widgets/video_playback_timing.dart';
import 'package:flight_time/widgets/velocity_jog_scrubber_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

typedef FrameScrubEndCallback = Future<void> Function(int frameIndex);

class VelocityJogScrubber extends StatefulWidget {
  const VelocityJogScrubber({
    super.key,
    required this.fps,
    required this.duration,
    required this.frameIndex,
    required this.onFrameChanged,
    this.onScrubStart,
    this.onScrubEnd,
    this.config = const VelocityJogScrubberConfig(),
    this.enableInertia = true,
    this.enableHaptics = true,
    this.reverseDirection = false,
  });

  final double fps;
  final Duration duration;
  final int frameIndex;
  final ValueChanged<int> onFrameChanged;
  final VoidCallback? onScrubStart;
  final FrameScrubEndCallback? onScrubEnd;
  final VelocityJogScrubberConfig config;
  final bool enableInertia;
  final bool enableHaptics;
  final bool reverseDirection;

  @override
  State<VelocityJogScrubber> createState() => _VelocityJogScrubberState();
}

class _VelocityJogScrubberState extends State<VelocityJogScrubber>
    with SingleTickerProviderStateMixin {
  final FrameDeltaAccumulator _frameAccumulator = FrameDeltaAccumulator();

  late final Ticker _inertiaTicker;
  late int _currentFrame;
  Duration? _lastUpdateTimestamp;
  Duration? _lastHapticTimestamp;
  FrictionSimulation? _inertiaSimulation;
  double _lastInertiaPosition = 0;
  double _smoothedVelocity = 0;
  bool _hasVelocitySample = false;
  bool _dragging = false;
  bool _scrubSessionActive = false;
  bool _interruptedInertia = false;

  int get _totalFrames => totalFramesForDuration(
        duration: widget.duration,
        fps: widget.fps,
      );

  bool get _isEnabled =>
      widget.fps.isFinite && widget.fps > 0 && _totalFrames > 0;

  double get _visualFramePosition =>
      (_currentFrame + _frameAccumulator.fractionalFrames).clamp(
        0.0,
        _totalFrames.toDouble(),
      );

  @override
  void initState() {
    super.initState();
    _currentFrame = clampFrameIndex(widget.frameIndex, _totalFrames);
    _inertiaTicker = createTicker(_onInertiaTick);
  }

  @override
  void didUpdateWidget(VelocityJogScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && !_inertiaTicker.isActive) {
      final nextFrame = clampFrameIndex(widget.frameIndex, _totalFrames);
      if (_currentFrame != nextFrame) {
        _currentFrame = nextFrame;
        _frameAccumulator.reset();
      }
    }
    if (!widget.enableInertia && _inertiaTicker.isActive) {
      _stopInertia();
      unawaited(_finishScrub());
    }
  }

  @override
  void dispose() {
    _inertiaTicker.dispose();
    super.dispose();
  }

  void _beginScrub() {
    if (_scrubSessionActive) return;
    _scrubSessionActive = true;
    widget.onScrubStart?.call();
  }

  void _onDragDown(DragDownDetails details) {
    if (!_inertiaTicker.isActive) return;
    _stopInertia();
    _interruptedInertia = true;
    if (mounted) setState(() {});
  }

  void _onDragStart(DragStartDetails details) {
    if (!_isEnabled) return;

    _stopInertia();
    _interruptedInertia = false;
    _dragging = true;
    _lastUpdateTimestamp = details.sourceTimeStamp;
    _smoothedVelocity = 0;
    _hasVelocitySample = false;
    _frameAccumulator.reset();
    _beginScrub();
    setState(() {});
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragging || !_isEnabled) return;

    final delta = details.primaryDelta ?? details.delta.dx;
    if (delta == 0) return;

    final timestamp = details.sourceTimeStamp;
    final previousTimestamp = _lastUpdateTimestamp;
    final elapsed = timestamp != null && previousTimestamp != null
        ? timestamp - previousTimestamp
        : widget.config.decoderUpdateInterval;
    _lastUpdateTimestamp = timestamp;

    final elapsedSeconds = elapsed.inMicroseconds > 0
        ? elapsed.inMicroseconds / Duration.microsecondsPerSecond
        : widget.config.decoderUpdateInterval.inMicroseconds /
            Duration.microsecondsPerSecond;
    final sampledVelocity = delta / elapsedSeconds;
    _smoothedVelocity = smoothVelocity(
      previousVelocity: _smoothedVelocity,
      sampledVelocity: sampledVelocity,
      hasPreviousSample: _hasVelocitySample,
      config: widget.config,
    );
    _hasVelocitySample = true;

    _applyPixelDelta(delta, _smoothedVelocity);
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;

    final trackedVelocity = details.velocity.pixelsPerSecond.dx;
    final initialVelocity =
        trackedVelocity.isFinite ? trackedVelocity : _smoothedVelocity;
    final logicalVelocity =
        widget.reverseDirection ? -initialVelocity : initialVelocity;
    final canStartInertia = widget.enableInertia &&
        initialVelocity.abs() >= widget.config.inertiaMinimumVelocity &&
        !(_currentFrame == 0 && logicalVelocity < 0) &&
        !(_currentFrame == _totalFrames && logicalVelocity > 0);

    if (canStartInertia) {
      _startInertia(initialVelocity);
    } else {
      unawaited(_finishScrub());
    }
  }

  void _onDragCancel() {
    _dragging = false;
    if (_interruptedInertia || _scrubSessionActive) {
      _interruptedInertia = false;
      unawaited(_finishScrub());
    }
  }

  void _startInertia(double velocity) {
    final maximumVelocity = widget.config.inertiaMaximumVelocity;
    final clampedVelocity = velocity.clamp(
      -maximumVelocity,
      maximumVelocity,
    );
    _inertiaSimulation = FrictionSimulation(
      widget.config.inertiaDrag,
      0,
      clampedVelocity,
    );
    _lastInertiaPosition = 0;
    _inertiaTicker.start();
    if (mounted) setState(() {});
  }

  void _onInertiaTick(Duration elapsed) {
    final simulation = _inertiaSimulation;
    if (simulation == null) return;

    final elapsedSeconds =
        elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final position = simulation.x(elapsedSeconds);
    final velocity = simulation.dx(elapsedSeconds);
    final delta = position - _lastInertiaPosition;
    _lastInertiaPosition = position;

    final reachedBoundary = _applyPixelDelta(delta, velocity);
    final shouldStop = reachedBoundary ||
        velocity.abs() <= widget.config.inertiaStopVelocity ||
        elapsed >= widget.config.inertiaMaximumDuration ||
        simulation.isDone(elapsedSeconds);
    if (shouldStop) {
      _stopInertia();
      unawaited(_finishScrub());
    }
  }

  bool _applyPixelDelta(double pixelDelta, double velocity) {
    final frameDelta = framesForPixelDelta(
      pixelDelta: pixelDelta,
      velocityPxPerSecond: velocity,
      fps: widget.fps,
      reverseDirection: widget.reverseDirection,
      config: widget.config,
    );
    final wholeFrames = _frameAccumulator.add(frameDelta);
    var reachedBoundary = false;

    if (wholeFrames != 0) {
      final requestedFrame = _currentFrame + wholeFrames;
      final nextFrame = clampFrameIndex(requestedFrame, _totalFrames);
      reachedBoundary = nextFrame != requestedFrame;
      if (reachedBoundary) _frameAccumulator.reset();

      if (nextFrame != _currentFrame) {
        _currentFrame = nextFrame;
        widget.onFrameChanged(_currentFrame);
        _triggerHapticFeedback(velocity);
      }
    }

    if (mounted) setState(() {});
    return reachedBoundary;
  }

  void _triggerHapticFeedback(double velocity) {
    if (!widget.enableHaptics || _inertiaTicker.isActive) return;

    final speed = velocity.abs();
    if (speed >= widget.config.accelerationFullVelocity) return;
    if (speed >= widget.config.accelerationStartVelocity &&
        _currentFrame % 5 != 0) {
      return;
    }

    final now = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    final lastHapticTimestamp = _lastHapticTimestamp;
    if (lastHapticTimestamp != null &&
        now - lastHapticTimestamp < widget.config.hapticMinimumInterval) {
      return;
    }
    _lastHapticTimestamp = now;
    unawaited(HapticFeedback.selectionClick());
  }

  void _stopInertia() {
    if (_inertiaTicker.isActive) _inertiaTicker.stop();
    _inertiaSimulation = null;
    _lastInertiaPosition = 0;
  }

  Future<void> _finishScrub() async {
    if (!_scrubSessionActive) return;

    _stopInertia();
    _dragging = false;
    _interruptedInertia = false;
    _frameAccumulator.reset();
    _scrubSessionActive = false;
    if (mounted) setState(() {});

    await widget.onScrubEnd?.call(_currentFrame);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final timeSeconds = widget.fps.isFinite && widget.fps > 0
        ? _currentFrame / widget.fps
        : 0.0;

    return Semantics(
      label: 'Video jog wheel',
      value: 'Frame $_currentFrame, ${timeSeconds.toStringAsFixed(4)} seconds',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DefaultTextStyle(
            style: Theme.of(context).textTheme.labelLarge!.copyWith(
                  color: colorScheme.onSurface,
                ),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 18,
              runSpacing: 2,
              children: [
                Text('Frame $_currentFrame'),
                Text('${timeSeconds.toStringAsFixed(4)} s'),
                Text('${widget.fps.toStringAsFixed(0)} fps'),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 64,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: _isEnabled ? 0.9 : 0.45,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onHorizontalDragDown: _isEnabled ? _onDragDown : null,
                onHorizontalDragStart: _isEnabled ? _onDragStart : null,
                onHorizontalDragUpdate: _isEnabled ? _onDragUpdate : null,
                onHorizontalDragEnd: _isEnabled ? _onDragEnd : null,
                onHorizontalDragCancel: _isEnabled ? _onDragCancel : null,
                child: CustomPaint(
                  painter: _JogRulerPainter(
                    framePosition: _visualFramePosition,
                    totalFrames: _totalFrames,
                    pixelsPerFrame: widget.config.precisionPixelsPerFrame,
                    tickColor: colorScheme.onSurfaceVariant,
                    markerColor: colorScheme.primary,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JogRulerPainter extends CustomPainter {
  const _JogRulerPainter({
    required this.framePosition,
    required this.totalFrames,
    required this.pixelsPerFrame,
    required this.tickColor,
    required this.markerColor,
  });

  final double framePosition;
  final int totalFrames;
  final double pixelsPerFrame;
  final Color tickColor;
  final Color markerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final visibleFrameRadius = (centerX / pixelsPerFrame).ceil() + 1;
    final firstFrame = (framePosition.floor() - visibleFrameRadius).clamp(
      0,
      totalFrames,
    );
    final lastFrame = (framePosition.ceil() + visibleFrameRadius).clamp(
      0,
      totalFrames,
    );
    final minorInterval = pixelsPerFrame >= 8 ? 1 : 5;
    final mediumInterval = minorInterval == 1 ? 5 : 10;
    final majorInterval = minorInterval == 1 ? 10 : 20;
    final tickPaint = Paint()
      ..color = tickColor
      ..strokeCap = StrokeCap.round;

    for (var frame = firstFrame; frame <= lastFrame; frame++) {
      if (frame % minorInterval != 0) continue;

      final x = centerX + (frame - framePosition) * pixelsPerFrame;
      final isMajor = frame % majorInterval == 0;
      final isMedium = frame % mediumInterval == 0;
      final tickHeight = isMajor
          ? 27.0
          : isMedium
              ? 19.0
              : 11.0;
      tickPaint.strokeWidth = isMajor ? 2 : 1;
      canvas.drawLine(
        Offset(x, size.height - 8),
        Offset(x, size.height - 8 - tickHeight),
        tickPaint,
      );

      if (isMajor) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: '$frame',
            style: TextStyle(color: tickColor, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, 2),
        );
      }
    }

    final markerPaint = Paint()
      ..color = markerColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(centerX, 16),
      Offset(centerX, size.height - 4),
      markerPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(centerX - 6, 0)
        ..lineTo(centerX + 6, 0)
        ..lineTo(centerX, 8)
        ..close(),
      markerPaint,
    );
  }

  @override
  bool shouldRepaint(_JogRulerPainter oldDelegate) =>
      oldDelegate.framePosition != framePosition ||
      oldDelegate.totalFrames != totalFrames ||
      oldDelegate.pixelsPerFrame != pixelsPerFrame ||
      oldDelegate.tickColor != tickColor ||
      oldDelegate.markerColor != markerColor;
}
