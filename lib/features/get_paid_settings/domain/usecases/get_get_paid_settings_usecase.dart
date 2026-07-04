import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_settings.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/repositories/get_paid_settings_repository.dart';

/// Reads the persisted Get Paid automated-backup preference. Thin pass-through;
/// the error-mapping seam is the repository.
class GetGetPaidSettingsUsecase {
  final GetPaidSettingsRepository _repository;

  const GetGetPaidSettingsUsecase({required this._repository});

  Future<GetPaidSettings> execute() => _repository.fetch();
}
