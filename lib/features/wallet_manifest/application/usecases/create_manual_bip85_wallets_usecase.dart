import 'package:bb_mobile/core/bip85/domain/bip85_manual_index_reservations.dart';
import 'package:bb_mobile/core/bip85/domain/bip85_derivation_entity.dart';
import 'package:bb_mobile/core/bip85/domain/fetch_all_derivations_usecase.dart';
import 'package:bb_mobile/core/settings/domain/repositories/settings_repository.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/wallet/domain/wallet_label_reservations.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/derive_wallet_manifest_root_key_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/fetch_wallet_manifest_origins_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/publish_local_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/restore_wallet_manifest_snapshot_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/bip85_derivation_path.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_account.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_origin.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_snapshot.dart';
import 'package:bb_mobile/features/wallet_manifest/public/create_manual_bip85_wallets.dart';
import 'package:bb_mobile/features/wallet_manifest/wallet_manifest_errors.dart';
import 'package:synchronized/synchronized.dart';

class CreateManualBip85WalletsUsecase {
  static final _lock = Lock();
  static final _relativeMnemonic12PathPattern = RegExp(
    r"^39'/0'/12'/([0-9]+)'$",
  );

  final DeriveWalletManifestRootKeyUsecase _deriveRootKey;
  final FetchWalletManifestOriginsUsecase _fetchOrigins;
  final RestoreWalletManifestSnapshotUsecase _restoreSnapshot;
  final PublishLocalWalletManifestUsecase _publishLocalManifest;
  final SettingsRepository _settingsRepository;
  final FetchAllBip85DerivationsUsecase _fetchAllBip85Derivations;
  final WalletLabelReservationPolicy _walletLabelReservationPolicy;

  CreateManualBip85WalletsUsecase({
    required DeriveWalletManifestRootKeyUsecase deriveRootKey,
    required FetchWalletManifestOriginsUsecase fetchOrigins,
    required RestoreWalletManifestSnapshotUsecase restoreSnapshot,
    required PublishLocalWalletManifestUsecase publishLocalManifest,
    required SettingsRepository settingsRepository,
    required FetchAllBip85DerivationsUsecase fetchAllBip85Derivations,
    required WalletLabelReservationPolicy walletLabelReservationPolicy,
  }) : _deriveRootKey = deriveRootKey,
       _fetchOrigins = fetchOrigins,
       _restoreSnapshot = restoreSnapshot,
       _publishLocalManifest = publishLocalManifest,
       _settingsRepository = settingsRepository,
       _fetchAllBip85Derivations = fetchAllBip85Derivations,
       _walletLabelReservationPolicy = walletLabelReservationPolicy;

  Future<CreateManualBip85WalletsResult> execute(
    CreateManualBip85WalletsCommand command,
  ) {
    return _lock.synchronized(() => _execute(command));
  }

  Future<CreateManualBip85WalletsResult> _execute(
    CreateManualBip85WalletsCommand command,
  ) async {
    final networks = await _networksFor(command.networkSelection);
    final labels = _labelsFor(command, networks);
    if (command.index != null) {
      _validateStaticIndex(command.index!);
    }
    final rootKey = await _deriveRootKey.execute();
    final origins = await _fetchOrigins.execute();
    final usedWallets = _usedWalletsForRoot(
      rootFingerprint: rootKey.rootFingerprint,
      origins: origins,
    );
    final usedUnmanifestedDerivationIndexes =
        await _usedUnmanifestedMnemonic12IndexesForRoot(
          rootFingerprint: rootKey.rootFingerprint,
          origins: origins,
        );
    final index =
        command.index ??
        _nextFreeIndex(
          networks,
          usedWallets,
          usedUnmanifestedDerivationIndexes,
        );

    _validateIndex(
      index,
      networks,
      usedWallets,
      usedUnmanifestedDerivationIndexes,
    );

    final path = Bip85DerivationPath.mnemonic12(index: index);
    final accounts = [
      for (final network in networks)
        WalletManifestAccount(
          rootFingerprint: rootKey.rootFingerprint,
          bip85DerivationPath: path,
          network: network,
          name: labels[network],
          timestamp: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        ),
    ];

    final result = await _restoreSnapshot.execute(
      snapshot: WalletManifestSnapshot(
        createdAt: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        accounts: accounts,
      ),
    );

    final restoredWallets = result.restored
        .where((outcome) => outcome.walletId != null)
        .map(
          (outcome) => CreateManualBip85WalletResult(
            network: outcome.account.network,
            walletId: outcome.walletId!,
            label: outcome.actualLabel ?? outcome.account.name!,
          ),
        )
        .toList(growable: false);
    final partialFailure =
        result.failed.isNotEmpty ||
        result.skipped.isNotEmpty ||
        result.alreadyPresent.isNotEmpty;

    if (result.failed.isNotEmpty && restoredWallets.isEmpty) {
      throw WalletManifestManualBip85WalletCreationException(
        'Failed to create one or more BIP85 wallets',
      );
    }
    if (result.skipped.isNotEmpty && restoredWallets.isEmpty) {
      throw WalletManifestManualBip85WalletCreationException(
        'BIP85 wallet restore skipped because the manifest root did not match',
      );
    }
    if (result.alreadyPresent.isNotEmpty && restoredWallets.isEmpty) {
      throw WalletManifestManualBip85IndexUnavailableException(index);
    }
    if (restoredWallets.isEmpty || restoredWallets.length > accounts.length) {
      throw WalletManifestManualBip85WalletCreationException(
        'BIP85 wallet creation did not return every created wallet',
      );
    }

    var manifestPublishFailed = false;
    try {
      await _publishLocalManifest.execute();
    } catch (e, stack) {
      manifestPublishFailed = true;
      log.warning(
        'Manual BIP85 wallet created but manifest publish failed',
        error: e,
        trace: stack,
      );
    }

    return CreateManualBip85WalletsResult(
      index: index,
      wallets: restoredWallets,
      manifestPublishFailed: manifestPublishFailed,
      partialFailure: partialFailure,
    );
  }

