import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bb_mobile/core/entropy/domain/usecases/mix_entropy_usecase.dart';
import 'package:bb_mobile/features/onboarding/domain/entropy_motion_port.dart';
import 'package:flutter/foundation.dart'
    show debugPrintSynchronously, kDebugMode;
import 'package:flutter_bloc/flutter_bloc.dart';

const _captureEnabled = bool.fromEnvironment('BB_ENTROPY_CAPTURE');
const _capturePrefix = 'BB_ENTROPY_CAPTURE_V2 ';

enum PointerSampleKind { down, move, up, cancel }

typedef ElapsedMicroseconds = int Function();

class EntropyCeremonyState {
  const EntropyCeremonyState({
    this.eventCount = 0,
    this.elapsedDurationMicros = 0,
    this.horizontalCoverage = 0,
    this.verticalCoverage = 0,
    this.isComplete = false,
  });

  /// Qualified pointer samples collected so far. This is ceremony pacing only,
  /// not an estimate of entropy bits.
  final int eventCount;

  /// Monotonic time between the first and latest accepted samples.
  final int elapsedDurationMicros;
  final double horizontalCoverage;
  final double verticalCoverage;
  final bool isComplete;

  static const targetEventCount = MixEntropyUsecase.requiredSampleCount;
  static const minimumElapsedDuration = Duration(seconds: 10);
  static const minimumAxisCoverage = 0.5;

  double get progress {
    final sampleProgress = eventCount / targetEventCount;
    final durationProgress =
        elapsedDurationMicros / minimumElapsedDuration.inMicroseconds;
    final coverageProgress =
        math.min(horizontalCoverage, verticalCoverage) / minimumAxisCoverage;
    return math
        .min(sampleProgress, math.min(durationProgress, coverageProgress))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  bool get gatesSatisfied =>
      eventCount >= targetEventCount &&
      elapsedDurationMicros >= minimumElapsedDuration.inMicroseconds &&
      horizontalCoverage >= minimumAxisCoverage &&
      verticalCoverage >= minimumAxisCoverage;

  int get decile => isComplete ? 10 : (progress * 10).floor();

  bool get hasStarted => eventCount > 0;
}

/// Serializes pointer samples and feeds them into the current pool ceremony.
class EntropyCeremonyCubit extends Cubit<EntropyCeremonyState> {
  EntropyCeremonyCubit({
    required this._mixEntropyUsecase,
    this.motionPort,
    this.motionCaptureEnabled = _captureEnabled,
    this.elapsedMicroseconds,
  }) : super(const EntropyCeremonyState());

  static const serializedSampleBytes = 128;
  static const serializedMotionSampleBytes = 80;

  final MixEntropyUsecase _mixEntropyUsecase;
  final EntropyMotionPort? motionPort;
  final bool motionCaptureEnabled;
  final ElapsedMicroseconds? elapsedMicroseconds;
  final Stopwatch _stopwatch = Stopwatch();
  StreamSubscription<EntropyMotionSample>? _motionSubscription;
  bool _started = false;
  bool _motionShouldRun = false;
  (double, double)? _lastAcceptedPosition;
  int? _firstAcceptedMicros;
  int _motionSampleCount = 0;
  int _motionSegment = 0;
  double? _minimumNormalizedX;
  double? _maximumNormalizedX;
  double? _minimumNormalizedY;
  double? _maximumNormalizedY;

  void start() {
    if (_started) return;
    _started = true;
    _stopwatch.start();
    _mixEntropyUsecase.begin();
    _capture('begin', {
      'version': 2,
      'pointerSampleBytes': serializedSampleBytes,
      'motionSampleBytes': serializedMotionSampleBytes,
      'requiredSamples': EntropyCeremonyState.targetEventCount,
    });
    _motionShouldRun = true;
    _startMotionCapture();
  }

  Future<void> pauseMotionCapture() async {
    _motionShouldRun = false;
    await _stopMotionCapture();
  }

  void resumeMotionCapture() {
    if (!_started || state.isComplete) return;
    _motionShouldRun = true;
    _startMotionCapture();
  }

