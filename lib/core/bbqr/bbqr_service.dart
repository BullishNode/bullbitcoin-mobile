import 'dart:convert';

import 'package:bb_mobile/core/bbqr/bbqr_options.dart';
import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:bdk_flutter/bdk_flutter.dart' as bdk;
import 'package:dart_bbqr/bbqr.dart' as bbqr;

class BbqrService {
  final Map<int, String> parts = {};

  BbqrService();

  Future<String?> collectPsbt(String payload) async {
    if (!BbqrOptions.isValid(payload)) return null;

    final options = BbqrOptions.decode(payload);
    parts[options.share] = payload;

    if (options.total < parts.length) {
      // reset another state.bbqr
      // and expect the next scan to be a new BBQR
      parts.clear();
      return null;
    }

    if (options.total == parts.length) {
      final bbqrParts = parts.values.toList();
      final bbqrJoiner = await bbqr.Joined.tryFromParts(parts: bbqrParts);
      final psbt = await PartiallySignedTransaction.fromString(
        base64.encode(bbqrJoiner.data),
      );
      return psbt.toString();
    } else {
      return null;
    }
  }

  static Future<List<String>> splitPsbt(String psbt) async {
    try {
      final bdkPsbt = await bdk.PartiallySignedTransaction.fromString(psbt);
      final psbtBytes = bdkPsbt.serialize();
      final bbqrOptions = await bbqr.SplitOptions.default_();

      final split = await bbqr.Split.tryFromData(
        bytes: psbtBytes,
        fileType: bbqr.FileType.psbt,
        options: bbqrOptions,
      );

      return split.parts;
    } catch (e) {
      rethrow;
    }
  }
}