  Future<List<WalletManifestNetwork>> _networksFor(
    ManualBip85WalletNetworkSelection selection,
  ) async {
    final settings = await _settingsRepository.fetch();
    final bitcoin = settings.environment.isMainnet
        ? WalletManifestNetwork.bitcoin
        : WalletManifestNetwork.testnet3;
    final liquid = settings.environment.isMainnet
        ? WalletManifestNetwork.liquid
        : WalletManifestNetwork.liquidTestnet;

    return switch (selection) {
      ManualBip85WalletNetworkSelection.bitcoin => [bitcoin],
      ManualBip85WalletNetworkSelection.liquid => [liquid],
      ManualBip85WalletNetworkSelection.both => [bitcoin, liquid],
    };
  }

  Map<WalletManifestNetwork, String> _labelsFor(
    CreateManualBip85WalletsCommand command,
    List<WalletManifestNetwork> networks,
  ) {
    final labels = <WalletManifestNetwork, String>{};
    for (final network in networks) {
      final label = switch (network.isBitcoin) {
        true => command.bitcoinLabel,
        false => command.liquidLabel,
      }?.trim();
      if (label == null || label.isEmpty) {
        throw WalletManifestManualBip85LabelRequiredException();
      }
      try {
        _walletLabelReservationPolicy.throwIfReserved(label);
      } on ReservedWalletLabelException {
        throw WalletManifestManualBip85ReservedLabelException();
      }
      labels[network] = label;
    }
    return labels;
  }

  Future<Set<int>> _usedUnmanifestedMnemonic12IndexesForRoot({
    required String rootFingerprint,
    required List<WalletManifestOrigin> origins,
  }) async {
    final derivations = await _fetchAllBip85Derivations.execute(usage: null);
    final manifestedIndexes = origins
        .where((origin) => origin.rootFingerprint == rootFingerprint)
        .map((origin) => origin.bip85Index)
        .toSet();
    return derivations
        .where(
          (derivation) =>
              derivation.xprvFingerprint == rootFingerprint &&
              derivation.application == Bip85Application.bip39 &&
              derivation.status != Bip85Status.revoked,
        )
        .map((derivation) => _mnemonic12IndexForStoredPath(derivation.path))
        .whereType<int>()
        .where((index) => !manifestedIndexes.contains(index))
        .toSet();
  }

  int? _mnemonic12IndexForStoredPath(String path) {
    final parsed = Bip85DerivationPath.tryParse(path);
    if (parsed != null) return parsed.index;
    final relativeMatch = _relativeMnemonic12PathPattern.firstMatch(path);
    if (relativeMatch == null) return null;
    final index = int.tryParse(relativeMatch.group(1)!);
    if (index == null) return null;
    if (index > Bip85DerivationPath.maxHardenedChildIndex) return null;
    return index;
  }

  Set<({String path, WalletManifestNetwork network})> _usedWalletsForRoot({
    required String rootFingerprint,
    required List<WalletManifestOrigin> origins,
  }) {
    return origins
        .where((origin) => origin.rootFingerprint == rootFingerprint)
        .map(
          (origin) =>
              (path: origin.bip85DerivationPath.value, network: origin.network),
        )
        .toSet();
  }

  int _nextFreeIndex(
    List<WalletManifestNetwork> networks,
    Set<({String path, WalletManifestNetwork network})> usedWallets,
    Set<int> usedDerivationIndexes,
  ) {
    var index = 0;
    var path = Bip85DerivationPath.mnemonic12(index: index);
    while (_isReserved(index) ||
        usedDerivationIndexes.contains(index) ||
        networks.any((network) => _isUsed(path, network, usedWallets))) {
      index += 1;
      if (index > Bip85DerivationPath.maxHardenedChildIndex) {
        throw WalletManifestManualBip85InvalidIndexException(index);
      }
      path = Bip85DerivationPath.mnemonic12(index: index);
    }
    return index;
  }

  void _validateIndex(
    int index,
    List<WalletManifestNetwork> networks,
    Set<({String path, WalletManifestNetwork network})> usedWallets,
    Set<int> usedDerivationIndexes,
  ) {
    _validateStaticIndex(index);
    final path = Bip85DerivationPath.mnemonic12(index: index);
    if (usedDerivationIndexes.contains(index)) {
      throw WalletManifestManualBip85IndexUnavailableException(index);
    }
    if (networks.any((network) => _isUsed(path, network, usedWallets))) {
      throw WalletManifestManualBip85IndexUnavailableException(index);
    }
  }

  void _validateStaticIndex(int index) {
    if (index < 0 || index > Bip85DerivationPath.maxHardenedChildIndex) {
      throw WalletManifestManualBip85InvalidIndexException(index);
    }
    if (_isReserved(index)) {
      throw WalletManifestManualBip85IndexUnavailableException(index);
    }
  }

  bool _isReserved(int index) {
    return Bip85ManualIndexReservations.unavailable.contains(index);
  }

  bool _isUsed(
    Bip85DerivationPath path,
    WalletManifestNetwork network,
    Set<({String path, WalletManifestNetwork network})> usedWallets,
  ) {
    return usedWallets.contains((path: path.value, network: network));
  }
}
