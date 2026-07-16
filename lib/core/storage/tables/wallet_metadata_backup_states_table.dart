import 'package:drift/drift.dart';

@DataClassName('WalletMetadataBackupStateRow')
class WalletMetadataBackupStates extends Table {
  IntColumn get id => integer()(); // single row, id == 1
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();
  BoolColumn get relayDisclosureAcknowledged =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();
  IntColumn get dirtyRevision => integer().withDefault(const Constant(0))();
  IntColumn get lastAttemptedAt => integer().nullable()();
  IntColumn get lastAcceptedAt => integer().nullable()();
  TextColumn get lastVerifiedRootEventId => text().nullable()();
  IntColumn get lastVerifiedSnapshotRevision => integer().nullable()();
  TextColumn get lastVerifiedContentHash => text().nullable()();
  IntColumn get lastVerifiedAt => integer().nullable()();
  TextColumn get blockedReason => text().nullable()();
  TextColumn get blockedRootEventId => text().nullable()();
  IntColumn get blockedEnvelopeVersion => integer().nullable()();
  IntColumn get blockedEventCreatedAt => integer().nullable()();
  IntColumn get blockedObservedAt => integer().nullable()();
  TextColumn get recoveryBlockedReason => text().nullable()();
  TextColumn get recoveryBlockedRootEventId => text().nullable()();
  IntColumn get recoveryBlockedSnapshotRevision => integer().nullable()();
  IntColumn get recoveryBlockedEventCreatedAt => integer().nullable()();
  IntColumn get recoveryBlockedObservedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
