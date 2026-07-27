import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/presentation/nostr_keys_cubit.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/nostr_key_fixtures.dart';

void main() {
  test('splits stored keys into user and system groups', () async {
    final cubit = NostrKeysCubit(
      FakeKeychainManifestFacade(keys: [userKeyRecord(), systemKeyRecord()]),
    );
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.userKeys, hasLength(1));
    expect(cubit.state.systemKeys, hasLength(1));
    expect(
      cubit.state.userKeys.single.entry.bip85DerivationPath,
      "128002'/1'/1'",
    );
    expect(
      cubit.state.systemKeys.single.entry.bip85DerivationPath,
      "128002'/100'/1'",
    );
  });

  test('system keys stay hidden until explicitly shown', () async {
    final cubit = NostrKeysCubit(FakeKeychainManifestFacade());
    addTearDown(cubit.close);

    expect(cubit.state.showSystemKeys, isFalse);

    cubit.setShowSystemKeys(true);
    expect(cubit.state.showSystemKeys, isTrue);

    cubit.setShowSystemKeys(false);
    expect(cubit.state.showSystemKeys, isFalse);
  });

  test('rejects an empty name before touching the facade', () async {
    final facade = FakeKeychainManifestFacade();
    final cubit = NostrKeysCubit(facade);
    addTearDown(cubit.close);

    expect(await cubit.create('   '), isFalse);
    expect(cubit.state.formError, NostrKeyFormError.nameRequired);
    expect(facade.createCalls, isEmpty);
  });

  test('rejects a name longer than the entity allows', () async {
    final facade = FakeKeychainManifestFacade();
    final cubit = NostrKeysCubit(facade);
    addTearDown(cubit.close);

    final tooLong =
        'n' * (KeychainManifestNostrKeyMaterialization.maxPurposeLength + 1);
    expect(await cubit.create(tooLong), isFalse);
    expect(cubit.state.formError, NostrKeyFormError.nameTooLong);
    expect(facade.createCalls, isEmpty);
  });

  test('rejects a description longer than the entity allows', () async {
    final facade = FakeKeychainManifestFacade();
    final cubit = NostrKeysCubit(facade);
    addTearDown(cubit.close);

    final tooLong =
        'd' *
        (KeychainManifestNostrKeyMaterialization.maxDescriptionLength + 1);
    expect(await cubit.create('valid name', description: tooLong), isFalse);
    expect(cubit.state.formError, NostrKeyFormError.descriptionTooLong);
    expect(facade.createCalls, isEmpty);
  });

  test(
    'submits a valid name and description and clears the form error',
    () async {
      final facade = FakeKeychainManifestFacade();
      final cubit = NostrKeysCubit(facade);
      addTearDown(cubit.close);

      expect(await cubit.create(''), isFalse);
      expect(cubit.state.formError, isNotNull);

      expect(
        await cubit.create('personal identity', description: 'long-form notes'),
        isTrue,
      );

      expect(cubit.state.formError, isNull);
      expect(facade.createCalls, [('personal identity', 'long-form notes')]);
    },
  );

  test(
    'an edit passes the name and description through to the facade',
    () async {
      final record = userKeyRecord();
      final facade = FakeKeychainManifestFacade(keys: [record]);
      final cubit = NostrKeysCubit(facade);
      addTearDown(cubit.close);

      expect(
        await cubit.updateKey(
          key: record,
          name: 'renamed',
          description: 'new note',
        ),
        isTrue,
      );

      expect(facade.updateCalls, [(record.entryId, 'renamed', 'new note')]);
    },
  );

  test('a rejected edit never reaches the facade', () async {
    final record = userKeyRecord();
    final facade = FakeKeychainManifestFacade(keys: [record]);
    final cubit = NostrKeysCubit(facade);
    addTearDown(cubit.close);

    expect(await cubit.updateKey(key: record, name: '  '), isFalse);

    expect(cubit.state.formError, NostrKeyFormError.nameRequired);
    expect(facade.updateCalls, isEmpty);
  });

  test('a facade failure advances the failure revision', () async {
    final facade = FakeKeychainManifestFacade(failing: true);
    final cubit = NostrKeysCubit(facade);
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.failureRevision, 1);
    expect(cubit.state.loading, isFalse);
  });
}
