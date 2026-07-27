import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/features/keychain_manifest/presentation/nostr_keys_cubit.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
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

  testWidgets('offers a name and description field and no path input', (
    tester,
  ) async {
    await _pumpCreate(tester, FakeKeychainManifestFacade());

    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.textContaining('Derivation path'), findsNothing);
    expect(find.textContaining("128002'"), findsNothing);
  });

  testWidgets('rejects an empty name without calling the facade', (
    tester,
  ) async {
    final facade = FakeKeychainManifestFacade();
    await _pumpCreate(tester, facade);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a name for this key.'), findsOneWidget);
    expect(facade.createCalls, isEmpty);
  });

  testWidgets('caps the name and description at the entity bounds', (
    tester,
  ) async {
    await _pumpCreate(tester, FakeKeychainManifestFacade());

    final name = tester.widget<TextField>(
      find.byKey(const Key('nostr_key_name_field')),
    );
    final description = tester.widget<TextField>(
      find.byKey(const Key('nostr_key_description_field')),
    );

    expect(
      name.maxLength,
      KeychainManifestNostrKeyMaterialization.maxPurposeLength,
    );
    expect(
      description.maxLength,
      KeychainManifestNostrKeyMaterialization.maxDescriptionLength,
    );
  });

  testWidgets('an over-long name typed past the cap is truncated, not sent', (
    tester,
  ) async {
    final facade = FakeKeychainManifestFacade();
    await _pumpCreate(tester, facade);

    await tester.enterText(
      find.byKey(const Key('nostr_key_name_field')),
      'n' * (KeychainManifestNostrKeyMaterialization.maxPurposeLength + 40),
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(facade.createCalls, hasLength(1));
    expect(
      facade.createCalls.single.$1.length,
      KeychainManifestNostrKeyMaterialization.maxPurposeLength,
    );
  });

  testWidgets('submits the name and description', (tester) async {
    final facade = FakeKeychainManifestFacade();
    await _pumpCreate(tester, facade);

    await tester.enterText(
      find.byKey(const Key('nostr_key_name_field')),
      'personal identity',
    );
    await tester.enterText(
      find.byKey(const Key('nostr_key_description_field')),
      'long-form notes',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(facade.createCalls, [('personal identity', 'long-form notes')]);
  });

  testWidgets('the full create flow returns to a list showing the new key', (
    tester,
  ) async {
    final facade = FakeKeychainManifestFacade();
    await _pumpList(tester, facade);

    await tester.tap(find.text('Create nostr key'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('nostr_key_name_field')),
      'personal identity',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(facade.createCalls, [('personal identity', '')]);
    expect(find.text('Nostr keys'), findsOneWidget);
    expect(find.text('personal identity'), findsOneWidget);
    expect(find.text('Nostr key created'), findsOneWidget);

    // The confirmation is an overlay with its own auto-dismiss timer; let it
    // expire so the test does not tear down with a pending timer.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('clears the validation error once the field is edited', (
    tester,
  ) async {
    await _pumpCreate(tester, FakeKeychainManifestFacade());

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name for this key.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('nostr_key_name_field')), 'p');
    await tester.pumpAndSettle();

    expect(find.text('Enter a name for this key.'), findsNothing);
  });

  testWidgets('an edit submits the changed name and description', (
    tester,
  ) async {
    final record = userKeyRecord(description: 'old note');
    final facade = FakeKeychainManifestFacade(keys: [record]);
    await _pumpEdit(tester, facade, record);

    await tester.enterText(
      find.byKey(const Key('nostr_key_name_field')),
      'renamed',
    );
    await tester.enterText(
      find.byKey(const Key('nostr_key_description_field')),
      'new note',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(facade.updateCalls, [(record.entryId, 'renamed', 'new note')]);
  });
}

Future<void> _pumpCreate(
  WidgetTester tester,
  FakeKeychainManifestFacade facade,
) => _pump(tester, facade, KeychainManifestRoutes.nostrKeyCreateName, null);

/// Stops at the list so a test can drive the real push-and-return flow.
Future<void> _pumpList(
  WidgetTester tester,
  FakeKeychainManifestFacade facade,
) => _pump(tester, facade, null, null);

Future<void> _pumpEdit(
  WidgetTester tester,
  FakeKeychainManifestFacade facade,
  KeychainManifestNostrKeyRecord record,
) => _pump(tester, facade, KeychainManifestRoutes.nostrKeyEditName, record);

Future<void> _pump(
  WidgetTester tester,
  FakeKeychainManifestFacade facade,
  String? routeName,
  KeychainManifestNostrKeyRecord? record,
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
  if (routeName == null) return;
  router.pushNamed(routeName, extra: record);
  await tester.pumpAndSettle();
}
