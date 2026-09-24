import 'dart:async';
import 'dart:io';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:camerawesome/pigeon.dart';
import 'package:flight_time/models/text_manager.dart';
import 'package:flight_time/screens/playback_page.dart';
import 'package:flight_time/widgets/helpers.dart';
import 'package:flight_time/widgets/main_drawer.dart';
import 'package:flight_time/widgets/translatable_text.dart';
import 'package:flight_time/widgets/waiting_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  static const routeName = '/camera-page';

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  static const _captureFpsPreferenceKey = 'captureFps';
  static const _captureFrameRates = <int>[30, 60, 120, 240];

  int _captureFps = 240;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      unawaited(_loadCaptureFps());
    }
  }

  Future<void> _loadCaptureFps() async {
    final preferences = await SharedPreferences.getInstance();
    final savedFps = preferences.getInt(_captureFpsPreferenceKey);
    if (!mounted || !_captureFrameRates.contains(savedFps)) return;
    setState(() => _captureFps = savedFps!);
  }

  Future<void> _setCaptureFps(int fps) async {
    if (fps == _captureFps) return;
    setState(() => _captureFps = fps);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_captureFpsPreferenceKey, fps);
  }

  void _recordVideo(BuildContext context, MediaCapture mediaRecording) {
    final finishedRecording = !mediaRecording.isRecordingVideo;
    if (!finishedRecording) return;

    Navigator.pushNamed(context, PlaybackPage.routeName,
        arguments: {'file_path': mediaRecording.captureRequest.path});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TranslatableText(TextManager.instance.recordingVideo,
            style: appTitleStyle),
        actions: [
          if (Platform.isAndroid)
            PopupMenuButton<int>(
              initialValue: _captureFps,
              tooltip: 'Cadence d’enregistrement',
              onSelected: (fps) => unawaited(_setCaptureFps(fps)),
              itemBuilder: (context) => [
                for (final fps in _captureFrameRates)
                  PopupMenuItem(value: fps, child: Text('$fps fps')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(child: Text('$_captureFps fps')),
              ),
            ),
        ],
      ),
      drawer: MainDrawer(),
      body: KeyedSubtree(
        key: ValueKey(_captureFps),
        child: CameraAwesomeBuilder.awesome(
          progressIndicator: WaitingScreen(),
          saveConfig: SaveConfig.video(
            videoOptions: VideoOptions(
              enableAudio: false,
              android: AndroidVideoOptions(
                highSpeedFrameRate: _captureFps == 30 ? null : _captureFps,
              ),
              ios: CupertinoVideoOptions(fps: 300),
            ),
          ),
          sensorConfig: SensorConfig.single(
            sensor: Sensor.position(SensorPosition.back),
          ),
          onMediaCaptureEvent: (mediaRecording) =>
              _recordVideo(context, mediaRecording),
        ),
      ),
    );
  }
}
