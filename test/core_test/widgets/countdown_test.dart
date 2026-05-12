import 'package:bb_mobile/core/widgets/timers/countdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps second ticks for mmss countdowns', () {
    expect(
      countdownTickInterval(
        format: CountdownFormat.mmss,
        remaining: const Duration(hours: 2),
      ),
      const Duration(seconds: 1),
    );
  });

  test('uses minute ticks for long dhm countdowns', () {
    expect(
      countdownTickInterval(
        format: CountdownFormat.dhm,
        remaining: const Duration(hours: 2),
      ),
      const Duration(minutes: 1),
    );
  });

  test('uses second ticks for short dhm countdowns', () {
    expect(
      countdownTickInterval(
        format: CountdownFormat.dhm,
        remaining: const Duration(hours: 1),
      ),
      const Duration(seconds: 1),
    );
  });
}
