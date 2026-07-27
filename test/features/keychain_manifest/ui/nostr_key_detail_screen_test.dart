import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/widgets/address_viewer.dart';
import 'package:bb_mobile/core/widgets/qr_display_widget.dart';
import 'package:bb_mobile/features/keychain_manifest/presentation/nostr_keys_cubit.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_routes.dart';
import 'package:bb_mobile/features/keychain_manifest/ui/widgets/nostr_nsec_reveal_dialog.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:bb_mobile/locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'nostr_key_fixtures.dart';

/// The reveal dialog turns the platform screenshot block on and off; stub the
/// plugin channel so the widget under test runs unchanged.
const _noScreenshotChannel = MethodChannel(
  'com.flutterplaza.no_screenshot_methods',
);

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_noScreenshotChannel, (_) async => true);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_noScreenshotChannel, null);
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
    // A user key keeps showing what the user stored, not any generated copy.
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('long-form notes'), findsOneWidget);
    expect(find.text("128002'/1'/1'"), findsOneWidget);
  });

  testWidgets('a user key with no description omits the row', (tester) async {
    final record = userKeyRecord();
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    expect(find.text('Description'), findsNothing);
  });

  testWidgets('each system role explains itself in the description row', (
    tester,
  ) async {
    const expected = {
      "128002'/100'/1'": (
        'nostr_wallet_backup_key',
        'Identifies and signs your encrypted metadata backup so the app can '
            'find and restore it. Managed automatically — you never need to '
            'use this key yourself.',
      ),
      "128002'/101'/1'": (
        'nostr_bullnym_server_auth_key',
        'Authenticates this wallet to the Bull Bitcoin payment server for '
            'your Lightning address, invoices, Payment Page and Point of '
            'Sale. Managed automatically — you never need to use this key '
            'yourself.',
      ),
      "128002'/102'/1'": (
        'nostr_nip05_public_nym_verification_key',
        'Reserved for verifying your payment name publicly over Nostr. Not '
            'used by the app yet — it exists so a future version can enable '
            'verification without changing your keys.',
      ),
    };

    for (final entry in expected.entries) {
      final (reservationId, copy) = entry.value;
      final record = systemKeyRecord(
        path: entry.key,
        reservationId: reservationId,
      );
      await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

      expect(find.text('Description'), findsOneWidget);
      expect(find.text(copy), findsOneWidget, reason: 'for ${entry.key}');

      await locator.reset();
    }
  });

  testWidgets('localized system copy wins over a stored description', (
    tester,
  ) async {
    // Reserved rows are written with a null description by design; if one ever
    // carried stored text, the role copy must still be what the user reads.
    final record = systemKeyRecord(
      purpose: 'whatever was stored',
      description: 'stored description that must not surface',
    );
    await _pump(tester, FakeKeychainManifestFacade(keys: [record]), record);

    expect(find.text('Metadata backup'), findsOneWidget);
    expect(find.text('whatever was stored'), findsNothing);
    expect(find.text('stored description that must not surface'), findsNothing);
    expect(
      find.textContaining('Identifies and signs your encrypted metadata'),
      findsOneWidget,
    );
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

  testWidgets('confirming the warning actually reveals the nsec', (
    tester,
  ) async {
    final record = userKeyRecord();
    final facade = FakeKeychainManifestFacade(
      keys: [record],
      nsec: 'nsec1revealedsecret',
    );
    await _pump(tester, facade, record);

    await tester.tap(find.text('Show nsec'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();

    expect(facade.revealCalls, [record.entryId]);
    expect(find.text('nsec1revealedsecret'), findsOneWidget);
    // The nsec uses the SAME presentation as the npub — an AddressViewer whose
    // own full-value/QR view carries the copy control — so the dialog must not
    // add a second, duplicate copy button of its own. (Two viewers are in the
    // tree: the npub row behind the dialog, and the nsec inside it.)
    expect(
      find.descendant(
        of: find.byType(NostrNsecRevealDialog),
        matching: find.byType(AddressViewer),
      ),
      findsOneWidget,
    );
    expect(find.text('Copy nsec'), findsNothing);
  });

  testWidgets('a system key nsec reveal also reaches the dialog', (
    tester,
  ) async {
    final record = systemKeyRecord();
    final facade = FakeKeychainManifestFacade(
      keys: [record],
      nsec: 'nsec1systemsecret',
    );
    await _pump(tester, facade, record);

    await tester.tap(find.text('Show nsec'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();

    expect(find.text('nsec1systemsecret'), findsOneWidget);
  });

  testWidgets('dismissing the warning without confirming reveals nothing', (
    tester,
  ) async {
    final record = userKeyRecord();
    final facade = FakeKeychainManifestFacade(keys: [record]);
    await _pump(tester, facade, record);

    await tester.tap(find.text('Show nsec'));
    await tester.pumpAndSettle();
    // Tap the barrier to dismiss the sheet instead of confirming.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(facade.revealCalls, isEmpty);
    expect(find.textContaining('nsec1'), findsNothing);
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
  router.pushNamed(KeychainManifestRoutes.nostrKeyDetailName, extra: record);
  await tester.pumpAndSettle();
}
