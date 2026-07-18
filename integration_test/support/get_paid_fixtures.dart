import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/locator.dart';

// Shared valueless seed fixture for hermetic Get Paid lifecycle tests.
const getPaidFixtureMnemonicWords = <String>[
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'zoo',
  'wrong',
];

Future<void> ensureFixtureSeed([List<String>? mnemonicWords]) async {
  final words = mnemonicWords ?? getPaidFixtureMnemonicWords;
  final seeds = locator<SeedRepository>();
  final fingerprint = seeds.fingerprintFor(mnemonicWords: words);
  if (!await seeds.exists(fingerprint)) {
    await seeds.createFromMnemonic(mnemonicWords: words);
  }
}
