import 'package:bb_mobile/features/bullnym/domain/bullnym_client_port.dart';
import 'package:bb_mobile/features/keychain_manifest/data/datasources/keychain_manifest_nostr_relay_datasource.dart';
import 'package:bb_mobile/features/keychain_manifest/data/websocket_keychain_manifest_nostr_relay_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_nostr_relay_repository.dart';
import 'package:get_it/get_it.dart';

import 'fake_bullnym_client.dart';
import 'fake_nostr_relay.dart';

/// Overrides ONLY the network-boundary types (HARNESS §2.6): the relay
/// transport and the bullnym port. Everything below the seam — SQLite, secure
/// storage, bull_sdk natives, the codec, the signers — stays real; that is the
/// value of the L1 layer.
///
/// Call immediately after `Bull.init()` and BEFORE any facade is resolved
/// (usecases are `registerFactory` and capture their deps at construction, so
/// re-registering the singleton first is sufficient). The relay repository is
/// unregistered + re-registered because `AppLocator.setup` enables registering
/// multiple instances of one type, making blind re-registration ambiguous.
Future<void> overrideBoundariesForTest(
  GetIt locator, {
  required FakeNostrRelay relay,
  required FakeBullnymClient bullnym,
}) async {
  await locator.unregister<KeychainManifestNostrRelayRepository>();
  locator.registerLazySingleton<KeychainManifestNostrRelayRepository>(
    () => WebSocketKeychainManifestNostrRelayRepository(
      datasource: KeychainManifestNostrRelayDatasource(connect: relay.connect),
    ),
  );

  await locator.unregister<BullnymClientPort>();
  locator.registerLazySingleton<BullnymClientPort>(() => bullnym);
}
