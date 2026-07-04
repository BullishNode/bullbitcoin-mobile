import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_settings.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_settings_default_wallet_xprv_port.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_settings_error.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/repositories/get_paid_settings_repository.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/usecases/publish_automated_keychain_backup_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/nostr_relay_policy/public/nostr_relay_policy_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _FakeRepository implements GetPaidSettingsRepository {
  _FakeRepository(this._settings);

  GetPaidSettings _settings;

  @override
  Future<GetPaidSettings> fetch() async => _settings;

  @override
  Future<void> setAutomatedBackupEnabled(bool enabled) async {
    _settings = _settings.copyWith(automatedBackupEnabled: enabled);
  }

  @override
  Future<void> setBackupDisclosureAcknowledged({
    required bool automatedBackupEnabled,
  }) async {
    _settings = GetPaidSettings(
      automatedBackupEnabled: automatedBackupEnabled,
      backupDisclosureAcknowledged: true,
    );
  }
}

class _FakeXprvPort implements GetPaidSettingsDefaultWalletXprvPort {
  _FakeXprvPort({this.throwOnDerive = false});

  final bool throwOnDerive;
  int deriveCalls = 0;

  @override
  Future<GetPaidSettingsDefaultWalletXprv> deriveDefaultWalletXprv() async {
    deriveCalls++;
    if (throwOnDerive) {
      throw GetPaidSettingsStorageException();
    }
    return const GetPaidSettingsDefaultWalletXprv(
      xprvBase58: 'xprv-base58',
      parentFingerprint: 'fedcba98',
    );
  }
}

class _MockKeychainManifestFacade extends Mock
    implements KeychainManifestFacade {}

void main() {
  const relayPolicy = NostrRelayPolicyFacade();
  final expectedRelayUrls = relayPolicy
      .getPolicy()
      .defaultRelays
      .map((relay) => relay.url)
      .toList(growable: false);

  late _MockKeychainManifestFacade keychainManifest;

  PublishAutomatedKeychainBackupUsecase buildUsecase({
    required GetPaidSettings settings,
    _FakeXprvPort? xprvPort,
  }) {
    return PublishAutomatedKeychainBackupUsecase(
      repository: _FakeRepository(settings),
      xprvPort: xprvPort ?? _FakeXprvPort(),
      keychainManifest: keychainManifest,
      relayPolicy: relayPolicy,
    );
  }

  void stubPublishOk() {
    when(
      () => keychainManifest.publishEncryptedNostrSnapshot(
        parentFingerprint: any(named: 'parentFingerprint'),
        xprvBase58: any(named: 'xprvBase58'),
        relayUrls: any(named: 'relayUrls'),
      ),
    ).thenAnswer((_) async {});
  }

  setUp(() {
    keychainManifest = _MockKeychainManifestFacade();
  });

  test('does not publish when the toggle is off (even with ack)', () async {
    stubPublishOk();
    final usecase = buildUsecase(
      settings: const GetPaidSettings(
        automatedBackupEnabled: false,
        backupDisclosureAcknowledged: true,
      ),
    );

    await usecase.execute();

    verifyNever(
      () => keychainManifest.publishEncryptedNostrSnapshot(
        parentFingerprint: any(named: 'parentFingerprint'),
        xprvBase58: any(named: 'xprvBase58'),
        relayUrls: any(named: 'relayUrls'),
      ),
    );
  });

  test('does not publish when the disclosure is not acknowledged', () async {
    stubPublishOk();
    final usecase = buildUsecase(
      settings: const GetPaidSettings(
        automatedBackupEnabled: true,
        backupDisclosureAcknowledged: false,
      ),
    );

    await usecase.execute();

    verifyNever(
      () => keychainManifest.publishEncryptedNostrSnapshot(
        parentFingerprint: any(named: 'parentFingerprint'),
        xprvBase58: any(named: 'xprvBase58'),
        relayUrls: any(named: 'relayUrls'),
      ),
    );
  });

  test('publishes once with the policy relay URLs and the derived xprv when '
      'enabled and acknowledged', () async {
    stubPublishOk();
    final usecase = buildUsecase(
      settings: const GetPaidSettings(
        automatedBackupEnabled: true,
        backupDisclosureAcknowledged: true,
      ),
    );

    await usecase.execute();

    final captured = verify(
      () => keychainManifest.publishEncryptedNostrSnapshot(
        parentFingerprint: captureAny(named: 'parentFingerprint'),
        xprvBase58: captureAny(named: 'xprvBase58'),
        relayUrls: captureAny(named: 'relayUrls'),
      ),
    ).captured;

    expect(captured[0], 'fedcba98');
    expect(captured[1], 'xprv-base58');
    expect(captured[2], equals(expectedRelayUrls));
  });

  test('returns normally when the facade reports an empty inventory', () async {
    when(
      () => keychainManifest.publishEncryptedNostrSnapshot(
        parentFingerprint: any(named: 'parentFingerprint'),
        xprvBase58: any(named: 'xprvBase58'),
        relayUrls: any(named: 'relayUrls'),
      ),
    ).thenThrow(KeychainManifestEmptyInventoryException());
    final usecase = buildUsecase(
      settings: const GetPaidSettings(
        automatedBackupEnabled: true,
        backupDisclosureAcknowledged: true,
      ),
    );

    await expectLater(usecase.execute(), completes);
  });

  test('returns normally when the facade throws a generic failure', () async {
    when(
      () => keychainManifest.publishEncryptedNostrSnapshot(
        parentFingerprint: any(named: 'parentFingerprint'),
        xprvBase58: any(named: 'xprvBase58'),
        relayUrls: any(named: 'relayUrls'),
      ),
    ).thenThrow(Exception('relay failure'));
    final usecase = buildUsecase(
      settings: const GetPaidSettings(
        automatedBackupEnabled: true,
        backupDisclosureAcknowledged: true,
      ),
    );

    await expectLater(usecase.execute(), completes);
  });

  test('returns normally when the xprv port throws', () async {
    stubPublishOk();
    final usecase = buildUsecase(
      settings: const GetPaidSettings(
        automatedBackupEnabled: true,
        backupDisclosureAcknowledged: true,
      ),
      xprvPort: _FakeXprvPort(throwOnDerive: true),
    );

    await expectLater(usecase.execute(), completes);
    verifyNever(
      () => keychainManifest.publishEncryptedNostrSnapshot(
        parentFingerprint: any(named: 'parentFingerprint'),
        xprvBase58: any(named: 'xprvBase58'),
        relayUrls: any(named: 'relayUrls'),
      ),
    );
  });
}
