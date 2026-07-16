import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/domain/repositories/wallet_preferences_repository.dart';
import 'package:bb_mobile/core/wallet/domain/repositories/wallet_utxo_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/apply_recovered_wallet_preferences_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallet_preferences_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/watch_wallet_preference_changes_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/watch_wallet_utxo_freeze_changes_usecase.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/labels_bip329_wallet_metadata_contributor.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_utxo_freeze_metadata_contributor.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_preferences_metadata_contributor.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_relay_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_graph_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_safe_head_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_snapshot_composition_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/build_wallet_metadata_snapshot_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/fetch_wallet_metadata_recovery_plan_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/publish_wallet_metadata_backup_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/wallet_metadata_backup_locator.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

class _MockLabelsFacade extends Mock implements LabelsFacade {}

class _MockWalletUtxoRepository extends Mock implements WalletUtxoRepository {}

class _MockWalletPreferencesRepository extends Mock
    implements WalletPreferencesRepository {}

class _MockNostrIdentityFacade extends Mock implements NostrIdentityFacade {}

void main() {
  test(
    'resolves independent default-off controls and catch-up state',
    () async {
      final database = SqliteDatabase(NativeDatabase.memory());
      final locator = GetIt.asNewInstance();
      addTearDown(() async {
        await locator.reset();
        await database.close();
      });
      locator.registerSingleton<SqliteDatabase>(database);
      WalletMetadataBackupLocator.setup(locator);

      final first = locator<WalletMetadataBackupFacade>();
      final second = locator<WalletMetadataBackupFacade>();
      expect(second, same(first));

      final initial = _requireOk(await first.getState());
      expect(initial.enabled, isFalse);
      expect(initial.relayDisclosureAcknowledged, isFalse);

      final enabled = _requireOk(await first.setEnabled(true));
      expect(enabled.enabled, isTrue);
      expect(enabled.dirty, isTrue);
      expect(enabled.dirtyRevision, 1);
      expect(enabled.canContactRelays, isFalse);

      final acknowledged = _requireOk(await first.acknowledgeRelayDisclosure());
      expect(acknowledged.enabled, isTrue);
      expect(acknowledged.relayDisclosureAcknowledged, isTrue);
      expect(acknowledged.canAttemptPublication, isTrue);

      final persisted = _requireOk(await first.getState());
      expect(persisted.enabled, isTrue);
      expect(persisted.relayDisclosureAcknowledged, isTrue);
      expect(persisted.dirty, isTrue);
    },
  );

  test(
    'local changes remain dirty while metadata relay access is off',
    () async {
      final database = SqliteDatabase(NativeDatabase.memory());
      final locator = GetIt.asNewInstance();
      addTearDown(() async {
        await locator.reset();
        await database.close();
      });
      locator.registerSingleton<SqliteDatabase>(database);
      WalletMetadataBackupLocator.setup(locator);
      final facade = locator<WalletMetadataBackupFacade>();

      final state = _requireOk(await facade.markDirty());

      expect(state.enabled, isFalse);
      expect(state.relayDisclosureAcknowledged, isFalse);
      expect(state.dirty, isTrue);
      expect(state.dirtyRevision, 1);
      expect(state.canContactRelays, isFalse);
    },
  );

  test('resolves the labels contributor through the labels facade', () async {
    final database = SqliteDatabase(NativeDatabase.memory());
    final locator = GetIt.asNewInstance();
    addTearDown(() async {
      await locator.reset();
      await database.close();
    });
    locator.registerSingleton<SqliteDatabase>(database);
    locator.registerSingleton<LabelsFacade>(_MockLabelsFacade());
    WalletMetadataBackupLocator.setup(locator);

    final contributor = locator<LabelsBip329WalletMetadataContributor>();

    expect(contributor.recordType, 'labels.bip329');
  });

  test('resolves the freeze contributor through the wallet domain', () async {
    final database = SqliteDatabase(NativeDatabase.memory());
    final locator = GetIt.asNewInstance();
    addTearDown(() async {
      await locator.reset();
      await database.close();
    });
    locator.registerSingleton<SqliteDatabase>(database);
    final repository = _MockWalletUtxoRepository();
    locator.registerSingleton<WalletUtxoRepository>(repository);
    locator.registerSingleton<WatchWalletUtxoFreezeChangesUsecase>(
      WatchWalletUtxoFreezeChangesUsecase(repository),
    );
    WalletMetadataBackupLocator.setup(locator);

    final contributor = locator<WalletUtxoFreezeMetadataContributor>();

    expect(contributor.recordType, 'wallet.utxo_freeze');
  });

  test('resolves the preferences contributor through its use case', () async {
    final database = SqliteDatabase(NativeDatabase.memory());
    final locator = GetIt.asNewInstance();
    addTearDown(() async {
      await locator.reset();
      await database.close();
    });
    locator.registerSingleton<SqliteDatabase>(database);
    final repository = _MockWalletPreferencesRepository();
    locator.registerSingleton<GetWalletPreferencesUsecase>(
      GetWalletPreferencesUsecase(repository),
    );
    locator.registerSingleton<ApplyRecoveredWalletPreferencesUsecase>(
      ApplyRecoveredWalletPreferencesUsecase(repository),
    );
    locator.registerSingleton<WatchWalletPreferenceChangesUsecase>(
      WatchWalletPreferenceChangesUsecase(repository),
    );
    WalletMetadataBackupLocator.setup(locator);

    final contributor = locator<WalletPreferencesMetadataContributor>();

    expect(contributor.recordType, 'wallet.preferences');
  });

  test(
    'resolves publication and recovery coordinators through feature ports',
    () async {
      final database = SqliteDatabase(NativeDatabase.memory());
      final locator = GetIt.asNewInstance();
      addTearDown(() async {
        await locator.reset();
        await database.close();
      });
      locator.registerSingleton<SqliteDatabase>(database);
      locator.registerSingleton<Bip85RegistryFacade>(
        const Bip85RegistryFacade(),
      );
      locator.registerSingleton<Clock>(const SystemClock());
      locator.registerSingleton<NostrIdentityFacade>(
        _MockNostrIdentityFacade(),
      );
      locator.registerSingleton<LabelsFacade>(_MockLabelsFacade());
      final utxoRepository = _MockWalletUtxoRepository();
      locator.registerSingleton<WalletUtxoRepository>(utxoRepository);
      locator.registerSingleton<WatchWalletUtxoFreezeChangesUsecase>(
        WatchWalletUtxoFreezeChangesUsecase(utxoRepository),
      );
      final preferencesRepository = _MockWalletPreferencesRepository();
      locator.registerSingleton<GetWalletPreferencesUsecase>(
        GetWalletPreferencesUsecase(preferencesRepository),
      );
      locator.registerSingleton<ApplyRecoveredWalletPreferencesUsecase>(
        ApplyRecoveredWalletPreferencesUsecase(preferencesRepository),
      );
      locator.registerSingleton<WatchWalletPreferenceChangesUsecase>(
        WatchWalletPreferenceChangesUsecase(preferencesRepository),
      );
      WalletMetadataBackupLocator.setup(locator);

      expect(locator<BuildWalletMetadataSnapshotUsecase>(), isNotNull);
      expect(locator<WalletMetadataSnapshotCompositionRepository>(), isNotNull);
      expect(locator<WalletMetadataRelayRepository>(), isNotNull);
      expect(locator<WalletMetadataGraphRepository>(), isNotNull);
      expect(locator<WalletMetadataSafeHeadRepository>(), isNotNull);
      expect(locator<PublishWalletMetadataBackupUsecase>(), isNotNull);
      expect(locator<FetchWalletMetadataRecoveryPlanUsecase>(), isNotNull);
    },
  );
}

WalletMetadataBackupState _requireOk(
  Result<WalletMetadataBackupState, WalletMetadataBackupFailure> result,
) {
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw TestFailure(
      'expected Ok, got ${failure.runtimeType}',
    ),
  };
}
