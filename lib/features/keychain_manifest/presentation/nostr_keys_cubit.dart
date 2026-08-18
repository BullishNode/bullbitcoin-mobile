// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/features/keychain_manifest/domain/entities/created_keychain_manifest_nostr_key.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/nostr_key_display.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

typedef LoadDefaultWalletNostrKeys =
    Future<List<KeychainManifestNostrKeyRecord>> Function();
typedef CreateUserNostrKey =
    Future<CreatedKeychainManifestNostrKey> Function({
      required String purpose,
      String? description,
      DateTime? now,
    });
typedef UpdateUserNostrKey =
    Future<void> Function({
      required String parentFingerprint,
      required String entryId,
      String? purpose,
      String? description,
      DateTime? now,
    });

/// Which name/description field a submitted form rejected, if any.
///
/// The entity is the real gate; this exists so the form can point at the
/// offending field instead of surfacing a generic failure snackbar.
enum NostrKeyFormError { nameRequired, nameTooLong, descriptionTooLong }

final class NostrKeysState {
  final List<KeychainManifestNostrKeyRecord> keys;
  final bool loading;
  final bool busy;
  final int failureRevision;

  /// Whether app-owned keys are revealed below the user keys. Screen-local by
  /// design: the cubit is created per route, so it resets on every visit.
  final bool showSystemKeys;

  final NostrKeyFormError? formError;

  const NostrKeysState({
    this.keys = const [],
    this.loading = false,
    this.busy = false,
    this.failureRevision = 0,
    this.showSystemKeys = false,
    this.formError,
  });

  /// Keys the user created, in stored order.
  List<KeychainManifestNostrKeyRecord> get userKeys => keys
      .where((key) => !KeychainManifestNostrKeyDisplay.of(key).isSystem)
      .toList(growable: false);

  /// App-owned keys. Retired roles are already excluded upstream.
  List<KeychainManifestNostrKeyRecord> get systemKeys => keys
      .where((key) => KeychainManifestNostrKeyDisplay.of(key).isSystem)
      .toList(growable: false);

  NostrKeysState copyWith({
    List<KeychainManifestNostrKeyRecord>? keys,
    bool? loading,
    bool? busy,
    int? failureRevision,
    bool? showSystemKeys,
    NostrKeyFormError? formError,
    bool clearFormError = false,
  }) {
    return NostrKeysState(
      keys: keys ?? this.keys,
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      failureRevision: failureRevision ?? this.failureRevision,
      showSystemKeys: showSystemKeys ?? this.showSystemKeys,
      formError: clearFormError ? null : (formError ?? this.formError),
    );
  }
}

final class NostrKeysCubit extends Cubit<NostrKeysState> {
  final LoadDefaultWalletNostrKeys _loadKeys;
  final CreateUserNostrKey _createKey;
  final UpdateUserNostrKey _updateKey;

  NostrKeysCubit({
    required LoadDefaultWalletNostrKeys loadKeys,
    required CreateUserNostrKey createKey,
    required UpdateUserNostrKey updateKey,
  }) : _loadKeys = loadKeys,
       _createKey = createKey,
       _updateKey = updateKey,
       super(const NostrKeysState());

  Future<void> load() async {
    if (isClosed) return;
    emit(state.copyWith(loading: true));
    try {
      final keys = await _loadKeys();
      if (!isClosed) emit(state.copyWith(keys: keys, loading: false));
    } on Exception catch (_) {
      _fail(loading: false);
    }
  }

  void setShowSystemKeys(bool show) {
    if (isClosed || state.showSystemKeys == show) return;
    emit(state.copyWith(showSystemKeys: show));
  }

  Future<bool> create(String name, {String? description}) async {
    if (isClosed || state.busy) return false;
    final formError = _validate(name: name, description: description);
    if (formError != null) {
      emit(state.copyWith(formError: formError));
      return false;
    }
    emit(state.copyWith(busy: true, clearFormError: true));
    try {
      await _createKey(purpose: name, description: description);
    } on Exception catch (_) {
      _fail(busy: false);
      return false;
    }
    await _reloadAfterCommittedMutation();
    return true;
  }

  /// Updates a user key's name and/or description. Returns false when the form
  /// was rejected or the write failed, so the caller can stay on the form.
  Future<bool> updateKey({
    required KeychainManifestNostrKeyRecord key,
    String? name,
    String? description,
  }) async {
    if (isClosed || state.busy) return false;
    final formError = _validate(
      name: name,
      description: description,
      nameRequired: name != null,
    );
    if (formError != null) {
      emit(state.copyWith(formError: formError));
      return false;
    }
    emit(state.copyWith(busy: true, clearFormError: true));
    try {
      await _updateKey(
        parentFingerprint: key.entry.parentFingerprint,
        entryId: key.entryId,
        purpose: name,
        description: description,
      );
    } on Exception catch (_) {
      _fail(busy: false);
      return false;
    }
    await _reloadAfterCommittedMutation();
    return true;
  }

  void reportRevealFailure() => _fail();

  void clearFormError() {
    if (isClosed || state.formError == null) return;
    emit(state.copyWith(clearFormError: true));
  }

  NostrKeyFormError? _validate({
    required String? name,
    required String? description,
    bool nameRequired = true,
  }) {
    final trimmedName = name?.trim();
    if (nameRequired && (trimmedName == null || trimmedName.isEmpty)) {
      return NostrKeyFormError.nameRequired;
    }
    if (trimmedName != null &&
        trimmedName.length >
            KeychainManifestNostrKeyMaterialization.maxPurposeLength) {
      return NostrKeyFormError.nameTooLong;
    }
    final trimmedDescription = description?.trim();
    if (trimmedDescription != null &&
        trimmedDescription.length >
            KeychainManifestNostrKeyMaterialization.maxDescriptionLength) {
      return NostrKeyFormError.descriptionTooLong;
    }
    return null;
  }

  Future<void> _reloadAfterCommittedMutation() async {
    try {
      final keys = await _loadKeys();
      if (!isClosed) emit(state.copyWith(keys: keys, busy: false));
    } on Exception catch (_) {
      // The mutation is already durable. Report the refresh problem without
      // inviting the user to repeat an irreversible creation/update.
      _fail(busy: false);
    }
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
