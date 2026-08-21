import 'package:flight_time/widgets/velocity_jog_scrubber.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('slow drag updates frames and sends an exact final frame', (
    tester,
  ) async {
    var frame = 100;
    var scrubStartCount = 0;
    final changedFrames = <int>[];
    final finalFrames = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: StatefulBuilder(
                builder: (context, setState) => VelocityJogScrubber(
                  fps: 240,
                  duration: const Duration(seconds: 2),
                  frameIndex: frame,
                  enableInertia: false,
                  enableHaptics: false,
                  onScrubStart: () => scrubStartCount++,
                  onFrameChanged: (nextFrame) {
                    changedFrames.add(nextFrame);
                    setState(() => frame = nextFrame);
                  },
                  onScrubEnd: (finalFrame) async {
                    finalFrames.add(finalFrame);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    await tester.timedDrag(
      find.byType(VelocityJogScrubber),
      const Offset(36, 0),
      const Duration(seconds: 2),
    );
    await tester.pumpAndSettle();

    expect(scrubStartCount, 1);
    expect(changedFrames, isNotEmpty);
    expect(changedFrames.last, inInclusiveRange(101, 103));
    expect(finalFrames, [changedFrames.last]);
    expect(tester.takeException(), isNull);
  });
}
