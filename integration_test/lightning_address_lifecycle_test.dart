import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_error.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fake_bullnym_client.dart';
import 'support/fake_nostr_relay.dart';
import 'support/get_paid_fixtures.dart';
import 'support/test_locator_overrides.dart';
import 'support/wipe_app_state.dart';

// SPEC-LA-01 — the fake-backed Lightning Address lifecycle + liveness matrix.
//
// The Lightning Address feature had zero app-process coverage. Each case drives
// the REAL LightningAddressFacade against the fake bullnym boundary with a
// frozen clock: register (materializes reserved wallet 101), lookup, and the
// four liveness outcomes of ensureRegistrationLive (live / reregistered /
// needsReactivation / unreachable), plus a fail-closed nym conflict on register.
//
// Fork-only overlay; run directly:
//   fvm flutter test integration_test/lightning_address_lifecycle_test.dart
const _nym = 'alice';

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  // Fresh fakes + frozen clock + seeded default wallets per case. Returns the
  // bullnym fake so a case can drive its registration mode / injected error.
  Future<FakeBullnymClient> bootstrap() async {
    final relay = FakeNostrRelay();
    final bullnym = FakeBullnymClient();
    await wipeAppState(locator);
    await overrideBoundariesForTest(locator, relay: relay, bullnym: bullnym);
    await overrideClockForTest(locator);
    await locator<CreateDefaultWalletsUsecase>().execute(
      mnemonicWords: getPaidFixtureMnemonicWords,
    );
    await locator<GetPaidSettingsFacade>().acknowledgeBackupDisclosure(
      automatedBackupEnabled: true,
    );
    return bullnym;
  }

  test('register materializes wallet 101 and lookup reports active', () async {
    await bootstrap();
    final la = locator<LightningAddressFacade>();

    // prepareWallet materializes the reserved index-101 wallet.
    final prepared = await la.prepareWallet();
    expect(prepared.created, isTrue);
    expect(prepared.walletId, isNotEmpty);
    expect(prepared.ctDescriptor, isNotEmpty);

    await la.registerWalletOwned(nym: _nym);

    final status = await la.lookupWalletOwnedRegistration();
    expect(status.active, isTrue);
    expect(status.nym, _nym);
  });

  test('a lapsed registration silently re-registers (reregistered)', () async {
    final bullnym = await bootstrap();
    final la = locator<LightningAddressFacade>();
    await la.prepareWallet();
    await la.registerWalletOwned(nym: _nym);

    // Server now reports the nym inactive (a lapsed registration).
    bullnym.mode = FakeBullnymMode.inactiveWithPreviousNym;
    final outcome = await la.ensureRegistrationLive();
    expect(outcome.liveness, LightningAddressRegistrationLiveness.reregistered);
  });

  test('a genuinely missing registration needs reactivation', () async {
    final bullnym = await bootstrap();
    final la = locator<LightningAddressFacade>();
    await la.prepareWallet();

    bullnym.mode = FakeBullnymMode.registrationMissing;
    final outcome = await la.ensureRegistrationLive();
    expect(
      outcome.liveness,
      LightningAddressRegistrationLiveness.needsReactivation,
    );
  });

  test('a nym conflict on register FAILS CLOSED', () async {
    final bullnym = await bootstrap();
    final la = locator<LightningAddressFacade>();

    // The server rejects the registration (the nym is taken).
    bullnym.injectedRegistrationError =
        const BullnymException.serverRejectedRequest(
      code: 'NymTaken',
      diagnosticReason: 'nym taken',
      retryable: false,
    );
    await expectLater(
      la.registerWalletOwned(nym: _nym),
      throwsA(isA<LightningAddressException>()),
    );
  });

  test('server unreachable degrades loudly, never heals blindly', () async {
    final bullnym = await bootstrap();
    final la = locator<LightningAddressFacade>();
    await la.prepareWallet();

    bullnym.mode = FakeBullnymMode.serverUnreachable;
    final outcome = await la.ensureRegistrationLive();
    expect(outcome.liveness, LightningAddressRegistrationLiveness.unreachable);
  });
}
