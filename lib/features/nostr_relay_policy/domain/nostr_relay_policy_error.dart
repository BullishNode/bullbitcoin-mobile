import 'package:bb_mobile/core/errors/bull_exception.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:flutter/widgets.dart';

/// Sealed error family for the Nostr relay policy feature (AD9e). The former
/// standalone `NostrRelayUrlException` is folded in so every variant carries a
/// user-facing `toTranslated` message instead of leaking a developer string.
sealed class NostrRelayPolicyException extends BullException {
  NostrRelayPolicyException._(super.message);

  String toTranslated(BuildContext context) {
    return switch (this) {
      // A malformed relay URL is a configuration/validation fault rather than
      // a user action, so it maps to the generic message; the raw detail stays
      // in logs via the exception message.
      NostrRelayUrlException() => context.loc.anErrorOccurred,
    };
  }
}

final class NostrRelayUrlException extends NostrRelayPolicyException {
  NostrRelayUrlException(super.message) : super._();
}
