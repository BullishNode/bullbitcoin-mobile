import 'package:bb_mobile/core/nostr/nostr_authenticated_cipher.dart';
import 'package:bb_mobile/core/nostr/nostr_signed_event.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_encryption_key.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_nostr_event.dart';

final class WalletMetadataNostrEventEncodingException implements Exception {
  final String message;
  final Object? cause;

  const WalletMetadataNostrEventEncodingException(this.message, {this.cause});

  @override
  String toString() => 'WalletMetadataNostrEventEncodingException: $message';
}

final class WalletMetadataNostrEventEncoder {
  final RecoverBullNostrAuthenticatedCipher cipher;

  const WalletMetadataNostrEventEncoder({
    this.cipher = const RecoverBullNostrAuthenticatedCipher(),
  });

  WalletMetadataNostrEvent encode({
    required String plaintext,
    required String dTag,
    required int createdAt,
    required WalletMetadataEncryptionKey encryptionKey,
    required WalletMetadataNostrSigner signer,
  }) {
    try {
      final ciphertext = cipher.encrypt(
        plaintext: plaintext,
        key: NostrAuthenticatedCipherKey(encryptionKey.hex),
      );
      final draft = NostrEventDraft(
        authorPublicKeyHex: signer.publicKeyHex,
        createdAt: createdAt,
        kind: walletMetadataNostrEventKind,
        tags: [
          ['d', dTag],
        ],
        content: ciphertext.value,
      );
      final signature = signer.signHashHex(draft.id);
      return WalletMetadataNostrEvent(
        NostrSignedEvent.fromDraft(draft: draft, signatureHex: signature),
      );
    } on NostrAuthenticatedCipherException catch (e) {
      throw WalletMetadataNostrEventEncodingException(
        'failed to encrypt wallet metadata event',
        cause: e,
      );
    } on NostrEventException catch (e) {
      throw WalletMetadataNostrEventEncodingException(
        'failed to encode wallet metadata event',
        cause: e,
      );
    }
  }
}
