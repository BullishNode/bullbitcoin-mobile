import 'package:bb_mobile/features/onboarding/domain/entropy_motion_port.dart';
import 'package:flutter/services.dart';

class PlatformEntropyMotionPort implements EntropyMotionPort {
  static const _channel = EventChannel('com.bullbitcoin.mobile/entropy_motion');

  const PlatformEntropyMotionPort();

  @override
  Stream<EntropyMotionSample> samples() =>
      _channel.receiveBroadcastStream().map(_decode);

  static EntropyMotionSample _decode(Object? event) {
    if (event is! List<Object?> || event.length != 8) {
      throw const FormatException('Invalid entropy motion sample shape');
    }

    final source = event[0];
    final nativeSequence = event[1];
    final sensorTimestampNanos = event[2];
    final nativeArrivalTimestampNanos = event[3];
    final x = event[4];
    final y = event[5];
    final z = event[6];
    final accuracy = event[7];
    if (source is! int ||
        source < 0 ||
        source >= EntropyMotionKind.values.length ||
        nativeSequence is! int ||
        nativeSequence < 0 ||
        sensorTimestampNanos is! int ||
        sensorTimestampNanos < 0 ||
        nativeArrivalTimestampNanos is! int ||
        nativeArrivalTimestampNanos < 0 ||
        x is! num ||
        !x.isFinite ||
        y is! num ||
        !y.isFinite ||
        z is! num ||
        !z.isFinite ||
        accuracy is! int) {
      throw const FormatException('Invalid entropy motion sample values');
    }

    return EntropyMotionSample(
      kind: EntropyMotionKind.values[source],
      nativeSequence: nativeSequence,
      sensorTimestampNanos: sensorTimestampNanos,
      nativeArrivalTimestampNanos: nativeArrivalTimestampNanos,
      x: x.toDouble(),
      y: y.toDouble(),
      z: z.toDouble(),
      accuracy: accuracy,
    );
  }
}
