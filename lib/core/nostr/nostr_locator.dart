import 'package:bb_mobile/core/nostr/nostr_facade.dart';
import 'package:bb_mobile/core/nostr/nostr_relay_client.dart';
import 'package:get_it/get_it.dart';

class NostrLocator {
  static void registerFacades(GetIt locator) {
    locator.registerLazySingleton<NostrRelayClient>(
      () => const NostrRelayClient(),
    );
    locator.registerLazySingleton<NostrFacade>(() => const NostrFacade());
  }
}
