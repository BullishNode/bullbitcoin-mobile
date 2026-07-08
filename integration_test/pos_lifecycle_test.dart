import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';
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

// SPEC-POS-01 — the fake-backed Point of Sale lifecycle round-trip.
//
// AUTHORED-BUT-CI-ONLY (flagged deviation, same rationale as SPEC-PP-01 /
// get_paid_backup_roundtrip_test.dart): excluded from the aggregated L1 suite
// (tool/gen_all_test.dart skip set) because the live app-startup timers/blocs
// make an app-process run non-deterministic. The deterministic gates for this
// feature are the L0 usecase/cubit suites; this file is retained for a
// dedicated CI job with a per-test relay-only harness.

const _nym = 'alice';

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  test('provision -> backup -> wipe -> recover restores wallet 103, and the '
      'DG-3 heal classifies the POS read-only', () async {
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

    // Register the nym (creates wallet 101) then provision the POS (derives +
    // records wallet 103 and saves the row with descriptor + kind=pos).
    await locator<LightningAddressFacade>().registerWalletOwned(nym: _nym);
    final created = await locator<PosFacade>().provision(
      const PosProvisionCommand(label: 'My Till', displayCurrency: 'CAD'),
    );
    expect(created.nym, _nym);
    expect(created.isActive, isTrue);
    // DG-P5: the terminal URL is constructed client-side as {base}/{nym}/pos.
    expect(created.terminalUrl, endsWith('/$_nym/pos'));
    // The save signed a non-empty 103 descriptor and kind=pos (KR-1/KR-3).
    final savedRequest = bullnym.saveDonationPageCalls.single;
    expect(savedRequest.ctDescriptor, isNotEmpty);
    expect(savedRequest.kind, 'pos');
    expect(savedRequest.enabled, isTrue);
    final writesAfterCreate = bullnym.totalDonationWriteCalls;

    // Wipe local state; the relay + bullnym fakes survive (server-side state).
    await wipeAppState(locator);
    await locator<CreateDefaultWalletsUsecase>().execute(
      mnemonicWords: getPaidFixtureMnemonicWords,
    );

    // Drive the real remote recovery: restores the manifest (101 + 103) under
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

    // The DG-3 heal is READ-ONLY: recovery must not have written to the POS.
    expect(bullnym.totalDonationWriteCalls, writesAfterCreate);

    // Heal matrix via the real facade against the surviving server state.
    // live: pos present + not archived.
    bullnym.posMode = FakePosMode.normal;
    final live = await locator<PosFacade>().ensurePosLive();
    expect(live.liveness, PosLiveness.live);

    // archivedByUser: respected, no write.
    bullnym.posMode = FakePosMode.archived;
    final archived = await locator<PosFacade>().ensurePosLive();
    expect(archived.liveness, PosLiveness.archivedByUser);

    // needsReactivation: registration live but pos row purged; no write.
    bullnym.posMode = FakePosMode.missing;
    final missing = await locator<PosFacade>().ensurePosLive();
    expect(missing.liveness, PosLiveness.needsReactivation);

    // Every heal path issued ZERO writes (§8.7 / T-NOCLOBBER).
    expect(bullnym.totalDonationWriteCalls, writesAfterCreate);
  });

  test('coexistence: a Donation Page (102) and a POS (103) under one nym are '
      'independent - provisioning/healing one never touches the other',
      () async {
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

    await locator<LightningAddressFacade>().registerWalletOwned(nym: _nym);

    // Create the page (102) first, then provision the POS (103).
    final page = await locator<PaymentPageFacade>().save(
      const SavePaymentPageCommand(
        header: 'Tip me',
        description: 'Support my work',
        displayCurrency: 'CAD',
      ),
    );
    expect(page.isActive, isTrue);

    await locator<PosFacade>().provision(
      const PosProvisionCommand(label: 'My Till', displayCurrency: 'CAD'),
    );

    // Both rows coexist and are independently readable.
    final foundPage = await locator<PaymentPageFacade>().find(nym: _nym);
    final foundPos = await locator<PosFacade>().find(nym: _nym);
    expect(foundPage, isNotNull);
    expect(foundPos, isNotNull);
    expect(foundPage!.header, 'Tip me');
    expect(foundPos!.label, 'My Till');
    expect(foundPage.isActive, isTrue);
    expect(foundPos.isActive, isTrue);

    // Archiving the POS leaves the page live and untouched (and vice-versa).
    await locator<PosFacade>().archive();
    final pageAfterPosArchive =
        await locator<PaymentPageFacade>().find(nym: _nym);
    expect(pageAfterPosArchive, isNotNull);
    expect(pageAfterPosArchive!.isActive, isTrue);
  });
}
