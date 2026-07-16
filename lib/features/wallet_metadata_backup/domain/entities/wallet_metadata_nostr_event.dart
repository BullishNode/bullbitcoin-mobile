import 'dart:convert';

import 'package:bb_mobile/core/nostr/nostr_authenticated_cipher.dart';
import 'package:bb_mobile/core/nostr/nostr_signed_event.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_limits.dart';
import 'package:crypto/crypto.dart';

const int walletMetadataNostrEventKind = 30078;

final class WalletMetadataNostrEvent {
  static final _opaqueTagPattern = RegExp(r'^[0-9a-f]{64}$');

  final NostrSignedEvent _event;
  final String dTag;
  final String ciphertextHash;
  final String serializedFrame;
  final int frameByteLength;

  factory WalletMetadataNostrEvent(NostrSignedEvent event) {
    if (event.kind != walletMetadataNostrEventKind ||
        event.tags.length != 1 ||
        event.tags.single.length != 2 ||
        event.tags.single.first != 'd') {
      throw ArgumentError.value(
        event,
        'event',
        'must be an opaque wallet metadata event',
      );
    }
    final dTag = event.tags.single[1];
    if (!_opaqueTagPattern.hasMatch(dTag)) {
      throw ArgumentError.value(
        dTag,
        'event',
        'must have one opaque 32-byte d tag',
      );
    }
    final ciphertext = NostrAuthenticatedCiphertext(event.content);
    if (ciphertext.value != event.content) {
      throw ArgumentError.value(
        event.content,
        'event',
        'must use canonical bare ciphertext content',
      );
    }
    final frame = const NostrSignedEventCodec().serialize(event);
    return WalletMetadataNostrEvent._(
      event: event,
      dTag: dTag,
      ciphertextHash: sha256
          .convert(base64.decode(ciphertext.value))
          .toString(),
      serializedFrame: frame,
      frameByteLength: utf8.encode(frame).length,
    );
  }

  const WalletMetadataNostrEvent._({
    required this._event,
    required this.dTag,
    required this.ciphertextHash,
    required this.serializedFrame,
    required this.frameByteLength,
  });

  String get id => _event.id;

  String get authorPublicKeyHex => _event.authorPublicKeyHex;

  int get createdAt => _event.createdAt;

  int get kind => _event.kind;

  List<List<String>> get tags => _event.tags;

  String get encryptedContent => _event.content;

  String get signatureHex => _event.signatureHex;

  bool get fitsProductionFrameLimit =>
      frameByteLength <= WalletMetadataBackupLimits.maxEventFrameBytes;

  NostrSignedEvent toNostrSignedEvent() => _event;
}
