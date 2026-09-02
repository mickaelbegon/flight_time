import 'package:flight_time/widgets/video_seek_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aggregates a one-second scrub metrics window', () {
    final metrics = VideoSeekMetrics();
    metrics.recordGestureUpdate();
    metrics.recordGestureUpdate();
    metrics.recordTargetFrameChange();
    metrics.recordSeekRequest();
    metrics.recordSeekRequest();
    metrics.recordCoalescedRequest();
    metrics.recordSeekCompleted(const Duration(milliseconds: 10));
    metrics.recordSeekCompleted(const Duration(milliseconds: 20));
    metrics.recordSeekCompleted(const Duration(milliseconds: 50));
    metrics.recordSeekCompleted(const Duration(milliseconds: 100));

    final snapshot = metrics.takeSnapshot();

    expect(snapshot.gestureUpdates, 2);
    expect(snapshot.targetFrameChanges, 1);
    expect(snapshot.seekRequests, 2);
    expect(snapshot.seekCompleted, 4);
    expect(snapshot.coalescedRequests, 1);
    expect(snapshot.meanSeekDuration, const Duration(milliseconds: 45));
    expect(snapshot.medianSeekDuration, const Duration(milliseconds: 50));
    expect(snapshot.p95SeekDuration, const Duration(milliseconds: 100));
    expect(snapshot.maximumSeekDuration, const Duration(milliseconds: 100));
    expect(metrics.takeSnapshot().isEmpty, isTrue);
  });
}
