import 'package:bb_mobile/core/failures/failure.dart';

sealed class GetPaidFailure extends Failure {
  final bool retryable;

  const GetPaidFailure._({required this.retryable, String? logMessage})
    : super(logMessage);

  const factory GetPaidFailure.unavailable({String? logMessage}) =
      GetPaidUnavailableFailure;

  const factory GetPaidFailure.localPreparation({String? logMessage}) =
      GetPaidLocalPreparationFailure;

  const factory GetPaidFailure.invalidResponse({String? logMessage}) =
      GetPaidInvalidResponseFailure;

  const factory GetPaidFailure.incompleteHistory({String? logMessage}) =
      GetPaidIncompleteHistoryFailure;
}

final class GetPaidUnavailableFailure extends GetPaidFailure {
  const GetPaidUnavailableFailure({super.logMessage})
    : super._(retryable: true);
}

final class GetPaidLocalPreparationFailure extends GetPaidFailure {
  const GetPaidLocalPreparationFailure({super.logMessage})
    : super._(retryable: false);
}

final class GetPaidInvalidResponseFailure extends GetPaidFailure {
  const GetPaidInvalidResponseFailure({super.logMessage})
    : super._(retryable: true);
}

/// The full-history walk could not be completed: the server exhausted the page
/// cap while still offering a continuation cursor, or it looped by repeating a
/// cursor. The export must fail rather than present a truncated file as the
/// complete accounting history. Not retryable — the same walk yields the same
/// truncation.
final class GetPaidIncompleteHistoryFailure extends GetPaidFailure {
  const GetPaidIncompleteHistoryFailure({super.logMessage})
    : super._(retryable: false);
}
