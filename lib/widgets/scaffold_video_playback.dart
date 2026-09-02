import 'dart:async';
import 'dart:io';

import 'package:flight_time/models/athletes.dart';
import 'package:flight_time/models/file_manager.dart';
import 'package:flight_time/models/text_manager.dart';
import 'package:flight_time/models/video_meta_data.dart';
import 'package:flight_time/widgets/helpers.dart';
import 'package:flight_time/widgets/save_trial_dialog.dart';
import 'package:flight_time/widgets/translatable_text.dart';
import 'package:flight_time/widgets/video_playback_timing.dart';
import 'package:flight_time/widgets/video_replay_configuration.dart';
import 'package:flight_time/widgets/video_seek_coordinator.dart';
import 'package:flight_time/widgets/video_seek_metrics.dart';
import 'package:flight_time/widgets/velocity_jog_scrubber.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

enum FpsOptions {
  fps30,
  fps60,
  fps120,
  fps240;

  double get value {
    switch (this) {
      case FpsOptions.fps30:
        return 30.0;
      case FpsOptions.fps60:
        return 60.0;
      case FpsOptions.fps120:
        return 120.0;
      case FpsOptions.fps240:
        return 240.0;
    }
  }

  @override
  String toString() {
    switch (this) {
      case FpsOptions.fps30:
        return '30';
      case FpsOptions.fps60:
        return '60';
      case FpsOptions.fps120:
        return '120';
      case FpsOptions.fps240:
        return '240';
    }
  }
}

class _VideoPlaybackWatcher {
  Duration start;
  Duration end;

  FpsOptions fps;

  _VideoPlaybackWatcher({
    required this.start,
    required this.end,
    required this.fps,
  });
}

class ScaffoldVideoPlayback extends StatefulWidget {
  const ScaffoldVideoPlayback({
    super.key,
    required this.controller,
    required this.filePath,
    required this.onWaitForControllerReady,
    this.videoMetaData,
  });

  final VideoPlayerController controller;
  final String filePath;
  final VideoMetaData? videoMetaData;
  final Future<void> Function() onWaitForControllerReady;

  @override
  State<ScaffoldVideoPlayback> createState() => _ScaffoldVideoPlaybackState();
}

class _ScaffoldVideoPlaybackState extends State<ScaffoldVideoPlayback> {
  bool get _isVideoNew =>
      _metaData == null || (_metaData?.isFromCorrupted ?? false);
  late VideoMetaData? _metaData = widget.videoMetaData;

  bool _canPop = false;
  late bool _canSave = _isVideoNew;

  late String? _athleteName = _metaData?.athlete.name;
  late String? _trialName = _metaData?.trialName;

  late final _videoPlaybackWatcher = _VideoPlaybackWatcher(
    start: _metaData?.timeJumpStarts ?? Duration.zero,
    end: _metaData?.timeJumpEnds ?? widget.controller.value.duration,
    fps: FpsOptions.fps30,
  );

