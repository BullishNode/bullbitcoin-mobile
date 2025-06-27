import 'package:drift/drift.dart';

@DataClassName('AutoSwapRow')
class AutoSwap extends Table {
  IntColumn get id => integer().autoIncrement()();
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();
  IntColumn get balanceThresholdSats => integer()();
  RealColumn get feeThresholdPercent => real()();
  BoolColumn get blockTillNextExecution =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get alwaysBlock => boolean().withDefault(const Constant(false))();
}
