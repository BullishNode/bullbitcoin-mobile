import 'package:bb_mobile/core/errors/exchange_errors.dart';
import 'package:bb_mobile/core/exchange/domain/entity/user_summary.dart';
import 'package:bb_mobile/core/exchange/domain/usecases/delete_exchange_api_key_usecase.dart';
import 'package:bb_mobile/core/exchange/domain/usecases/get_exchange_user_summary_usecase.dart';
import 'package:bb_mobile/core/exchange/domain/usecases/save_exchange_api_key_usecase.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'exchange_state.freezed.dart';

@freezed
abstract class ExchangeState with _$ExchangeState {
  const factory ExchangeState({
    UserSummary? userSummary,
    ApiKeyException? apiKeyException,
    GetExchangeUserSummaryException? getUserSummaryException,
    SaveExchangeApiKeyException? saveApiKeyException,
    DeleteExchangeApiKeyException? deleteApiKeyException,
  }) = _ExchangeState;

  const ExchangeState._();

  bool get isFetchingUserSummary =>
      userSummary == null &&
      getUserSummaryException == null &&
      apiKeyException == null;
  bool get isApiKeyInvalid => apiKeyException != null;
  bool get hasUser => userSummary != null;

  bool get isFullyVerifiedKycLevel =>
      userSummary?.groups.contains('KYC_IDENTITY_VERIFIED') ?? false;
  bool get isLightKycLevel =>
      userSummary?.groups.contains('KYC_LIGHT_VERIFICATION') ?? false;
  bool get isLimitedKycLevel =>
      userSummary?.groups.contains('KYC_LIMITED_VERIFICATION') ?? false;

  List<UserBalance> get balances =>
      userSummary?.balances.where((b) => b.amount > 0).toList() ?? [];
}
