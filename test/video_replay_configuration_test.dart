import 'package:flight_time/widgets/video_replay_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the default Android replay configuration keeps five seconds back', () {
    expect(androidReplayBackBufferDurationMs, 5000);
  });

  test('the default Android preview seek limit is a safe 8 Hz', () {
    expect(androidReplayMaximumSeeksPerSecond, 8);
    expect(
      androidReplaySeekMinimumInterval(),
      const Duration(
        microseconds: Duration.microsecondsPerSecond ~/ 8,
      ),
    );
  });
}
