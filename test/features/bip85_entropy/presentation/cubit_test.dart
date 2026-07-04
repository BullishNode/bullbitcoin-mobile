import 'package:bb_mobile/core/bip85/domain/activate_bip85_derivation_usecase.dart';
import 'package:bb_mobile/core/bip85/domain/alias_bip85_derivation_usecase.dart';
import 'package:bb_mobile/core/bip85/domain/bip85_derivation_entity.dart';
import 'package:bb_mobile/core/bip85/domain/derive_next_bip85_hex_from_default_wallet_usecase.dart';
import 'package:bb_mobile/core/bip85/domain/derive_next_bip85_mnemonic_from_default_wallet_usecase.dart';
import 'package:bb_mobile/core/bip85/domain/fetch_all_bip85_derivations_with_entropy_usecase.dart';
import 'package:bb_mobile/core/bip85/domain/revoke_bip85_derivation_usecase.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bip85_entropy/presentation/cubit.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFetchAll extends Mock
    implements FetchAllBip85DerivationsWithEntropyUsecase {}

class _MockDeriveNextMnemonic extends Mock
    implements DeriveNextBip85MnemonicFromDefaultWalletUsecase {}

class _MockDeriveNextHex extends Mock
    implements DeriveNextBip85HexFromDefaultWalletUsecase {}

class _MockAlias extends Mock implements AliasBip85DerivationUsecase {}

class _MockRevoke extends Mock implements RevokeBip85DerivationUsecase {}

class _MockActivate extends Mock implements ActivateBip85DerivationUsecase {}

Bip85DerivationEntity _derivation(String path, int index) =>
    Bip85DerivationEntity(
      path: path,
      xprvFingerprint: '3f635a63',
      alias: null,
      status: Bip85Status.active,
      application: Bip85Application.bip39,
      index: index,
    );

void main() {
  late _MockFetchAll fetchAll;
  late Bip85EntropyCubit cubit;

  setUpAll(() {
    registerFallbackValue(<String>{});
  });

  setUp(() {
    fetchAll = _MockFetchAll();
  });

  tearDown(() => cubit.close());

  test(
    'filters reserved wallet-seed derivations out of the exposed list',
    () async {
      // A stored reserved BTCPay product seed (index 100) and an ordinary dev
      // derivation (index 5) both exist in the store. The cubit must forward
      // the registry's reserved paths as the usecase's exclusion set so a
      // reserved product seed's entropy is never re-derived or exposed (KI-2).
      // The mock honours that exclusion set, mirroring the real usecase.
      when(
        () => fetchAll.execute(excludedPaths: any(named: 'excludedPaths')),
      ).thenAnswer((invocation) async {
        final excluded =
            invocation.namedArguments[#excludedPaths] as Set<String>;
        final all = [
          (derivation: _derivation("39'/0'/12'/100'", 100), entropy: 'e100'),
          (derivation: _derivation("39'/0'/12'/5'", 5), entropy: 'e5'),
        ];
        return Ok(
          all.where((e) => !excluded.contains(e.derivation.path)).toList(),
        );
      });

      cubit = Bip85EntropyCubit(
        fetchAllBip85DerivationsWithEntropyUsecase: fetchAll,
        deriveNextBip85MnemonicFromDefaultWalletUsecase:
            _MockDeriveNextMnemonic(),
        deriveNextBip85HexFromDefaultWalletUsecase: _MockDeriveNextHex(),
        aliasBip85DerivationUsecase: _MockAlias(),
        revokeBip85DerivationUsecase: _MockRevoke(),
        activateBip85DerivationUsecase: _MockActivate(),
        registry: const Bip85RegistryFacade(),
      );

      await cubit.fetchAllDerivations();
      await pumpEventQueue();

      final exposedPaths = cubit.state.derivations
          .map((e) => e.derivation.path)
          .toList();
      expect(exposedPaths, ["39'/0'/12'/5'"]);
      expect(exposedPaths, isNot(contains("39'/0'/12'/100'")));
    },
  );
}
