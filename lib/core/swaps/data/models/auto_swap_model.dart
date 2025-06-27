import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/swaps/domain/entity/auto_swap.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'auto_swap_model.freezed.dart';

@freezed
sealed class AutoSwapModel with _$AutoSwapModel {
  const factory AutoSwapModel({
    @Default(false) bool enabled,
    @Default(1000000) int balanceThresholdSats,
    @Default(3.0) double feeThresholdPercent,
    @Default(false) bool blockTillNextExecution,
    @Default(false) bool alwaysBlock,
  }) = _AutoSwapModel;

  const AutoSwapModel._();

  factory AutoSwapModel.fromEntity(AutoSwap entity) {
    return AutoSwapModel(
      enabled: entity.enabled,
      balanceThresholdSats: entity.balanceThresholdSats,
      feeThresholdPercent: entity.feeThresholdPercent,
      blockTillNextExecution: entity.blockTillNextExecution,
      alwaysBlock: entity.alwaysBlock,
    );
  }

  AutoSwap toEntity() {
    return AutoSwap(
      enabled: enabled,
      balanceThresholdSats: balanceThresholdSats,
      feeThresholdPercent: feeThresholdPercent,
      blockTillNextExecution: blockTillNextExecution,
      alwaysBlock: alwaysBlock,
    );
  }

  factory AutoSwapModel.fromSqlite(AutoSwapRow row) {
    return AutoSwapModel(
      enabled: row.enabled,
      balanceThresholdSats: row.balanceThresholdSats,
      feeThresholdPercent: row.feeThresholdPercent,
      blockTillNextExecution: row.blockTillNextExecution,
      alwaysBlock: row.alwaysBlock,
    );
  }

  AutoSwapRow toSqlite() {
    return AutoSwapRow(
      id: 1,
      enabled: enabled,
      balanceThresholdSats: balanceThresholdSats,
      feeThresholdPercent: feeThresholdPercent,
      blockTillNextExecution: blockTillNextExecution,
      alwaysBlock: alwaysBlock,
    );
  }
}
