import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/themes/colors.dart';
import 'package:bb_mobile/core/widgets/buttons/button.dart';
import 'package:bb_mobile/core/widgets/settings_entry_item.dart';
import 'package:bb_mobile/features/keychain_manifest/presentation/nostr_keys_cubit.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_routes.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'nostr_key_fixtures.dart';

void main() {
  tearDown(() async {
    await locator.reset();
  });

  testWidgets('lists user key names only, with no npub, hex, or path', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeKeychainManifestFacade(
        keys: [
          userKeyRecord(purpose: 'personal identity'),
          userKeyRecord(purpose: 'work identity', identity: 2),
          systemKeyRecord(),
        ],
      ),
    );

    expect(find.text('personal identity'), findsOneWidget);
    expect(find.text('work identity'), findsOneWidget);
    // System keys are collapsed by default.
    expect(find.text('Metadata backup'), findsNothing);
    // Rows carry the name and nothing else.
    expect(find.textContaining('npub1'), findsNothing);
    expect(find.textContaining("128002'"), findsNothing);
    expect(find.textContaining('ababab'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
  });

  testWidgets('shows the empty state when no user key exists', (tester) async {
    await _pump(tester, FakeKeychainManifestFacade(keys: [systemKeyRecord()]));

    expect(find.text('No Nostr keys have been created yet.'), findsOneWidget);
  });

  testWidgets('hides the system-keys affordance when there are none', (
    tester,
  ) async {
    await _pump(tester, FakeKeychainManifestFacade(keys: [userKeyRecord()]));

    expect(find.text('Show system keys'), findsNothing);
  });

  testWidgets(
    'reveals subdued system rows only after the warning is accepted',
    (tester) async {
      await _pump(
        tester,
        FakeKeychainManifestFacade(keys: [userKeyRecord(), systemKeyRecord()]),
      );

      await tester.tap(find.text('Show system keys'));
      await tester.pumpAndSettle();

      // The warning gates the reveal: nothing is shown until it is accepted.
      expect(
        find.text(
          'These keys are managed by the app for troubleshooting and recovery. '
          'They are not your identities. Do not use or share them.',
        ),
        findsOneWidget,
      );
      expect(find.text('Metadata backup'), findsNothing);

      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();

      expect(find.text('System keys'), findsOneWidget);
      expect(find.text('Metadata backup'), findsOneWidget);
      // Revealed rows are muted, not styled like the user's own keys.
      final row = tester.widget<SettingsEntryItem>(
        find.widgetWithText(SettingsEntryItem, 'Metadata backup'),
      );
      expect(row.textColor, isNotNull);
      expect(find.text('Hide system keys'), findsOneWidget);
    },
  );

  testWidgets('hiding system keys again needs no warning', (tester) async {
    await _pump(
      tester,
      FakeKeychainManifestFacade(keys: [userKeyRecord(), systemKeyRecord()]),
    );

    await tester.tap(find.text('Show system keys'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();
    expect(find.text('Metadata backup'), findsOneWidget);

    await tester.tap(find.text('Hide system keys'));
    await tester.pumpAndSettle();

    expect(find.text('Metadata backup'), findsNothing);
    expect(find.text('Show system keys'), findsOneWidget);
  });

  testWidgets('names system keys from their role, not their stored purpose', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeKeychainManifestFacade(
        keys: [
          systemKeyRecord(
            path: "128002'/100'/1'",
            reservationId: 'nostr_wallet_backup_key',
            purpose: 'whatever was stored',
          ),
          systemKeyRecord(
            path: "128002'/101'/1'",
            reservationId: 'nostr_bullnym_server_auth_key',
            purpose: 'whatever was stored',
          ),
          systemKeyRecord(
            path: "128002'/102'/1'",
            reservationId: 'nostr_nip05_public_nym_verification_key',
            purpose: 'whatever was stored',
          ),
        ],
      ),
    );

    await tester.tap(find.text('Show system keys'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();

    expect(find.text('Metadata backup'), findsOneWidget);
    expect(find.text('Bullnym Auth key'), findsOneWidget);
    expect(find.text('Nostr NIP-05 Public Nym Verification'), findsOneWidget);
    expect(find.text('whatever was stored'), findsNothing);
  });

  testWidgets('the create action is a footer button, not an app bar icon', (
    tester,
  ) async {
    await _pump(tester, FakeKeychainManifestFacade(keys: [userKeyRecord()]));

    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.widgetWithText(BBButton, 'Create nostr key'), findsOneWidget);
  });

  testWidgets('the create button opens the create form', (tester) async {
    await _pump(tester, FakeKeychainManifestFacade(keys: [userKeyRecord()]));

    await tester.tap(find.text('Create nostr key'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nostr_key_name_field')), findsOneWidget);
  });

  testWidgets('the system keys affordance uses the advanced-settings style', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeKeychainManifestFacade(keys: [userKeyRecord(), systemKeyRecord()]),
    );

    final button = find.byKey(const Key('nostr_keys_system_keys_button'));
    expect(button, findsOneWidget);
    expect(
      tester.widget<TextButton>(button).child,
      isA<Text>()
          .having((text) => text.data, 'label', 'Show system keys')
          .having((text) => text.style?.color, 'color', AppColors.light.error),
    );
  });

  testWidgets('tapping a user row opens its detail page', (tester) async {
    await _pump(tester, FakeKeychainManifestFacade(keys: [userKeyRecord()]));

    await tester.tap(find.text('personal identity'));
    await tester.pumpAndSettle();

    expect(find.text('Nostr key'), findsOneWidget);
    expect(find.text('Derivation path'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  FakeKeychainManifestFacade facade,
) async {
  locator.registerFactory<NostrKeysCubit>(() => nostrKeysCubitForTest(facade));
  final router = GoRouter(
    initialLocation: '/settings/nostr-keys',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (_, _) => const Scaffold(body: Text('settings-root')),
        routes: [KeychainManifestRoutes.nostrKeys],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      theme: AppTheme.themeData(AppThemeType.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
}
