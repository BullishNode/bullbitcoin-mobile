import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/backup_settings_failure.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/backup_wallet_now_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/set_wallet_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fake_bullnym_client.dart';
import 'support/get_paid_fixtures.dart';
import 'support/get_paid_test_harness.dart';
import 'support/integration_test_profile.dart';

// SPEC-PP-01 - the fake-backed Donation Page lifecycle round-trip.
//
// Runs in the aggregated L1 suite against the deterministic fake Bullnym
// backend. Product lifecycle journeys must not exist only as unaudited files.

const _nym = 'alice';

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  await initializeIntegrationTestApp(isInitialized: isInitialized);

  group('fake-backed Donation Page lifecycle', () {
    late FakeBullnymClient bullnym;

    setUp(() async {
      bullnym = FakeBullnymClient();
      await installFakeBullnymClient(bullnym);
      await wipeGetPaidLocalState();
      await locator<CreateDefaultWalletsUsecase>().execute(
        mnemonicWords: getPaidFixtureMnemonicWords,
      );
    });

    tearDown(wipeGetPaidLocalState);

    test(
      'create -> backup -> recover restores wallet 102, and the '
      'DG-3 heal classifies the page read-only',
      timeout: const Timeout(Duration(minutes: 1)),
      () async {
        expect(
          await locator<SetWalletBackupEnabledUsecase>().execute(true),
          isA<Ok<void, BackupSettingsFailure>>(),
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
        // The save signed a non-empty descriptor and kind=payment_page.
        final savedRequest = bullnym.saveDonationPageCalls.single;
        expect(savedRequest.ctDescriptor, isNotEmpty);
        expect(savedRequest.kind, 'payment_page');
        expect(savedRequest.enabled, isTrue);
        final writesAfterCreate = bullnym.totalDonationWriteCalls;

        expect(
          await locator<BackupWalletNowUsecase>().execute(),
          isA<Ok<void, BackupSettingsFailure>>(),
        );

        // Simulate a fresh local install. The fake keeps the remote backup and
        // Donation Page so recovery exercises server-backed state.
        await wipeGetPaidLocalState();
        await locator<CreateDefaultWalletsUsecase>().execute(
          mnemonicWords: getPaidFixtureMnemonicWords,
        );

        final recovered = await locator<RemoteKeychainRecoveryFacade>()
            .recover();
        expect(
          recovered.status,
          RemoteKeychainRecoveryStatus.restored,
          reason:
              'restored=${recovered.restoredCount}, failed=${recovered.failedCount}',
        );
        expect(recovered.restoredCount, greaterThan(0));
        final recoveredWallets = await Future.wait(
          recovered.createdWalletIds.map(
            (id) => locator<WalletRepository>().getWallet(id),
          ),
        );
        expect(
          recoveredWallets.any(
            (wallet) => wallet?.label == 'Payment Page Liquid',
          ),
          isTrue,
        );
        final recoveredPage = await locator<PaymentPageFacade>()
            .ensurePageLive();
        expect(recoveredPage.liveness, PaymentPageLiveness.live);

        // The DG-3 heal is read-only: recovery must not have written to the page.
        expect(bullnym.totalDonationWriteCalls, writesAfterCreate);

        // Heal matrix via the real facade against the surviving server state.
        bullnym.donationPageMode = FakeDonationPageMode.normal;
        final live = await locator<PaymentPageFacade>().ensurePageLive();
        expect(live.liveness, PaymentPageLiveness.live);

        bullnym.donationPageMode = FakeDonationPageMode.archived;
        final archived = await locator<PaymentPageFacade>().ensurePageLive();
        expect(archived.liveness, PaymentPageLiveness.archivedByUser);

        bullnym.donationPageMode = FakeDonationPageMode.missing;
        final missing = await locator<PaymentPageFacade>().ensurePageLive();
        expect(missing.liveness, PaymentPageLiveness.needsReactivation);

        expect(bullnym.totalDonationWriteCalls, writesAfterCreate);
      },
    );
  });
}
