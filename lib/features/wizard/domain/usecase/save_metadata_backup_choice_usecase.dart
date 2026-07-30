import 'package:bb_mobile/features/wizard/domain/repository/wizard_repository.dart';

class SaveMetadataBackupChoiceUsecase {
  const SaveMetadataBackupChoiceUsecase({required this._repository});

  final WizardRepository _repository;

  Future<void> execute(bool enabled) =>
      _repository.saveMetadataBackupChoice(enabled);
}