  final _videoPlaybackWatcherCompleter = Completer<void>();
  bool _completionObserved = false;
  bool _playbackReachedEnd = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handlePlaybackCompletion);
    widget.controller.seekTo(_videoPlaybackWatcher.start);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final preferences = await SharedPreferences.getInstance();
      final fps = preferences.getDouble('fps') ?? FpsOptions.fps30.value;
      if (!mounted) return;
      _videoPlaybackWatcher.fps = FpsOptions.values.firstWhere(
        (element) => element.value == fps,
        orElse: () => FpsOptions.fps30,
      );
      _videoPlaybackWatcherCompleter.complete();
      setState(() {});
    });
    _showWarningMessage();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handlePlaybackCompletion);
    super.dispose();
  }

  @override
  void didUpdateWidget(ScaffoldVideoPlayback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;

    oldWidget.controller.removeListener(_handlePlaybackCompletion);
    widget.controller.addListener(_handlePlaybackCompletion);
    _completionObserved = widget.controller.value.isCompleted;
  }

  void _handlePlaybackCompletion() {
    final completed = widget.controller.value.isCompleted;
    if (!completed) {
      _completionObserved = false;
      return;
    }
    if (_completionObserved) return;

    _completionObserved = true;
    _playbackReachedEnd = true;
  }

  Future<void> _prepareManualSeek() async {
    await widget.onWaitForControllerReady();
    _playbackReachedEnd = false;
  }

  Future<void> _showWarningMessage() async {
    final preferences = await SharedPreferences.getInstance();
    final showWarning = preferences.getBool('showFpsWarning') ?? true;
    if (!showWarning) return;

    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => PopScope(
          onPopInvokedWithResult: (didPop, result) {
            preferences.setBool('showFpsWarning', false);
          },
          child: AlertDialog(
            title: TranslatableText(TextManager.instance.fpsWarningTitle),
            content: TranslatableText(TextManager.instance.fpsWarningDetails),
            actions: [
              TextButton(
                onPressed: () {
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: TranslatableText(TextManager.instance.confirm),
              ),
            ],
          ),
        ),
      );
    });
  }

  Future<void> _onChangedFps(FpsOptions fps) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble('fps', fps.value);
    if (!mounted) return;
    _videoPlaybackWatcher.fps = fps;
    setState(() {});
  }

  Future<void> _onSaveVideo() async {
    final response = _isVideoNew
        ? await showDialog<Map<String, String>?>(
            context: context,
            builder: (context) => SaveTrialDialog(),
          )
        : {'athlete': _metaData!.athlete.name, 'trial': _metaData!.trialName};
    if (!mounted || response == null) return;

    _athleteName = response['athlete'];
    _trialName = response['trial'];

    _canSave = false;
    setState(() {});
    await _manageFileSaving();
  }

  void _onUpdateJumpTime() async {
    _canSave = true;
    setState(() {});
  }

  Future<void> _onPlay() async {
    await widget.onWaitForControllerReady();
    if (!mounted) return;

    final value = widget.controller.value;
    final reachedEnd =
        value.duration > Duration.zero && value.position >= value.duration;
    if (_playbackReachedEnd || value.isCompleted || reachedEnd) {
      // video_player also pauses and seeks when it emits its completion event.
      // Serialize our replay command after that transition so its internal seek
      // cannot move the video back to the end after playback has restarted.
      await widget.controller.pause();
      if (!mounted) return;
      await widget.controller.seekTo(_videoPlaybackWatcher.start);
      if (!mounted) return;
      _playbackReachedEnd = false;
    }

    await widget.controller.play();
    if (mounted) setState(() {});
  }

  Future<void> _onPause() async {
    await widget.controller.pause();
    if (mounted) setState(() {});
  }

  Future<void> _areYouSureDialog(BuildContext context) async {
    final canPop = _canSave
        ? await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: TranslatableText(TextManager.instance.areYouSureQuit),
              content: TranslatableText(
                TextManager.instance.youWillLoseYourProgress,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: TranslatableText(TextManager.instance.cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: TranslatableText(TextManager.instance.quit),
                ),
              ],
            ),
          )
        : true;

    if (!context.mounted) return;
    _canPop = canPop;
    if (_canPop) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _manageFileSaving() async {
    final now = DateTime.now();

    // We have to copy because _metaData won't be null anymore
    final isVideoNew = _isVideoNew;

    _metaData = (isVideoNew
        ? VideoMetaData(
            athlete: await Athletes.instance.athleteFromNameOrAdd(
              _athleteName!,
            ),
            trialName: _trialName!,
            baseFolder: Directory(
              '${await FileManager.dataFolder}/${_athleteName!}',
            ),
            duration: widget.controller.value.duration,
            creationDate: now,
            lastModified: now,
            timeJumpStarts: _videoPlaybackWatcher.start,
            timeJumpEnds: _videoPlaybackWatcher.end,
          )
        : _metaData!.copyWith(
            lastModified: now,
            timeJumpStarts: _videoPlaybackWatcher.start,
            timeJumpEnds: _videoPlaybackWatcher.end,
          ));

    // Add the video to the database
    await Athletes.instance.addVideo(_metaData!);

    // If the file is new, move it to the correct folder
    if (isVideoNew) {
      await File(widget.filePath).rename(_metaData!.videoPath);
    }
  }

  void _managePop() {
    if (_canSave && _isVideoNew) {
      // If the file is new and the user did not save it,
      // it means they just recorded it but do not want to keep it, then delete it
      File(widget.filePath).delete();
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) => _managePop(),
      child: Scaffold(
        appBar: AppBar(
          title: TranslatableText(
            TextManager.instance.visualizingVideo,
            style: appTitleStyle,
          ),
          elevation: 0,
          leading: IconButton(
            onPressed: () => _areYouSureDialog(context),
            icon: Icon(Icons.arrow_back),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _canSave ? _onSaveVideo : null,
            ),
          ],
        ),
        bottomNavigationBar: Container(
          color: Theme.of(context).appBarTheme.backgroundColor,
          width: double.infinity,
          height: 220,
          child: _VideoPlaybackSlider(
            _videoPlaybackWatcher,
            videoController: widget.controller,
            onUpdateRanges: _onUpdateJumpTime,
            onPlay: _onPlay,
            onPause: _onPause,
            onPrepareManualSeek: _prepareManualSeek,
          ),
        ),
        body: Stack(
          children: [
            Container(
              width: double.infinity,
              height: double.infinity,
              color: darkBlue,
            ),
            Center(
              child: AspectRatio(
                aspectRatio: widget.controller.value.aspectRatio,
                child: VideoPlayer(widget.controller),
              ),
            ),
            Positioned(
              left: 24,
              top: 24,
              child: _FightTime(videoPlaybackWatcher: _videoPlaybackWatcher),
            ),
            Positioned(
              right: 24,
              top: 24,
              child: FutureBuilder(
                future: _videoPlaybackWatcherCompleter.future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Container();
                  }
                  return _FpsSelector(
                    initialValue: _videoPlaybackWatcher.fps,
                    onFpsChanged: _onChangedFps,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FightTime extends StatelessWidget {
  const _FightTime({required _VideoPlaybackWatcher videoPlaybackWatcher})
      : _videoPlaybackWatcher = videoPlaybackWatcher;

  final _VideoPlaybackWatcher _videoPlaybackWatcher;

  @override
  Widget build(BuildContext context) {
    final fligthTimeDuration = fligthTime(
      timeJumpStarts: _videoPlaybackWatcher.start,
      timeJumpEnds: _videoPlaybackWatcher.end,
    );
    final fligthTimeText =
        '${(fligthTimeDuration.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(3)} s';
    final fligthHeightText =
        '${(flightHeight(fligthTime: fligthTimeDuration) * 100).toStringAsFixed(1)} cm';

    final textStyle = mainTextStyle.copyWith(
      color: Theme.of(
        context,
      ).elevatedButtonTheme.style!.foregroundColor!.resolve({}),
    );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .elevatedButtonTheme
            .style!
            .backgroundColor!
            .resolve({})!.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  TranslatableText(
                    TextManager.instance.flightTime,
                    style: textStyle,
                  ),
                  Text(': ', style: textStyle),
                ],
              ),
              Row(
                children: [
                  TranslatableText(
                    TextManager.instance.flightHeight,
                    style: textStyle,
                  ),
                  Text(': ', style: textStyle),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(fligthTimeText, style: textStyle),
              Text(fligthHeightText, style: textStyle),
            ],
          ),
        ],
      ),
    );
  }
}