  /// Returns whether this sample was mixed and counted toward completion.
  bool addPointerSample({
    required PointerSampleKind kind,
    required int pointer,
    required int deviceKind,
    required double x,
    required double y,
    required double canvasWidth,
    required double canvasHeight,
    required double dx,
    required double dy,
    required int timestampMicros,
    required double pressure,
    required double radiusMajor,
    required double radiusMinor,
    required double size,
    required double orientation,
    required double tilt,
    required bool synthesized,
  }) {
    if (!_started) {
      throw StateError('Entropy ceremony has not started');
    }
    if (state.isComplete || synthesized) return false;

    final position = (x, y);
    if (!x.isFinite ||
        !y.isFinite ||
        !dx.isFinite ||
        !dy.isFinite ||
        !canvasWidth.isFinite ||
        !canvasHeight.isFinite ||
        canvasWidth <= 0 ||
        canvasHeight <= 0 ||
        !pressure.isFinite ||
        !radiusMajor.isFinite ||
        !radiusMinor.isFinite ||
        !size.isFinite ||
        !orientation.isFinite ||
        !tilt.isFinite ||
        pointer < 0 ||
        deviceKind < 0 ||
        timestampMicros < 0 ||
        pressure < 0 ||
        radiusMajor < 0 ||
        radiusMinor < 0 ||
        size < 0 ||
        tilt < 0 ||
        (kind == PointerSampleKind.move && position == _lastAcceptedPosition)) {
      return false;
    }

    final elapsedTicks = _stopwatch.elapsedTicks;
    final elapsedMicros =
        elapsedMicroseconds?.call() ?? _stopwatch.elapsedMicroseconds;
    final sequence = state.eventCount;
    final bytes = Uint8List(serializedSampleBytes);
    final view = ByteData.view(bytes.buffer);
    view.setUint64(0, kind.index);
    view.setUint64(8, pointer);
    view.setUint64(16, sequence);
    view.setUint64(24, deviceKind);
    view.setFloat64(32, x);
    view.setFloat64(40, y);
    view.setFloat64(48, dx);
    view.setFloat64(56, dy);
    view.setUint64(64, timestampMicros);
    view.setUint64(72, elapsedTicks);
    view.setFloat64(80, pressure);
    view.setFloat64(88, radiusMajor);
    view.setFloat64(96, radiusMinor);
    view.setFloat64(104, size);
    view.setFloat64(112, orientation);
    view.setFloat64(120, tilt);

    try {
      _mixEntropyUsecase.execute(bytes);
      _capture('sample', {
        'index': state.eventCount,
        'elapsedMicros': elapsedMicros,
        'bytes': base64Encode(bytes),
      });
    } finally {
      _zero(bytes);
    }

    _lastAcceptedPosition = position;
    final nextCount = state.eventCount + 1;
    final firstAcceptedMicros = _firstAcceptedMicros ?? elapsedMicros;
    _firstAcceptedMicros = firstAcceptedMicros;

    final normalizedX = (x / canvasWidth).clamp(0.0, 1.0).toDouble();
    final normalizedY = (y / canvasHeight).clamp(0.0, 1.0).toDouble();
    _minimumNormalizedX = math.min(
      _minimumNormalizedX ?? normalizedX,
      normalizedX,
    );
    _maximumNormalizedX = math.max(
      _maximumNormalizedX ?? normalizedX,
      normalizedX,
    );
    _minimumNormalizedY = math.min(
      _minimumNormalizedY ?? normalizedY,
      normalizedY,
    );
    _maximumNormalizedY = math.max(
      _maximumNormalizedY ?? normalizedY,
      normalizedY,
    );

    final nextState = EntropyCeremonyState(
      eventCount: nextCount,
      elapsedDurationMicros: math.max(0, elapsedMicros - firstAcceptedMicros),
      horizontalCoverage: _maximumNormalizedX! - _minimumNormalizedX!,
      verticalCoverage: _maximumNormalizedY! - _minimumNormalizedY!,
      isComplete: false,
    );
    final completesOnLift =
        kind == PointerSampleKind.up && nextState.gatesSatisfied;
    final emittedState = completesOnLift
        ? EntropyCeremonyState(
            eventCount: nextState.eventCount,
            elapsedDurationMicros: nextState.elapsedDurationMicros,
            horizontalCoverage: nextState.horizontalCoverage,
            verticalCoverage: nextState.verticalCoverage,
            isComplete: true,
          )
        : nextState;
    if (completesOnLift) {
      _mixEntropyUsecase.complete();
      _capture('end', {
        'acceptedSamples': nextCount,
        'motionSamples': _motionSampleCount,
      });
      _motionShouldRun = false;
      unawaited(_stopMotionCapture());
    }
    emit(emittedState);
    return true;
  }

  @override
  Future<void> close() async {
    _motionShouldRun = false;
    await _stopMotionCapture();
    await super.close();
  }

  void _startMotionCapture() {
    if (!motionCaptureEnabled ||
        !_motionShouldRun ||
        motionPort == null ||
        _motionSubscription != null) {
      return;
    }

    final segment = ++_motionSegment;
    _capture('motion_start', {'segment': segment});
    _motionSubscription = motionPort!.samples().listen(
      _mixMotionSample,
      onError: (_) => _capture('motion_error', {'segment': segment}),
      onDone: () {
        if (_motionSegment == segment) _motionSubscription = null;
        _capture('motion_done', {'segment': segment});
      },
    );
  }

  Future<void> _stopMotionCapture() async {
    final subscription = _motionSubscription;
    _motionSubscription = null;
    await subscription?.cancel();
  }

  void _mixMotionSample(EntropyMotionSample sample) {
    if (!_started || state.isComplete || !_motionShouldRun) return;

    final bytes = Uint8List(serializedMotionSampleBytes);
    final view = ByteData.view(bytes.buffer);
    final sampleIndex = _motionSampleCount;
    view.setUint64(0, sample.kind.index);
    view.setUint64(8, sampleIndex);
    view.setUint64(16, sample.nativeSequence);
    view.setUint64(24, sample.sensorTimestampNanos);
    view.setUint64(32, sample.nativeArrivalTimestampNanos);
    view.setUint64(40, _stopwatch.elapsedTicks);
    view.setFloat64(48, sample.x);
    view.setFloat64(56, sample.y);
    view.setFloat64(64, sample.z);
    view.setInt64(72, sample.accuracy);

    final elapsedMicros =
        elapsedMicroseconds?.call() ?? _stopwatch.elapsedMicroseconds;
    try {
      _mixEntropyUsecase.mixMotion(bytes);
      _capture('motion', {
        'index': sampleIndex,
        'elapsedMicros': elapsedMicros,
        'bytes': base64Encode(bytes),
      });
      _motionSampleCount++;
    } finally {
      _zero(bytes);
    }
  }

  static void _zero(Uint8List bytes) {
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }

  static void _capture(String type, Map<String, Object> fields) {
    if (!kDebugMode || !_captureEnabled) return;

    // Deliberately bypasses the application logger: raw gesture traces are
    // research data and must never enter support logs or Sentry. Capture is
    // best-effort and must not be able to interrupt the entropy ceremony.
    try {
      debugPrintSynchronously(
        '$_capturePrefix${jsonEncode({'type': type, ...fields})}',
      );
    } catch (_) {}
  }
}
