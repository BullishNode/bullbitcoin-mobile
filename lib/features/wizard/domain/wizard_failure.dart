import 'package:bb_mobile/core/failures/failure.dart';

sealed class WizardFailure extends Failure {
  const WizardFailure([super.logMessage]);
}

/// A wizard choice could not be saved to durable local storage.
final class WizardPersistenceFailure extends WizardFailure {
  const WizardPersistenceFailure([super.logMessage]);
}
