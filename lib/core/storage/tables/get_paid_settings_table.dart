import 'package:drift/drift.dart';

@DataClassName('GetPaidSettingsRow')
class GetPaidSettings extends Table {
  IntColumn get id => integer()(); // single row, id == 1
  BoolColumn get automatedBackupEnabled =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get backupDisclosureAcknowledged =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
