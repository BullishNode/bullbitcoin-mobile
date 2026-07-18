import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_client_port.dart';
import 'package:get_it/get_it.dart';

import 'fake_bullnym_client.dart';
import 'fake_clock.dart';

/// Overrides ONLY the network-boundary type (HARNESS §2.6): the Bullnym
/// port. Everything below the seam — SQLite, secure storage, bull_sdk
/// natives, the codec, the signers — stays real; that is the value of the L1
/// layer.
///
/// Both the keychain-manifest and wallet-metadata-backup remote repositories
/// now go through [BullnymClientPort] (`fetchBackup`/`storeBackup`/
/// `deleteBackup`) rather than a direct Nostr relay connection, so overriding
/// this single port is sufficient to fake both backup surfaces; there is no
/// separate relay-transport seam left to override (superseded architecture —
/// see the overlay NOTES on `fake_nostr_relay.dart`).
///
/// Call immediately after `Bull.init()` and BEFORE any facade is resolved
/// (usecases are `registerFactory` and capture their deps at construction, so
/// re-registering the singleton first is sufficient).
Future<void> overrideBoundariesForTest(
  GetIt locator, {
  required FakeBullnymClient bullnym,
}) async {
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
