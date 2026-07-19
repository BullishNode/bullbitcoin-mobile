import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/storage/data/datasources/key_value_storage/key_value_storage_datasource.dart';
import 'package:bb_mobile/core/utils/constants.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_address_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/invoices/application/usecases/create_invoice_usecase.dart';
import 'package:bb_mobile/features/invoices/invoices_locator.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

class _MockSeedRepository extends Mock implements SeedRepository {}

class _MockGetSettingsUsecase extends Mock implements GetSettingsUsecase {}

class _MockSecureStorage extends Mock
    implements KeyValueStorageDatasource<String> {}

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockWalletAddressRepository extends Mock
    implements WalletAddressRepository {}

class _MockBullnymFacade extends Mock implements BullnymFacade {}

class _MockLabelsFacade extends Mock implements LabelsFacade {}

class _MockNostrIdentityFacade extends Mock implements NostrIdentityFacade {}

void main() {
  late GetIt locator;

  setUp(() {
    locator = GetIt.asNewInstance();
    locator.registerSingleton<SeedRepository>(_MockSeedRepository());
    locator.registerSingleton<GetSettingsUsecase>(_MockGetSettingsUsecase());
    locator.registerSingleton<KeyValueStorageDatasource<String>>(
      _MockSecureStorage(),
      instanceName: LocatorInstanceNameConstants.secureStorageDatasource,
    );
    locator.registerSingleton<WalletRepository>(_MockWalletRepository());
    locator.registerSingleton<WalletAddressRepository>(
      _MockWalletAddressRepository(),
    );
    locator.registerSingleton<BullnymFacade>(_MockBullnymFacade());
    locator.registerSingleton<LabelsFacade>(_MockLabelsFacade());
    locator.registerSingleton<NostrIdentityFacade>(_MockNostrIdentityFacade());
  });

  tearDown(() => locator.reset());

  test('shares one create usecase for the single durable pending slot', () {
    InvoicesLocator.setup(locator);

    final first = locator<CreateInvoiceUsecase>();
    final second = locator<CreateInvoiceUsecase>();

    expect(second, same(first));
  });
}
