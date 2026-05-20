import 'package:bb_mobile/core/widgets/timers/countdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('expired countdown schedules timeout after build', (
    tester,
  ) async {
    var timeoutCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Countdown(
          until: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
          onTimeout: () => timeoutCount += 1,
        ),
      ),
    );

    expect(timeoutCount, 0);

    await tester.pump(const Duration(milliseconds: 1));

    expect(timeoutCount, 1);
  });

  testWidgets('scheduled timeout is ignored after deadline changes', (
    tester,
  ) async {
    var timeoutCount = 0;

    Widget countdown(DateTime until) {
      return MaterialApp(
        home: Countdown(until: until, onTimeout: () => timeoutCount += 1),
      );
    }

    await tester.pumpWidget(
      countdown(DateTime.now().toUtc().subtract(const Duration(seconds: 1))),
    );
    expect(timeoutCount, 0);

    await tester.pumpWidget(
      countdown(DateTime.now().toUtc().add(const Duration(minutes: 1))),
    );
    await tester.pump(const Duration(milliseconds: 1));

    expect(timeoutCount, 0);
  });

  testWidgets('exact deadline schedules timeout after build', (tester) async {
    var timeoutCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Countdown(
          until: DateTime.now().toUtc(),
          onTimeout: () => timeoutCount += 1,
        ),
      ),
    );

    expect(timeoutCount, 0);

    await tester.pump(const Duration(milliseconds: 1));
    expect(timeoutCount, 1);
  });
}
