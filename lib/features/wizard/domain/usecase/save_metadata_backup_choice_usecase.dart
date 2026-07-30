import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wizard/domain/repository/wizard_repository.dart';
import 'package:bb_mobile/features/wizard/domain/wizard_failure.dart';
import 'package:meta/meta.dart';

class SaveMetadataBackupChoiceUsecase {
  const SaveMetadataBackupChoiceUsecase({required this._repository});

  final WizardRepository _repository;

  @useResult
  Future<Result<void, WizardFailure>> execute(bool enabled) =>
      _repository.saveMetadataBackupChoice(enabled);
}
