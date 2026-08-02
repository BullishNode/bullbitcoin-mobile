enum EntropyMotionKind { accelerometer, gyroscope }

class EntropyMotionSample {
  final EntropyMotionKind kind;
  final int nativeSequence;
  final int sensorTimestampNanos;
  final int nativeArrivalTimestampNanos;
  final double x;
  final double y;
  final double z;
  final int accuracy;

  const EntropyMotionSample({
    required this.kind,
    required this.nativeSequence,
    required this.sensorTimestampNanos,
    required this.nativeArrivalTimestampNanos,
    required this.x,
    required this.y,
    required this.z,
    required this.accuracy,
  });
}

abstract interface class EntropyMotionPort {
  Stream<EntropyMotionSample> samples();
}
