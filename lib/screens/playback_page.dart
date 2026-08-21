import 'dart:async';
import 'dart:io';

import 'package:flight_time/models/video_meta_data.dart';
import 'package:flight_time/widgets/scaffold_video_playback.dart';
import 'package:flight_time/widgets/waiting_screen.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class PlaybackPage extends StatefulWidget {
  const PlaybackPage({super.key});

  static const routeName = '/playback-page';

  @override
  State<PlaybackPage> createState() => _PlaybackPageState();
}

class _PlaybackPageState extends State<PlaybackPage> {
  bool _isReady = false;
  VideoMetaData? _metaData;
  String? _filePath;
  VideoPlayerController? _videoPlayerController;
  Future<void>? _controllerReplacement;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initVideoPlayer();
    });
  }

  @override
  void dispose() {
    final controller = _videoPlayerController;
    controller?.removeListener(_handleVideoPlayerState);
    unawaited(controller?.dispose());
    super.dispose();
  }

  void _handleVideoPlayerState() {
    final controller = _videoPlayerController;
    if (controller == null ||
        _controllerReplacement != null ||
        !controller.value.isCompleted) {
      return;
    }

    final replacement = _replaceCompletedController(controller);
    _controllerReplacement = replacement;
    unawaited(
      replacement.whenComplete(() {
        if (identical(_controllerReplacement, replacement)) {
          _controllerReplacement = null;
        }
      }),
    );
  }

  Future<void> _replaceCompletedController(
    VideoPlayerController completedController,
  ) async {
    VideoPlayerController? replacement;
    try {
      replacement = VideoPlayerController.file(File(_filePath!));
      await replacement.initialize();

      final duration = replacement.value.duration;
      if (duration > Duration.zero) {
        await replacement.seekTo(
          Duration(microseconds: duration.inMicroseconds - 1),
        );
      }

      if (!mounted || !identical(_videoPlayerController, completedController)) {
        await replacement.dispose();
        return;
      }

      completedController.removeListener(_handleVideoPlayerState);
      replacement.addListener(_handleVideoPlayerState);
      setState(() => _videoPlayerController = replacement);

      // Keep the old texture alive until the child has rebuilt with the new
      // controller, then release the decoder that reached the broken state.
      await WidgetsBinding.instance.endOfFrame;
      await completedController.dispose();
    } on Object catch (error, stackTrace) {
      if (replacement != null &&
          !identical(_videoPlayerController, replacement)) {
        await replacement.dispose();
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'flight_time video replay',
          context: ErrorDescription(
            'while recreating the video player after completion',
          ),
        ),
      );
    }
  }

  Future<void> _waitForControllerReady() async {
    await _controllerReplacement;
  }

  Future<void> _initVideoPlayer() async {
    _metaData = (ModalRoute.of(context)!.settings.arguments as Map)['meta_data']
        as VideoMetaData?;
    _filePath = _metaData == null
        ? (ModalRoute.of(context)!.settings.arguments as Map)['file_path']
            as String?
        : _metaData!.videoPath;

    final controller = VideoPlayerController.file(File(_filePath!));
    _videoPlayerController = controller;
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    controller.addListener(_handleVideoPlayerState);
    _isReady = true;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return _isReady
        ? ScaffoldVideoPlayback(
            controller: _videoPlayerController!,
            filePath: _filePath!,
            videoMetaData: _metaData,
            onWaitForControllerReady: _waitForControllerReady,
          )
        : WaitingScreen();
  }
}
