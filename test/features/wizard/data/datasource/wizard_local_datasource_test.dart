import 'package:bb_mobile/features/wizard/data/datasource/wizard_local_datasource.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSharedPreferences extends Mock implements SharedPreferences {}

void main() {
  late _MockSharedPreferences preferences;
  late WizardLocalDatasourceImpl datasource;

  setUp(() {
    preferences = _MockSharedPreferences();
    datasource = WizardLocalDatasourceImpl(
      loadPreferences: () async => preferences,
    );
  });

  test('rejects a pending-version write that was not persisted', () async {
    when(
      () => preferences.setInt('wizard_pending_version', 2),
    ).thenAnswer((_) async => false);

    await expectLater(
      datasource.writePendingVersion(2),
      throwsA(isA<WizardPersistenceException>()),
    );
  });

  test('rejects a backup choice that was not persisted', () async {
    when(
      () => preferences.setBool('wizard_pending_metadata_backup', true),
    ).thenAnswer((_) async => false);

    await expectLater(
      datasource.writePendingMetadataBackup(true),
      throwsA(isA<WizardPersistenceException>()),
    );
  });

  test('rejects a completion marker that was not persisted', () async {
    when(
      () => preferences.setInt('wizard_completed_version', 2),
    ).thenAnswer((_) async => false);

    await expectLater(
      datasource.writeCompletedVersion(2),
      throwsA(isA<WizardPersistenceException>()),
    );
  });

  test('rejects cleanup when any removal was not persisted', () async {
    when(() => preferences.remove(any())).thenAnswer((invocation) async {
      return invocation.positionalArguments.single !=
          'wizard_pending_metadata_backup';
    });

    await expectLater(
      datasource.clearAllPending(),
      throwsA(isA<WizardPersistenceException>()),
    );
    verify(
      () => preferences.remove('wizard_pending_metadata_backup'),
    ).called(1);
  });
}
