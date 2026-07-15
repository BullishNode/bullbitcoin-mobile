import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/features/get_paid_settings/data/drift_get_paid_settings_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SqliteDatabase database;
  late DriftGetPaidSettingsRepository repository;

  setUp(() {
    database = SqliteDatabase(NativeDatabase.memory());
    repository = DriftGetPaidSettingsRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  test('returns the defaults (backup on, disclosure not acknowledged) when the '
      'row is absent', () async {
    final settings = await repository.fetch();

    expect(settings.automatedBackupEnabled, isTrue);
    expect(settings.backupDisclosureAcknowledged, isFalse);
  });

  test('round-trips the automated backup toggle', () async {
    await repository.setAutomatedBackupEnabled(false);

    final settings = await repository.fetch();

    expect(settings.automatedBackupEnabled, isFalse);
    // Toggling the backup flag must not touch the disclosure ack.
    expect(settings.backupDisclosureAcknowledged, isFalse);
  });

  test(
    'the ack setter writes both the ack and the chosen toggle value',
    () async {
      await repository.setBackupDisclosureAcknowledged(
        automatedBackupEnabled: false,
      );

      final settings = await repository.fetch();

      expect(settings.backupDisclosureAcknowledged, isTrue);
      expect(settings.automatedBackupEnabled, isFalse);
    },
  );

  test('the toggle setter preserves a previously recorded ack', () async {
    await repository.setBackupDisclosureAcknowledged(
      automatedBackupEnabled: true,
    );

    await repository.setAutomatedBackupEnabled(false);

    final settings = await repository.fetch();

    expect(settings.backupDisclosureAcknowledged, isTrue);
    expect(settings.automatedBackupEnabled, isFalse);
  });
}
