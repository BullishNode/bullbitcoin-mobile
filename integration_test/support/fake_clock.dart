import 'package:bb_mobile/core/utils/clock.dart';

/// A test [Clock] whose time is settable, so the D8 clock-skew dimension
/// (GETPAID-APP-E2E-FAILURE-MATRIX §5.1) can drive the signing/ordering paths
/// off a skewed device clock. Register it over the real [SystemClock] with
/// [overrideClockForTest] before resolving the facades that read the clock.
class FakeClock implements Clock {
  FakeClock(DateTime now) : _now = now.toUtc();

  /// A clock pinned to a fixed, deterministic base instant (2025-01-01T00:00Z),
  /// the "in-sync" reference the skew offsets are applied against.
  factory FakeClock.baseline() => FakeClock(_baseInstant);

  static final DateTime _baseInstant = DateTime.utc(2025, 1, 1);

  DateTime _now;

  set now(DateTime value) => _now = value.toUtc();

  /// Shift the clock by [offset] (positive = into the future).
  void skew(Duration offset) => _now = _now.add(offset);

  @override
  DateTime nowUtc() => _now;
}
