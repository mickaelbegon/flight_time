import 'dart:async';

import 'package:flight_time/widgets/video_seek_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> flushMicrotasks() => Future<void>.delayed(Duration.zero);

void main() {
  test('last request wins while a seek is active', () async {
    final targets = <Duration>[];
    final completions = <Completer<void>>[];
    final coordinator = VideoSeekCoordinator(
      minimumInterval: Duration.zero,
      seek: (target) {
        targets.add(target);
        final completion = Completer<void>();
        completions.add(completion);
        return completion.future;
      },
    );
    addTearDown(coordinator.dispose);

    coordinator.request(const Duration(milliseconds: 10));
    coordinator.request(const Duration(milliseconds: 20));
    coordinator.request(const Duration(milliseconds: 30));

    expect(targets, [const Duration(milliseconds: 10)]);
    expect(coordinator.pendingTarget, const Duration(milliseconds: 30));
    expect(coordinator.maxPendingSeekCount, 1);

    completions.first.complete();
    await flushMicrotasks();

    expect(targets, [
      const Duration(milliseconds: 10),
      const Duration(milliseconds: 30),
    ]);
    completions.last.complete();
    await flushMicrotasks();
    expect(coordinator.isBusy, isFalse);
  });

  test('final seek drops stale pending work and awaits the exact target',
      () async {
    final targets = <Duration>[];
    final completions = <Completer<void>>[];
    final coordinator = VideoSeekCoordinator(
      minimumInterval: Duration.zero,
      seek: (target) {
        targets.add(target);
        final completion = Completer<void>();
        completions.add(completion);
        return completion.future;
      },
    );
    addTearDown(coordinator.dispose);

    coordinator.request(const Duration(milliseconds: 10));
    coordinator.request(const Duration(milliseconds: 20));
    final finalSeek = coordinator.requestFinal(
      const Duration(microseconds: 33333),
    );

    expect(targets, [const Duration(milliseconds: 10)]);
    completions.first.complete();
    await flushMicrotasks();

    expect(targets, [
      const Duration(milliseconds: 10),
      const Duration(microseconds: 33333),
    ]);
    var finalCompleted = false;
    finalSeek.then((_) => finalCompleted = true);
    await flushMicrotasks();
    expect(finalCompleted, isFalse);

    completions.last.complete();
    await finalSeek;
    expect(finalCompleted, isTrue);
    expect(targets, isNot(contains(const Duration(milliseconds: 20))));
  });

  test('final seek does not flush an already completed exact target', () async {
    final targets = <Duration>[];
    final coordinator = VideoSeekCoordinator(
      minimumInterval: Duration.zero,
      seek: (target) async => targets.add(target),
    );
    addTearDown(coordinator.dispose);

    const target = Duration(microseconds: 4167);
    coordinator.request(target);
    await flushMicrotasks();
    await coordinator.requestFinal(target);

    expect(targets, [target]);
  });

  test('external playback invalidates the completed-target optimization',
      () async {
    final targets = <Duration>[];
    final coordinator = VideoSeekCoordinator(
      minimumInterval: Duration.zero,
      seek: (target) async => targets.add(target),
    );
    addTearDown(coordinator.dispose);

    const target = Duration(milliseconds: 500);
    coordinator.request(target);
    await flushMicrotasks();
    coordinator.invalidateLastCompletedTarget();
    await coordinator.requestFinal(target);

    expect(targets, [target, target]);
  });

  test('a stalled seek times out and the latest request is dispatched',
      () async {
    final targets = <Duration>[];
    final stalledSeek = Completer<void>();
    final coordinator = VideoSeekCoordinator(
      minimumInterval: Duration.zero,
      operationTimeout: const Duration(milliseconds: 10),
      seek: (target) {
        targets.add(target);
        if (targets.length == 1) return stalledSeek.future;
        return Future<void>.value();
      },
    );
    addTearDown(coordinator.dispose);

    coordinator.request(const Duration(milliseconds: 10));
    coordinator.request(const Duration(milliseconds: 30));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(targets, [
      const Duration(milliseconds: 10),
      const Duration(milliseconds: 30),
    ]);
    expect(coordinator.isBusy, isFalse);
  });

  test('debounced preview only dispatches the latest requested target',
      () async {
    final targets = <Duration>[];
    final coordinator = VideoSeekCoordinator(
      minimumInterval: Duration.zero,
      debounceInterval: const Duration(milliseconds: 10),
      seek: (target) async => targets.add(target),
    );
    addTearDown(coordinator.dispose);

    coordinator.request(const Duration(milliseconds: 10), debounce: true);
    coordinator.request(const Duration(milliseconds: 20), debounce: true);
    coordinator.request(const Duration(milliseconds: 30), debounce: true);
    expect(targets, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(targets, [const Duration(milliseconds: 30)]);
    expect(coordinator.isBusy, isFalse);
  });
}
