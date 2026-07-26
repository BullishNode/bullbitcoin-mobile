import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/widgets/qr_display_widget.dart';
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

  testWidgets('a user key shows its npub, never the hex public key', (
    tester,
  ) async {
    final record = userKeyRecord(description: 'long-form notes');
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    final npub = NostrPublicKeyEncoding.npubFromPublicKeyHex(userPublicKeyHex);
    expect(find.text('npub'), findsOneWidget);
    expect(find.textContaining(npub.substring(0, 8)), findsOneWidget);
    expect(find.textContaining(userPublicKeyHex), findsNothing);
    expect(find.textContaining('ababab'), findsNothing);
    expect(find.text('personal identity'), findsOneWidget);
    expect(find.text('long-form notes'), findsOneWidget);
    expect(find.text("128002'/1'/1'"), findsOneWidget);
  });

  testWidgets('a user key with no description omits the row', (tester) async {
    final record = userKeyRecord();
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    expect(find.text('Description'), findsNothing);
  });

  testWidgets('a user npub opens the shared address viewer with a QR', (
    tester,
  ) async {
    final record = userKeyRecord();
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    final npub = NostrPublicKeyEncoding.npubFromPublicKeyHex(userPublicKeyHex);
    await tester.tap(find.textContaining(npub.substring(0, 8)));
    await tester.pumpAndSettle();

    // The Bitcoin-address viewer, reused: grouped text plus a QR and copy.
    expect(find.byType(QrDisplayWidget), findsOneWidget);
    expect(find.text('Tap to copy'), findsOneWidget);
    // An npub has no blockchain explorer, so those actions stay off.
    expect(find.textContaining('View in explorer'), findsNothing);
  });

  testWidgets('a user key offers edit and nsec reveal', (tester) async {
    final record = userKeyRecord();
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Show nsec'), findsOneWidget);
  });

  testWidgets('a system key hides its npub behind the exact warning', (
    tester,
  ) async {
    final record = systemKeyRecord();
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    final npub = NostrPublicKeyEncoding.npubFromPublicKeyHex(
      systemPublicKeyHex,
    );
    expect(find.text('Show npub'), findsOneWidget);
    expect(find.textContaining(npub.substring(0, 8)), findsNothing);

    await tester.tap(find.text('Show npub'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Do not use this npub for anything else. Viewing this npub is '
        'strictly for troubleshooting bugs. Do not share it with anyone.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();

    expect(find.textContaining(npub.substring(0, 8)), findsOneWidget);
    expect(find.textContaining(systemPublicKeyHex), findsNothing);
    expect(find.textContaining('cdcdcd'), findsNothing);
  });

  testWidgets('a system key offers no edit affordance', (tester) async {
    final record = systemKeyRecord();
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    expect(find.text('Edit'), findsNothing);
    // The reveal action is still available for recovery/troubleshooting.
    expect(find.text('Show nsec'), findsOneWidget);
  });

  testWidgets('a system key is named from its role, and never deletable', (
    tester,
  ) async {
    final record = systemKeyRecord(purpose: 'whatever was stored');
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    expect(find.text('Metadata backup'), findsOneWidget);
    expect(find.text('whatever was stored'), findsNothing);
    expect(find.textContaining('Delete'), findsNothing);
    expect(find.textContaining('Revoke'), findsNothing);
  });

  testWidgets('a system nsec reveal is gated by the exact warning', (
    tester,
  ) async {
    final record = systemKeyRecord();
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    await tester.tap(find.text('Show nsec'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Do not use this nsec for any other purpose. Do not share this nsec '
        'with anyone. Showing this nsec is only for emergency recovery or '
        'troubleshooting.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a user nsec reveal uses the standard sensitive warning', (
    tester,
  ) async {
    final record = userKeyRecord();
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    await tester.tap(find.text('Show nsec'));
    await tester.pumpAndSettle();

    expect(find.textContaining('DO NOT SHARE WITH ANYONE'), findsOneWidget);
  });

  testWidgets('the edit affordance opens the form prefilled', (tester) async {
    final record = userKeyRecord(description: 'long-form notes');
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Nostr key'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('nostr_key_name_field'))),
      isA<TextField>().having(
        (field) => field.controller?.text,
        'name',
        'personal identity',
      ),
    );
    expect(
      tester.widget<TextField>(
        find.byKey(const Key('nostr_key_description_field')),
      ),
      isA<TextField>().having(
        (field) => field.controller?.text,
        'description',
        'long-form notes',
      ),
    );
  });
}

Future<void> _pump(
  WidgetTester tester,
  FakeKeychainManifestFacade facade,
  KeychainManifestNostrKeyRecord record,
) async {
  locator.registerFactory<NostrKeysCubit>(() => NostrKeysCubit(facade));
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
  router.pushNamed(
    KeychainManifestRoutes.nostrKeyDetailName,
    extra: record,
  );
  await tester.pumpAndSettle();
}
