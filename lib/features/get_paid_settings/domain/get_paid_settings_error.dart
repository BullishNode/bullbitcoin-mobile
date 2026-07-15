import 'package:bb_mobile/core/errors/bull_exception.dart';
import 'package:bb_mobile/core/utils/build_context_x.dart';
import 'package:flutter/widgets.dart';

enum GetPaidSettingsErrorKind { storage }

/// Sealed error family for the Get Paid settings feature (charter C1). Every
/// variant carries a [toTranslated] user message; the raw [cause] stays for
/// logs only and is never surfaced through presentation.
sealed class GetPaidSettingsException extends BullException {
  final GetPaidSettingsErrorKind kind;
  final Object? cause;

  GetPaidSettingsException._(this.kind, String message, {this.cause})
    : super(message);

  String toTranslated(BuildContext context) {
    return switch (this) {
      GetPaidSettingsStorageException() =>
        context.loc.getPaidSettingsGenericError,
    };
  }
}

final class GetPaidSettingsStorageException extends GetPaidSettingsException {
  GetPaidSettingsStorageException({Object? cause})
    : super._(
        GetPaidSettingsErrorKind.storage,
        'get paid settings storage failure',
        cause: cause,
      );
}
