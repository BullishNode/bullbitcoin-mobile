import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
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

// SPEC-PP-01 — the fake-backed Donation Page lifecycle round-trip.
//
// AUTHORED-BUT-CI-ONLY (flagged deviation, same rationale as
// get_paid_backup_roundtrip_test.dart): excluded from the aggregated L1 suite
// (tool/gen_all_test.dart skip set) because the live app-startup timers/blocs
// make an app-process run non-deterministic. The deterministic gates for this
// feature are the L0 usecase/cubit suites; this file is retained for a
// dedicated CI job with a per-test relay-only harness.

const _nym = 'alice';

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  test('create -> backup -> wipe -> recover restores wallet 102, and the '
      'DG-3 heal classifies the page read-only', () async {
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

    // Register the nym (creates wallet 101) then create the Donation Page
    // (derives + records wallet 102 and saves the page with descriptor + kind).
    await locator<LightningAddressFacade>().registerWalletOwned(nym: _nym);
    final created = await locator<PaymentPageFacade>().save(
      const SavePaymentPageCommand(
        header: 'Tip me',
        description: 'Support my work',
        displayCurrency: 'CAD',
      ),
    );
    expect(created.nym, _nym);
    expect(created.isActive, isTrue);
    // The save signed a non-empty descriptor and kind=payment_page (KR-1/KR-2).
    final savedRequest = bullnym.saveDonationPageCalls.single;
    expect(savedRequest.ctDescriptor, isNotEmpty);
    expect(savedRequest.kind, 'payment_page');
    expect(savedRequest.enabled, isTrue);
    final writesAfterCreate = bullnym.totalDonationWriteCalls;

    // Wipe local state; the relay + bullnym fakes survive (server-side state).
    await wipeAppState(locator);
    await locator<CreateDefaultWalletsUsecase>().execute(
      mnemonicWords: getPaidFixtureMnemonicWords,
    );

    // Drive the real remote recovery: restores the manifest (101 + 102) under
    // the restored default-wallet key (same seed => same key).
    final cubit = locator<RemoteKeychainRecoveryCubit>();
    addTearDown(cubit.close);
    await cubit.start();
    if (cubit.state.status ==
        RemoteKeychainRecoveryStatus.requiresRelayDisclosure) {
      await cubit.acceptRelayDisclosure();
    }
    expect(cubit.state.status, RemoteKeychainRecoveryStatus.restored);
    expect(cubit.state.restoredCount, greaterThan(0));

    // The DG-3 heal is READ-ONLY: recovery must not have written to the page.
    expect(bullnym.totalDonationWriteCalls, writesAfterCreate);

    // Heal matrix via the real facade against the surviving server state.
    // live: page present + not archived.
    bullnym.donationPageMode = FakeDonationPageMode.normal;
    final live = await locator<PaymentPageFacade>().ensurePageLive();
    expect(live.liveness, PaymentPageLiveness.live);

    // archivedByUser: respected, no write.
    bullnym.donationPageMode = FakeDonationPageMode.archived;
    final archived = await locator<PaymentPageFacade>().ensurePageLive();
    expect(archived.liveness, PaymentPageLiveness.archivedByUser);

    // needsReactivation: registration live but page row purged; no write.
    bullnym.donationPageMode = FakeDonationPageMode.missing;
    final missing = await locator<PaymentPageFacade>().ensurePageLive();
    expect(missing.liveness, PaymentPageLiveness.needsReactivation);

    // Every heal path issued ZERO writes (§8.5 / T-NOCLOBBER).
    expect(bullnym.totalDonationWriteCalls, writesAfterCreate);
  });
}
