import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

final class NostrKeysState {
  final List<KeychainManifestNostrKeyRecord> keys;
  final bool loading;
  final bool busy;
  final int failureRevision;

  const NostrKeysState({
    this.keys = const [],
    this.loading = false,
    this.busy = false,
    this.failureRevision = 0,
  });

  NostrKeysState copyWith({
    List<KeychainManifestNostrKeyRecord>? keys,
    bool? loading,
    bool? busy,
    int? failureRevision,
  }) {
    return NostrKeysState(
      keys: keys ?? this.keys,
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      failureRevision: failureRevision ?? this.failureRevision,
    );
  }
}

final class NostrKeysCubit extends Cubit<NostrKeysState> {
  final KeychainManifestFacade _manifest;

  NostrKeysCubit(this._manifest) : super(const NostrKeysState());

  Future<void> load() async {
    if (isClosed) return;
    emit(state.copyWith(loading: true));
    try {
      final keys = await _manifest.getDefaultWalletNostrKeys();
      if (!isClosed) emit(state.copyWith(keys: keys, loading: false));
    } catch (_) {
      _fail(loading: false);
    }
  }

  Future<bool> create(String purpose) async {
    if (isClosed || state.busy) return false;
    emit(state.copyWith(busy: true));
    try {
      await _manifest.createUserNostrKey(purpose: purpose);
      await _reloadAfterMutation();
      return true;
    } catch (_) {
      _fail(busy: false);
      return false;
    }
  }

  Future<void> updatePurpose({
    required KeychainManifestNostrKeyRecord key,
    required String purpose,
  }) async {
    if (isClosed || state.busy) return;
    emit(state.copyWith(busy: true));
    try {
      await _manifest.updateNostrKeyPurpose(
        parentFingerprint: key.entry.parentFingerprint,
        entryId: key.entryId,
        purpose: purpose,
      );
      await _reloadAfterMutation();
    } catch (_) {
      _fail(busy: false);
    }
  }

  Future<String?> reveal(KeychainManifestNostrKeyRecord key) async {
    try {
      return await _manifest.revealNostrKeyNsec(key);
    } catch (_) {
      _fail();
      return null;
    }
  }

  Future<void> _reloadAfterMutation() async {
    final keys = await _manifest.getDefaultWalletNostrKeys();
    if (!isClosed) emit(state.copyWith(keys: keys, busy: false));
  }

  void _fail({bool? loading, bool? busy}) {
    if (isClosed) return;
    emit(
      state.copyWith(
        loading: loading,
        busy: busy,
        failureRevision: state.failureRevision + 1,
      ),
    );
  }
}
