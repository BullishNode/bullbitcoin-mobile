import 'package:bb_mobile/features/nostr_identity/domain/derive_nostr_identity_handle_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:get_it/get_it.dart';

class NostrIdentityLocator {
  static void setup(GetIt locator) {
    locator.registerFactory<DeriveNostrIdentityHandleUsecase>(
      () => const DeriveNostrIdentityHandleUsecase(),
    );
    locator.registerFactory<NostrIdentityFacade>(
      () => NostrIdentityFacade(locator<DeriveNostrIdentityHandleUsecase>()),
    );
  }
}
