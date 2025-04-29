import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'seed_model.freezed.dart';
part 'seed_model.g.dart';

@freezed
sealed class SeedModel with _$SeedModel {
  const SeedModel._();

  const factory SeedModel.bytes({required List<int> bytes}) = BytesSeedModel;

  const factory SeedModel.mnemonic({
    required List<String> mnemonicWords,
    String? passphrase,
  }) = MnemonicSeedModel;

  /// Convert `Seed` entity to `SeedModel`
  factory SeedModel.fromEntity(Seed entity) {
    return switch (entity) {
      BytesSeed(:final bytes) => SeedModel.bytes(bytes: bytes as List<int>),
      MnemonicSeed(:final mnemonicWords, :final passphrase) =>
        SeedModel.mnemonic(
          mnemonicWords: mnemonicWords,
          passphrase: passphrase,
        ),
    };
  }

  Seed toEntity() {
    return switch (this) {
      BytesSeedModel(:final bytes) => Seed.bytes(
        bytes: Uint8List.fromList(bytes),
      ),
      MnemonicSeedModel(:final mnemonicWords, :final passphrase) =>
        Seed.mnemonic(mnemonicWords: mnemonicWords, passphrase: passphrase),
    };
  }

  factory SeedModel.fromJson(Map<String, dynamic> json) =>
      _$SeedModelFromJson(json);
}
