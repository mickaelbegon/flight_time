import 'dart:io';

import 'package:flight_time/experimental_capture/capture_diagnostics.dart';
import 'package:flight_time/models/file_manager.dart';
import 'package:flight_time/models/text_manager.dart';
import 'package:flight_time/widgets/helpers.dart';
import 'package:flight_time/widgets/main_drawer.dart';
import 'package:flight_time/widgets/translatable_text.dart';
import 'package:flutter/material.dart';
import 'package:nitro_camera/nitro_camera.dart' as nitro;

/// Opt-in benchmark page for Nitro Camera. It intentionally does not create
/// Flight Time trials or replace the production CamerAwesome capture route.
class NitroCameraExperimentPage extends StatefulWidget {
  const NitroCameraExperimentPage({super.key});

  static const routeName = '/nitro-camera-experiment';

  @override
  State<NitroCameraExperimentPage> createState() =>
      _NitroCameraExperimentPageState();
}

class _NitroCameraExperimentPageState extends State<NitroCameraExperimentPage> {
  nitro.CameraController? _controller;
  nitro.CameraDeviceInfo? _device;
  List<nitro.CameraHighSpeedFormat> _modes = const [];
  nitro.CameraHighSpeedFormat? _selectedMode;
  _ExperimentCapture? _lastCapture;
  String? _error;
  bool _initializing = true;
  bool _operationInProgress = false;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _discoverCamera();
  }

  Future<void> _discoverCamera() async {
    try {
      final permission = await nitro.CameraController.requestCameraPermission();
      if (permission != nitro.PermissionStatus.granted) {
        throw StateError('Camera permission was not granted.');
      }

      final devices = await nitro.CameraController.getAvailableCameraDevices();
      final backCamera = devices.where((device) {
        return device.position == nitro.CameraPosition.back;
      }).firstOrNull;
      if (backCamera == null) {
        throw StateError('No back camera is available.');
      }

      final modes = [...backCamera.highSpeedFormats]..sort((left, right) {
          final byFps = right.maximumFps.compareTo(left.maximumFps);
          if (byFps != 0) return byFps;
          return (right.width * right.height)
              .compareTo(left.width * left.height);
        });
      final uniqueModes = <String, nitro.CameraHighSpeedFormat>{
        for (final mode in modes)
          '${mode.width}x${mode.height}@${mode.maximumFps}': mode,
      }.values.toList(growable: false);

      if (!mounted) return;
      setState(() {
        _device = backCamera;
        _modes = uniqueModes;
        _selectedMode = uniqueModes.firstOrNull;
        _initializing = false;
      });
      if (_selectedMode != null) await _openSelectedMode();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _initializing = false;
      });
    }
  }

  Future<void> _openSelectedMode() async {
    final device = _device;
    final mode = _selectedMode;
    if (device == null || mode == null) return;

    setState(() {
      _operationInProgress = true;
      _error = null;
    });
    try {
      final previous = _controller;
      _controller = null;
      await previous?.dispose();

      final controller = nitro.CameraController(
        device: device,
        audio: false,
        photo: false,
      );
      // The normal preview is opened at the exact high-speed size. The
      // dedicated high-speed session is only entered when recording starts.
      await controller.initialize(
        width: mode.width,
        height: mode.height,
        fps: 30,
      );
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _operationInProgress = false);
    }
  }

  Future<String> _newOutputPath(nitro.CameraHighSpeedFormat mode) async {
    final directory =
        Directory('${await FileManager.dataFolder}/nitro_experiments');
    await directory.create(recursive: true);
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    return '${directory.path}/nitro_${mode.width}x${mode.height}_${mode.maximumFps}fps_$timestamp.mp4';
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    final mode = _selectedMode;
    if (controller == null || mode == null || _operationInProgress) return;

    setState(() {
      _operationInProgress = true;
      _error = null;
    });
    try {
      if (!_isRecording) {
        final outputPath = await _newOutputPath(mode);
        final started = await controller.startHighSpeedRecording(
          outputPath,
          fps: mode.maximumFps,
        );
        if (!started) {
          throw StateError(
            'The device refused ${mode.width}×${mode.height} '
            '@ ${mode.maximumFps} fps.',
          );
        }
        if (!mounted) return;
        setState(() => _isRecording = true);
      } else {
        final file = await controller.stopHighSpeedRecording();
        final diagnostics = controller.getSessionState().highSpeedDiagnostics;
        if (diagnostics == null) {
          throw StateError('Nitro Camera returned no high-speed diagnostics.');
        }
        final report = CaptureTimingReport.fromTimestamps(
          timestampsMicroseconds: diagnostics.timestampsMicroseconds,
          expectedFps: diagnostics.captureFps,
        );
        final negotiatedMode = NegotiatedCaptureMode(
          request: CaptureRequest(
            width: mode.width,
            height: mode.height,
            fps: mode.maximumFps,
          ),
          width: diagnostics.width,
          height: diagnostics.height,
          captureFps: diagnostics.captureFps,
          playbackFps: diagnostics.playbackFps,
          isSlowMotion: diagnostics.isSlowMotion,
        );
        if (!mounted) return;
        setState(() {
          _isRecording = false;
          _lastCapture = _ExperimentCapture(
            path: file.path,
            fileSize: file.fileSize,
            mode: negotiatedMode,
            report: report,
            timestampsTruncated: diagnostics.timestampsTruncated,
          );
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _error = error.toString();
      });
    } finally {
      if (mounted) setState(() => _operationInProgress = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: TranslatableText(
          TextManager.instance.experimentalCamera,
          style: appTitleStyle,
        ),
      ),
      drawer: const MainDrawer(),
      body: Column(
        children: [
          Expanded(
            child: controller == null
                ? Center(
                    child: _initializing
                        ? const CircularProgressIndicator()
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error ?? 'No high-speed mode found.'),
                          ),
                  )
                : nitro.CameraPreview(controller: controller),
          ),
          _buildControls(context),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final hasModes = _modes.isNotEmpty;
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Nitro Camera — expérimental. Les vidéos high-speed sont encodées en slow motion à 30 fps ; elles ne créent pas d’essai Flight Time.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<nitro.CameraHighSpeedFormat>(
                key: ValueKey(_selectedMode?.toString()),
                initialValue: _selectedMode,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Mode Camera2 high-speed annoncé',
                ),
                items: _modes
                    .map(
                      (mode) => DropdownMenuItem(
                        value: mode,
                        child: Text(mode.toString()),
                      ),
                    )
                    .toList(growable: false),
                onChanged: !hasModes || _operationInProgress || _isRecording
                    ? null
                    : (mode) async {
                        if (mode == null || mode == _selectedMode) return;
                        setState(() => _selectedMode = mode);
                        await _openSelectedMode();
                      },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed:
                    !hasModes || _operationInProgress ? null : _toggleRecording,
                icon:
                    Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record),
                label:
                    Text(_isRecording ? 'Arrêter et analyser' : 'Enregistrer'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              if (_lastCapture != null) ...[
                const SizedBox(height: 16),
                _CaptureReportCard(capture: _lastCapture!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ExperimentCapture {
  const _ExperimentCapture({
    required this.path,
    required this.fileSize,
    required this.mode,
    required this.report,
    required this.timestampsTruncated,
  });

  final String path;
  final int fileSize;
  final NegotiatedCaptureMode mode;
  final CaptureTimingReport report;
  final bool timestampsTruncated;
}

class _CaptureReportCard extends StatelessWidget {
  const _CaptureReportCard({required this.capture});

  final _ExperimentCapture capture;

  @override
  Widget build(BuildContext context) {
    final mode = capture.mode;
    final report = capture.report;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Diagnostic de capture',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Requested: ${mode.request.label}'),
            Text(
                'Negotiated: ${mode.width}×${mode.height} @ ${mode.captureFps} fps'),
            Text('Playback: ${mode.playbackFps} fps slow motion'),
            Text('Frames: ${report.frameCount}'),
            Text('Measured: ${report.measuredFps.toStringAsFixed(2)} fps'),
            Text(
                'Median interval: ${report.medianIntervalMicroseconds.toStringAsFixed(1)} µs'),
            Text(
                'Jitter (σ): ${report.standardDeviationMicroseconds.toStringAsFixed(1)} µs'),
            Text('Estimated dropped frames: ${report.estimatedDroppedFrames}'),
            Text(
                'File size: ${(capture.fileSize / 1024 / 1024).toStringAsFixed(2)} MB'),
            if (capture.timestampsTruncated)
              const Text(
                'Timestamp list truncated; only the initial diagnostic window was analysed.',
                style: TextStyle(color: Colors.orange),
              ),
            const SizedBox(height: 4),
            SelectableText(capture.path, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
