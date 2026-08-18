part of 'wizard_bloc.dart';

@freezed
sealed class WizardState with _$WizardState {
  const factory WizardState({
    @Default(WizardChoices()) WizardChoices choices,
    @Default(false) bool finished,
    @Default(false) bool metadataBackupSaving,
    @Default(false) bool metadataBackupSaveFailed,
    @Default(false) bool completionSaving,
    @Default(false) bool completionSaveFailed,
  }) = _WizardState;
  const WizardState._();

  bool get persistenceSaving => metadataBackupSaving || completionSaving;
}
