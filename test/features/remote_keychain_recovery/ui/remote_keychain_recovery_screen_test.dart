import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_cubit.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_state.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/ui/screens/remote_keychain_recovery_screen.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

// A stub cubit seeded with a fixed state; start() and the actions are no-ops so
// the screen renders the seeded status without touching the locator or network.
class _StubRecoveryCubit extends Cubit<RemoteKeychainRecoveryState>
    implements RemoteKeychainRecoveryCubit {
  _StubRecoveryCubit(super.initialState);

  @override
  Future<void> start({bool acceptedThirdPartyRelayDisclosure = false}) async {}

  @override
  Future<void> acceptRelayDisclosure() async {}

  @override
  Future<void> restoreOlderManifest() async {}

  @override
  Future<void> startMetadataRecovery() async {}

  @override
  Future<void> skip() async {}
}

Future<void> _pump(
  WidgetTester tester,
  RemoteKeychainRecoveryState state,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider<RemoteKeychainRecoveryCubit>.value(
        value: _StubRecoveryCubit(state),
        child: const RemoteKeychainRecoveryScreen(fromOnboarding: false),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  const allStatuses = RemoteKeychainRecoveryStatus.values;

  testWidgets('every status renders without throwing (exhaustive)', (
    tester,
  ) async {
    for (final status in allStatuses) {
      await _pump(tester, RemoteKeychainRecoveryState(status: status));
      expect(find.byType(RemoteKeychainRecoveryScreen), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'status: $status');
    }
  });

  testWidgets('nothingToRestore shows its dedicated copy', (tester) async {
    await _pump(
      tester,
      const RemoteKeychainRecoveryState(
        status: RemoteKeychainRecoveryStatus.nothingToRestore,
      ),
    );
    expect(
      find.text('Your backup contains no Get Paid wallets to restore.'),
      findsOneWidget,
    );
  });

  testWidgets('noManifestFound shows its dedicated copy', (tester) async {
    await _pump(
      tester,
      const RemoteKeychainRecoveryState(
        status: RemoteKeychainRecoveryStatus.noManifestFound,
      ),
    );
    expect(
      find.text('No Get Paid backup was found on the relays.'),
      findsOneWidget,
    );
  });

  testWidgets('unsupportedNewerManifest shows update-the-app copy, NOT '
      '"no backup found" (KC-2)', (tester) async {
    await _pump(
      tester,
      const RemoteKeychainRecoveryState(
        status: RemoteKeychainRecoveryStatus.unsupportedNewerManifest,
      ),
    );
    expect(
      find.text(
        'This backup was created by a newer version of the app. Update the '
        'app to recover it.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('No Get Paid backup was found on the relays.'),
      findsNothing,
    );
  });

  testWidgets('olderManifestAvailable shows the warning and both actions', (
    tester,
  ) async {
    await _pump(
      tester,
      const RemoteKeychainRecoveryState(
        status: RemoteKeychainRecoveryStatus.olderManifestAvailable,
        newestEventCreatedAt: 30,
        selectedEventCreatedAt: 20,
      ),
    );
    expect(find.text('Restore an older backup?'), findsOneWidget);
    expect(find.text('Restore older backup'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
  });

  testWidgets('restored shows the count', (tester) async {
    await _pump(
      tester,
      const RemoteKeychainRecoveryState(
        status: RemoteKeychainRecoveryStatus.restored,
        restoredCount: 2,
      ),
    );
    expect(find.text('Restored 2 Get Paid wallets.'), findsOneWidget);
  });

  testWidgets('metadata result retains the keychain recovery summary', (
    tester,
  ) async {
    await _pump(
      tester,
      const RemoteKeychainRecoveryState(
        status: RemoteKeychainRecoveryStatus.metadataRestored,
        restoredCount: 2,
        metadataRestoredCount: 3,
        metadataAlreadyPresentCount: 1,
      ),
    );

    expect(find.text('Restored 2 Get Paid wallets.'), findsOneWidget);
    expect(
      find.text('Restored 3 records; 1 were already present.'),
      findsOneWidget,
    );
  });

  testWidgets('restored + live shows NO reactivation UI (DG-3 negative)', (
    tester,
  ) async {
    await _pump(
      tester,
      const RemoteKeychainRecoveryState(
        status: RemoteKeychainRecoveryStatus.restored,
        restoredCount: 1,
        healOutcome: LightningAddressHealOutcome(
          liveness: LightningAddressRegistrationLiveness.live,
        ),
      ),
    );
    expect(find.text('Re-activate'), findsNothing);
    expect(
      find.text('Your Lightning Address needs to be re-activated.'),
      findsNothing,
    );
  });

  testWidgets('restored + needsReactivation shows the re-activate affordance', (
    tester,
  ) async {
    await _pump(
      tester,
      const RemoteKeychainRecoveryState(
        status: RemoteKeychainRecoveryStatus.restored,
        restoredCount: 1,
        healOutcome: LightningAddressHealOutcome(
          liveness: LightningAddressRegistrationLiveness.needsReactivation,
        ),
      ),
    );
    expect(
      find.text('Your Lightning Address needs to be re-activated.'),
      findsOneWidget,
    );
    expect(find.text('Re-activate'), findsOneWidget);
  });

  testWidgets('restored + unreachable shows the loud verify warning', (
    tester,
  ) async {
    await _pump(
      tester,
      const RemoteKeychainRecoveryState(
        status: RemoteKeychainRecoveryStatus.restored,
        restoredCount: 1,
        healOutcome: LightningAddressHealOutcome(
          liveness: LightningAddressRegistrationLiveness.unreachable,
        ),
      ),
    );
    expect(find.textContaining('could not be verified'), findsOneWidget);
    expect(find.text('Re-activate'), findsNothing);
  });
}
