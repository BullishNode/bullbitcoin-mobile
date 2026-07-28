import 'dart:convert';
import 'dart:io';

import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:flutter_test/flutter_test.dart';

// The client's reservation sets are an immediate-feedback filter in front of an
// authoritative server check, so a client set that is WIDER than the server's
// silently forbids names the server would happily grant, and a NARROWER one
// promises names the server will reject after the merchant has committed to
// them. Neither shows up as a client-side failure, which is why these lists are
// pinned rather than eyeballed.
//
// The mobile package cannot read the bullnym repo at test time, so the server's
// two lists are materialized in the fixture below; its `_provenance` block
// records the exact server commit and file they were extracted from. When the
// server's lists change, re-extract the fixture — do not edit either side alone.
void main() {
  final fixture =
      jsonDecode(
            File(
              'test/features/bullnym/fixtures/server_reserved_names.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final serverNyms = (fixture['reserved_nyms'] as List).cast<String>().toSet();
  final serverAliasOnly = (fixture['reserved_aliases'] as List)
      .cast<String>()
      .toSet();
  // The server layers RESERVED_ALIASES over RESERVED_NYMS in
  // `is_reserved_alias`, so the effective alias set is the union.
  final serverAliases = {...serverNyms, ...serverAliasOnly};

  group('reserved-name parity with the released bullnym server', () {
    test('fixture provenance names the server commit it came from', () {
      final provenance = fixture['_provenance'] as Map<String, dynamic>;
      expect(provenance['source_file'], 'src/reserved_nyms.rs');
      expect(provenance['source_commit'], '7828e7c');
      expect(provenance['source_tag'], '0.4');
    });

    test('reserved nyms match the server exactly, both directions', () {
      expect(
        bullnymReservedNyms.difference(serverNyms),
        isEmpty,
        reason: 'client blocks nyms the server allows',
      );
      expect(
        serverNyms.difference(bullnymReservedNyms),
        isEmpty,
        reason: 'client allows nyms the server blocks',
      );
    });

    test('reserved aliases match the server exactly, both directions', () {
      expect(
        bullnymReservedAliases.difference(serverAliases),
        isEmpty,
        reason: 'client blocks aliases the server allows',
      );
      expect(
        serverAliases.difference(bullnymReservedAliases),
        isEmpty,
        reason: 'client allows aliases the server blocks',
      );
    });

    test('every reserved name is rejected by the matching claim factory', () {
      for (final value in serverNyms) {
        expect(
          () => BullnymPublicName.nymClaim(value),
          throwsArgumentError,
          reason: value,
        );
      }
      for (final value in serverAliases) {
        expect(
          () => BullnymPublicName.aliasClaim(value),
          throwsArgumentError,
          reason: value,
        );
      }
    });

    test('single digits are claimable aliases, as the server permits', () {
      // The server's own tests assert !is_reserved_alias("0") and
      // !is_reserved_alias("1"); the client used to reserve both.
      for (final value in ['0', '1']) {
        expect(bullnymReservedAliases.contains(value), isFalse, reason: value);
        expect(BullnymPublicName.aliasClaim(value).value, value);
        expect(BullnymPublicName.nymClaim(value).value, value);
      }
    });
  });
}
