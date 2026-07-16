import 'package:bb_mobile/core/nostr/nostr_relay_transport.dart';
import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_client_port.dart';
import 'package:bb_mobile/features/keychain_manifest/data/websocket_keychain_manifest_nostr_relay_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_nostr_relay_repository.dart';
import 'package:get_it/get_it.dart';

import 'fake_bullnym_client.dart';
import 'fake_clock.dart';
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
      transport: NostrRelayTransport(connect: relay.connect),
    ),
  );

  await locator.unregister<BullnymClientPort>();
  locator.registerLazySingleton<BullnymClientPort>(() => bullnym);
}

/// Freezes the injectable [Clock] over the real [SystemClock] so every
/// wall-clock-stamped path (the manifest `generatedAt`, entry timestamps, the
/// Nostr event `created_at`) is deterministic across a wipe/recover. Register
/// it in the SAME window as [overrideBoundariesForTest] — right after
/// `Bull.init()` and BEFORE any facade is resolved — because the usecases that
/// read the clock are `registerFactory` and capture it at construction. Returns
/// the [FakeClock] so a spec can skew it if it needs to drive clock-skew paths.
Future<FakeClock> overrideClockForTest(
  GetIt locator, {
  FakeClock? clock,
}) async {
  final fakeClock = clock ?? FakeClock.baseline();
  await locator.unregister<Clock>();
  locator.registerLazySingleton<Clock>(() => fakeClock);
  return fakeClock;
}
