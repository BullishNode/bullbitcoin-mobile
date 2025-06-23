import 'package:freezed_annotation/freezed_annotation.dart';

part 'auto_swap.freezed.dart';
part 'auto_swap.g.dart';

@freezed
sealed class AutoSwap with _$AutoSwap {
  const factory AutoSwap({
    @Default(false) bool enabled,
    @Default(1000000) int balanceThresholdSats,
    @Default(3) int feeThresholdPercent,
    @Default(false) bool blockTillNextExecution,
    @Default(false) bool alwaysBlock,
  }) = _AutoSwap;

  const AutoSwap._();

  factory AutoSwap.fromJson(Map<String, dynamic> json) =>
      _$AutoSwapFromJson(json);

  bool passedRequiredBalance(int balanceSat) {
    return balanceSat >= balanceThresholdSats * 2 && enabled;
  }

  bool withinFeeThreshold(double currentFeeRatio) {
    return feeThresholdPercent.toDouble() >= currentFeeRatio;
  }

  int swapAmount(int balanceSat) {
    return balanceSat - balanceThresholdSats;
  }
}
