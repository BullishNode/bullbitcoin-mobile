import 'package:bb_mobile/features/bullnym/application/ports/bullnym_client_port.dart';
import 'package:bb_mobile/features/bullnym/application/usecases/delete_bullnym_registration_usecase.dart';
import 'package:bb_mobile/features/bullnym/application/usecases/lookup_bullnym_registration_usecase.dart';
import 'package:bb_mobile/features/bullnym/application/usecases/register_bullnym_usecase.dart';
import 'package:bb_mobile/features/bullnym/frameworks/bullnym_http_client.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:get_it/get_it.dart';

class BullnymLocator {
  static void setup(GetIt locator) {
    locator.registerLazySingleton<BullnymClientPort>(() => BullnymHttpClient());
    locator.registerFactory<RegisterBullnymUsecase>(
      () => RegisterBullnymUsecase(client: locator<BullnymClientPort>()),
    );
    locator.registerFactory<DeleteBullnymRegistrationUsecase>(
      () => DeleteBullnymRegistrationUsecase(
        client: locator<BullnymClientPort>(),
      ),
    );
    locator.registerFactory<LookupBullnymRegistrationUsecase>(
      () => LookupBullnymRegistrationUsecase(
        client: locator<BullnymClientPort>(),
      ),
    );
    locator.registerFactory<BullnymFacade>(
      () => BullnymFacade(
        register: locator<RegisterBullnymUsecase>(),
        deleteRegistration: locator<DeleteBullnymRegistrationUsecase>(),
        lookupRegistration: locator<LookupBullnymRegistrationUsecase>(),
      ),
    );
  }
}