class _FpsSelector extends StatefulWidget {
  const _FpsSelector({required this.initialValue, required this.onFpsChanged});

  final FpsOptions initialValue;
  final Function(FpsOptions) onFpsChanged;

  @override
  State<_FpsSelector> createState() => _FpsSelectorState();
}

class _FpsSelectorState extends State<_FpsSelector> {
  bool _isExpanded = false;
  late FpsOptions _selectedFps = widget.initialValue;

  void _onFpsChanged(FpsOptions fps) {
    _selectedFps = fps;
    widget.onFpsChanged(_selectedFps);
    _isExpanded = false;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = mainTextStyle.copyWith(
      color: Theme.of(
        context,
      ).elevatedButtonTheme.style!.foregroundColor!.resolve({}),
    );

    final backgroundColor = Theme.of(context)
        .elevatedButtonTheme
        .style!
        .backgroundColor!
        .resolve({})!.withValues(alpha: 0.7);

    final width = 110.0;
    final height = 45.0;

    return Stack(
      children: [
        GestureDetector(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Container(
            width: width,
            height: height,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: _isExpanded
                  ? BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    )
                  : BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('FPS: ${_selectedFps.toString()}', style: textStyle),
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded) Container(height: MediaQuery.of(context).size.height),
        if (_isExpanded)
          Positioned(
            left: 0,
            top: height,
            child: Container(
              width: width,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Column(
                children: FpsOptions.values
                    .map(
                      (e) => GestureDetector(
                        onTap: () => _onFpsChanged(e),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text('FPS: ${e.toString()}', style: textStyle),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }
}

class _VideoPlaybackSlider extends StatefulWidget {
  const _VideoPlaybackSlider(
    this.watcher, {
    required this.videoController,
    required this.onUpdateRanges,
    required this.onPlay,
    required this.onPause,
    required this.onPrepareManualSeek,
  });

  final _VideoPlaybackWatcher watcher;
  final VideoPlayerController videoController;
  final VoidCallback onUpdateRanges;
  final Future<void> Function() onPlay;
  final Future<void> Function() onPause;
  final Future<void> Function() onPrepareManualSeek;

  @override
  State<_VideoPlaybackSlider> createState() => _VideoPlaybackSliderState();
}

class _VideoPlaybackSliderState extends State<_VideoPlaybackSlider> {
  late var _ranges = RangeValues(
    normalizedVideoPosition(
      position: widget.watcher.start,
      duration: widget.videoController.value.duration,
    ),
    normalizedVideoPosition(
      position: widget.watcher.end,
      duration: widget.videoController.value.duration,
    ),
  );
  bool _focusOnFirst = true;
  late double _fps = widget.watcher.fps.value;
  late int _targetFrame = _frameForPosition(widget.watcher.start);
  late final VideoSeekCoordinator _seekCoordinator;
  bool _isScrubbing = false;
  bool _wasPlayingBeforeScrub = false;
  int _scrubSequence = 0;
  Future<void>? _pauseBeforeSeek;
  late bool _lastControllerIsPlaying = widget.videoController.value.isPlaying;
  late bool _lastControllerIsCompleted =
      widget.videoController.value.isCompleted;

  int get _totalFrames => totalFramesForDuration(
        duration: widget.videoController.value.duration,
        fps: _fps,
      );

  Duration get _targetPosition => _positionForFrame(_targetFrame);

  double get _normalizedTarget => normalizedVideoPosition(
        position: _targetPosition,
        duration: widget.videoController.value.duration,
      );

  void _reportSeekError(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'flight_time video replay',
        context: ErrorDescription('while seeking during video scrubbing'),
      ),
    );
  }

  void _reportScrubMetrics(VideoSeekMetricsSnapshot metrics) {
    debugPrint(metrics.formatForDebugLog());
  }

  @override
  void initState() {
    super.initState();
    _seekCoordinator = VideoSeekCoordinator(
      seek: _seekVideo,
      // Logical frames can change freely. This bounds only the commands sent
      // to the decoder, which cannot display every intermediate target.
      minimumInterval: Platform.isAndroid
          ? androidReplaySeekMinimumInterval()
          : const Duration(
              microseconds: Duration.microsecondsPerSecond ~/ 60,
            ),
      // A preview is dispatched during the gesture. The minimum interval and
      // last-request-wins coordinator protect the decoder without hiding all
      // intermediate images until the gesture ends.
      debounceInterval: Duration.zero,
      // A platform seek can occasionally never complete after repeated codec
      // flushes. It must not permanently block the last-request-wins queue.
      operationTimeout: Platform.isAndroid ? androidReplaySeekTimeout : null,
      onError: _reportSeekError,
      onMetrics: kDebugMode ? _reportScrubMetrics : null,
    );
    widget.videoController.addListener(_updateFromVideoController);
  }

  @override
  void didUpdateWidget(_VideoPlaybackSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.videoController, widget.videoController)) {
      oldWidget.videoController.removeListener(_updateFromVideoController);
      widget.videoController.addListener(_updateFromVideoController);
      _seekCoordinator.invalidateLastCompletedTarget();
      _lastControllerIsPlaying = widget.videoController.value.isPlaying;
      _lastControllerIsCompleted = widget.videoController.value.isCompleted;
    }
    final updatedFps = widget.watcher.fps.value;
    if (updatedFps != _fps) {
      final currentPosition = _positionForFrame(_targetFrame);
      _fps = updatedFps;
      _targetFrame = _frameForPosition(currentPosition);
    }
  }

  @override
  void dispose() {
    _seekCoordinator.dispose();
    widget.videoController.removeListener(_updateFromVideoController);
    super.dispose();
  }

  int _frameForPosition(Duration position) {
    return clampFrameIndex(durationToFrame(position, _fps), _totalFrames);
  }

  Duration _positionForFrame(int frame) {
    if (!_fps.isFinite || _fps <= 0) return Duration.zero;

    final position = frameToDuration(
      clampFrameIndex(frame, _totalFrames),
      _fps,
    );
    final duration = widget.videoController.value.duration;
    return position > duration ? duration : position;
  }

  Future<void> _seekVideo(Duration target) async {
    await widget.onPrepareManualSeek();
    final pause = _pauseBeforeSeek;
    if (pause != null) {
      try {
        await pause;
      } finally {
        if (identical(_pauseBeforeSeek, pause)) _pauseBeforeSeek = null;
      }
    }
    await widget.videoController.seekTo(target);
  }

  void _updateFromVideoController() {
    if (!mounted) return;

    final value = widget.videoController.value;
    var needsRebuild = value.isPlaying != _lastControllerIsPlaying ||
        value.isCompleted != _lastControllerIsCompleted;
    _lastControllerIsPlaying = value.isPlaying;
    _lastControllerIsCompleted = value.isCompleted;

    if (value.isPlaying || value.isCompleted) {
      _seekCoordinator.invalidateLastCompletedTarget();
    }

    if (value.isPlaying && !_isScrubbing && !_seekCoordinator.isBusy) {
      final playingFrame = _frameForPosition(
        value.position,
      );
      if (playingFrame != _targetFrame) {
        _targetFrame = playingFrame;
        needsRebuild = true;
      }
    }

    if (needsRebuild) setState(() {});
  }

  void _setTargetFrame(int requestedFrame, {bool requestSeek = true}) {
    final nextFrame = clampFrameIndex(requestedFrame, _totalFrames);
    final changed = nextFrame != _targetFrame;
    _targetFrame = nextFrame;
    if (changed) {
      _seekCoordinator.recordTargetFrameChange();
      if (mounted) setState(() {});
    }
    if (requestSeek && changed) {
      _seekCoordinator.request(
        _targetPosition,
      );
    }
  }

  void _onScrubStart() {
    _scrubSequence++;
    if (_isScrubbing) return;

    _isScrubbing = true;
    _wasPlayingBeforeScrub = widget.videoController.value.isPlaying;
    _pauseBeforeSeek = _wasPlayingBeforeScrub ? widget.onPause() : null;
    if (mounted) setState(() {});
  }

  Future<void> _onScrubEnd(int frame) async {
    final sequence = _scrubSequence;
    _setTargetFrame(frame, requestSeek: false);
    try {
      await _seekCoordinator.requestFinal(_targetPosition);
    } on Object catch (error, stackTrace) {
      _reportSeekError(error, stackTrace);
    }
    if (!mounted || sequence != _scrubSequence) return;

    _isScrubbing = false;
    if (_wasPlayingBeforeScrub && _targetFrame < _totalFrames) {
      unawaited(widget.onPlay());
    }
    setState(() {});
  }

  void _onUpdateRanges(RangeValues values) {
    if (_ranges.start == values.start && _ranges.end == values.end) return;

    _seekCoordinator.recordGestureUpdate();
    _focusOnFirst = _ranges.start != values.start;
    final duration = widget.videoController.value.duration;
    final startFrame = _frameForPosition(
      videoPositionFromNormalized(
        normalizedPosition: values.start,
        duration: duration,
      ),
    );
    final endFrame = _frameForPosition(
      videoPositionFromNormalized(
        normalizedPosition: values.end,
        duration: duration,
      ),
    );
    widget.watcher.start = _positionForFrame(startFrame);
    widget.watcher.end = _positionForFrame(endFrame);
    _ranges = RangeValues(
      normalizedVideoPosition(
        position: widget.watcher.start,
        duration: duration,
      ),
      normalizedVideoPosition(
        position: widget.watcher.end,
        duration: duration,
      ),
    );
    widget.onUpdateRanges();
    if (mounted) setState(() {});

    _setTargetFrame(
      _focusOnFirst ? startFrame : endFrame,
      requestSeek: false,
    );
    _seekCoordinator.request(
      _targetPosition,
    );
  }

  Future<void> _onRangeChangeEnd(RangeValues values) async {
    _onUpdateRanges(values);
    try {
      await _seekCoordinator.requestFinal(_targetPosition);
    } on Object catch (error, stackTrace) {
      _reportSeekError(error, stackTrace);
    }
  }

  void _onJogFrameChanged(int frame) {
    _seekCoordinator.recordGestureUpdate();
    _setTargetFrame(frame);
  }

  void _setStartMarkerToCurrentFrame() {
    if (_targetPosition >= widget.watcher.end) return;
    widget.watcher.start = _targetPosition;
    _ranges = RangeValues(_normalizedTarget, _ranges.end);
    widget.onUpdateRanges();
    setState(() {});
  }

  void _setEndMarkerToCurrentFrame() {
    if (_targetPosition <= widget.watcher.start) return;
    widget.watcher.end = _targetPosition;
    _ranges = RangeValues(_ranges.start, _normalizedTarget);
    widget.onUpdateRanges();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    const padding = 10.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: padding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            children: [
              RangeSlider(
                values: _ranges,
                onChanged: _onUpdateRanges,
                onChangeEnd: _onRangeChangeEnd,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3 * padding),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _MarkerButton(
                          symbol: '|',
                          onTap: _targetPosition < widget.watcher.end
                              ? _setStartMarkerToCurrentFrame
                              : null,
                        ),
                        SizedBox(width: padding),
                        _MarkerButton(
                          symbol: '<<',
                          onTap: () => _setTargetFrame(
                            _frameForPosition(widget.watcher.start),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MarkerButton(
                          symbol: '<',
                          onTap: () => _setTargetFrame(_targetFrame - 1),
                        ),
                        SizedBox(width: padding),
                        _PlayButton(
                          isPlaying: widget.videoController.value.isPlaying,
                          onPause: () => unawaited(widget.onPause()),
                          onPlay: () => unawaited(widget.onPlay()),
                        ),
                        SizedBox(width: padding),
                        _MarkerButton(
                          symbol: '>',
                          onTap: () => _setTargetFrame(_targetFrame + 1),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _MarkerButton(
                          symbol: '>>',
                          onTap: () => _setTargetFrame(
                            _frameForPosition(widget.watcher.end),
                          ),
                        ),
                        SizedBox(width: padding),
                        _MarkerButton(
                          symbol: '|',
                          onTap: _targetPosition > widget.watcher.start
                              ? _setEndMarkerToCurrentFrame
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              VelocityJogScrubber(
                fps: _fps,
                duration: widget.videoController.value.duration,
                frameIndex: _targetFrame,
                reverseDirection: true,
                onFrameChanged: _onJogFrameChanged,
                onScrubStart: _onScrubStart,
                onScrubEnd: _onScrubEnd,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const playbackButtonColor = Colors.white;
const playbackDisabledButtonColor = Colors.white30;

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.isPlaying,
    required this.onPause,
    required this.onPlay,
  });

  final bool isPlaying;
  final VoidCallback onPause;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isPlaying ? onPause : onPlay,
      child: Container(
        width: 45,
        height: 45,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: playbackButtonColor,
        ),
        child:
            isPlaying ? const Icon(Icons.pause) : const Icon(Icons.play_arrow),
      ),
    );
  }
}

class _MarkerButton extends StatelessWidget {
  const _MarkerButton({required this.symbol, required this.onTap});

  final String symbol;
  final Function()? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              onTap == null ? playbackDisabledButtonColor : playbackButtonColor,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text(symbol),
        ),
      ),
    );
  }
}
