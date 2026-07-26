import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:bb_mobile/features/keychain_manifest/presentation/nostr_keys_cubit.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:flutter/widgets.dart';

/// Localized display name for a stored Nostr key.
///
/// A user key is named by what the user typed. An app-owned key is named from
/// its classified role, never from stored text, so a system key cannot be made
/// to look like an identity by whatever `purpose` happens to be in the row.
extension KeychainManifestNostrKeyRecordL10n on KeychainManifestNostrKeyRecord {
  String displayName(BuildContext context) {
    final display = KeychainManifestNostrKeyDisplay.of(this);
    if (!display.isSystem) return nostrKeyMaterialization.purpose;
    return switch (display.systemKind) {
      KeychainManifestNostrSystemKind.metadataBackup =>
        context.loc.settingsNostrKeysSystemMetadataBackup,
      KeychainManifestNostrSystemKind.bullnymAuth =>
        context.loc.settingsNostrKeysSystemBullnymAuth,
      KeychainManifestNostrSystemKind.nip05Verification =>
        context.loc.settingsNostrKeysSystemNip05Verification,
      // A reserved key this build has no role for, and the retired role the
      // listing already excludes: fall back to the stored label rather than
      // rendering an empty row.
      KeychainManifestNostrSystemKind.obsoleteWalletMetadataSigning ||
      KeychainManifestNostrSystemKind.none => nostrKeyMaterialization.purpose,
    };
  }
}

extension NostrKeyFormErrorL10n on NostrKeyFormError {
  String toTranslated(BuildContext context) => switch (this) {
    NostrKeyFormError.nameRequired =>
      context.loc.settingsNostrKeysNameRequiredError,
    NostrKeyFormError.nameTooLong =>
      context.loc.settingsNostrKeysNameTooLongError,
    NostrKeyFormError.descriptionTooLong =>
      context.loc.settingsNostrKeysDescriptionTooLongError,
  };
}
