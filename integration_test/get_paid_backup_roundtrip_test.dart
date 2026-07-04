import 'dart:convert';

import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_service_port.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/complete_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_cubit.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_state.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fake_bullnym_client.dart';
import 'support/fake_nostr_relay.dart';
import 'support/get_paid_fixtures.dart';
import 'support/test_locator_overrides.dart';
import 'support/wipe_app_state.dart';

// SPEC-RT-01 / WIRE-01 / T-NOCONSENT against the app-process DI graph.
//
// AUTHORED-BUT-CI-ONLY (flagged deviation): excluded from the aggregated L1
// suite (tool/gen_all_test.dart skip set) because the live app-startup
// timers/blocs make an app-process run non-deterministic (the "Cannot add event
// while adding stream" / perpetual-timer hang the harness design flagged) — the
// same reason BOOT-01 proves boot via Bull.init rather than a full app pump.
// The DETERMINISTIC money-path gate is the domain-layer round-trip
// (test/features/get_paid_settings/get_paid_backup_wire_roundtrip_test.dart):
// real encrypt/sign/codec against the injectable relay-datasource connector.
// This file is retained for a dedicated CI job with a per-test relay-only
// harness.
const _pairingUrl =
    'https://btcpay.example.com/plugins/store123/samrock/protocol'
    '?otp=123&setup=btc,lbtc,btcln';

class _FakePairingService implements SamRockPairingServicePort {
  @override
  Future<SamRockPairingResponse> submitSetup({
    required Object request,
    required Object payload,
  }) async {
    return const SamRockPairingResponse(success: true);
  }
}

Future<void> _installBoundaries(FakeNostrRelay relay, FakeBullnymClient bullnym) async {
  await overrideBoundariesForTest(locator, relay: relay, bullnym: bullnym);
  await locator.unregister<SamRockPairingServicePort>();
  locator.registerLazySingleton<SamRockPairingServicePort>(
    () => _FakePairingService(),
  );
}

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  test('no consent acknowledgement means no relay publish (T-NOCONSENT)', () async {
    final relay = FakeNostrRelay();
    final bullnym = FakeBullnymClient();
    await wipeAppState(locator);
    await _installBoundaries(relay, bullnym);
    await locator<CreateDefaultWalletsUsecase>().execute(
      mnemonicWords: getPaidFixtureMnemonicWords,
    );

    // Toggle defaults ON but the disclosure is NOT acknowledged.
    await locator<CompleteBtcpaySamRockPairingUsecase>().execute(
      pairingUrl: _pairingUrl,
    );

    expect(relay.capturedEventFrames, isEmpty);
  });

  test('consent then creation publishes exactly one opaque NIP-33 event '
      '(WIRE-01)', () async {
    final relay = FakeNostrRelay();
    final bullnym = FakeBullnymClient();
    await wipeAppState(locator);
    await _installBoundaries(relay, bullnym);
    await locator<CreateDefaultWalletsUsecase>().execute(
      mnemonicWords: getPaidFixtureMnemonicWords,
    );
    await locator<GetPaidSettingsFacade>().acknowledgeBackupDisclosure(
      automatedBackupEnabled: true,
    );

    await locator<CompleteBtcpaySamRockPairingUsecase>().execute(
      pairingUrl: _pairingUrl,
    );

    // The manifest is a single replaceable event (not accumulated).
    expect(relay.capturedEventFrames, isNotEmpty);
    expect(relay.storedEventCount, 1);

    for (final frame in relay.capturedEventFrames) {
      final lower = frame.toLowerCase();
      expect(lower.contains('bullbitcoin'), isFalse);
      expect(lower.contains('recoverbull'), isFalse);
      expect(lower.contains('satoshiportal'), isFalse);

      final decoded = jsonDecode(frame) as List;
      expect(decoded[0], 'EVENT');
      final event = decoded[1] as Map<String, dynamic>;
      expect(event['kind'], 30078);
      final tags = (event['tags'] as List).cast<List<dynamic>>();
      expect(tags.any((t) => t[0] == 'd' && t[1] == 'manifest'), isTrue);
      // Opaque base64 content: decodes, and is not a cleartext JSON envelope.
      final content = event['content'] as String;
      expect(content.startsWith('{'), isFalse);
      expect(() => base64.decode(content), returnsNormally);
    }
  });

  test('a wiped-then-recovered wallet restores the backup byte-identically '
      'with posture (SPEC-RT-01)', () async {
    final relay = FakeNostrRelay();
    final bullnym = FakeBullnymClient();
    await wipeAppState(locator);
    await _installBoundaries(relay, bullnym);
    await locator<CreateDefaultWalletsUsecase>().execute(
      mnemonicWords: getPaidFixtureMnemonicWords,
    );
    await locator<GetPaidSettingsFacade>().acknowledgeBackupDisclosure(
      automatedBackupEnabled: true,
    );
    await locator<CompleteBtcpaySamRockPairingUsecase>().execute(
      pairingUrl: _pairingUrl,
    );

    final defaultWallet = (await locator<WalletRepository>().getWallets(
      onlyDefaults: true,
      onlyBitcoin: true,
    )).first;
    final bytesBefore = (await locator<KeychainManifestFacade>()
            .buildManifestFilePayload(defaultWallet.masterFingerprint))
        .payload;

    // Wipe app state; the relay + bullnym fakes survive.
    await wipeAppState(locator);
    await locator<CreateDefaultWalletsUsecase>().execute(
      mnemonicWords: getPaidFixtureMnemonicWords,
    );

    // Drive the real remote recovery. The ack was wiped, so the first start
    // demands the disclosure (proving the gate); accepting fetches from the
    // fake relay, decrypts under the restored default-wallet author key (same
    // seed => same key, KC-4 obligation 4), and restores.
    final cubit = locator<RemoteKeychainRecoveryCubit>();
    addTearDown(cubit.close);
    await cubit.start();
    expect(
      cubit.state.status,
      RemoteKeychainRecoveryStatus.requiresRelayDisclosure,
    );
    await cubit.acceptRelayDisclosure();
    expect(cubit.state.status, RemoteKeychainRecoveryStatus.restored);
    expect(cubit.state.restoredCount, greaterThan(0));

    final restoredDefault = (await locator<WalletRepository>().getWallets(
      onlyDefaults: true,
      onlyBitcoin: true,
    )).first;
    expect(restoredDefault.masterFingerprint, defaultWallet.masterFingerprint);

    final bytesAfter = (await locator<KeychainManifestFacade>()
            .buildManifestFilePayload(restoredDefault.masterFingerprint))
        .payload;

    // [F] freeze: the rebuilt manifest is byte-identical to the published one.
    expect(bytesAfter, bytesBefore);
  });
}
