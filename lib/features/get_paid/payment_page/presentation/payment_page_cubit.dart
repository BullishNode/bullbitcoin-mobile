import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/archive_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/archive_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/find_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_command.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/save_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/upload_payment_page_image_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/presentation/payment_page_error_message.dart';
import 'package:bb_mobile/features/get_paid/payment_page/presentation/payment_page_state.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PaymentPageCubit extends Cubit<PaymentPageState> {
  final FindPaymentPageUsecase _findPaymentPage;
  final SavePaymentPageUsecase _savePaymentPage;
  final ArchivePaymentPageUsecase _archivePaymentPage;
  final UploadPaymentPageImageUsecase _uploadImage;

  PaymentPageCubit({
    required FindPaymentPageUsecase findPaymentPage,
    required SavePaymentPageUsecase savePaymentPage,
    required ArchivePaymentPageUsecase archivePaymentPage,
    required UploadPaymentPageImageUsecase uploadImage,
  }) : _findPaymentPage = findPaymentPage,
       _savePaymentPage = savePaymentPage,
       _archivePaymentPage = archivePaymentPage,
       _uploadImage = uploadImage,
       super(const PaymentPageState());

  Future<void> load({required String nym}) async {
    if (nym.isEmpty) {
      emit(
        state.copyWith(
          nym: '',
          clearPage: true,
          error: 'Choose a Bullnym name before creating a payment page',
          isLoading: false,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        nym: nym,
        isLoading: true,
        clearError: true,
        saved: false,
        archived: false,
      ),
    );
    try {
      final page = await _findPaymentPage.execute(nym: nym);
      if (isClosed) return;
      if (page == null || page.isArchived) {
        emit(
          state.copyWith(
            nym: nym,
            isLoading: false,
            clearError: true,
            clearPage: true,
          ),
        );
        return;
      }
      emit(PaymentPageState.fromPage(page));
    } on PaymentPageApplicationError catch (e) {
      if (isClosed) return;
      emit(state.copyWith(isLoading: false, error: paymentPageErrorMessage(e)));
    } on Exception catch (e) {
      if (isClosed) return;
      log.warning('Payment Page load failed', error: e);
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  void setHeader(String value) {
    emit(state.copyWith(header: value, clearError: true, saved: false));
  }

  void setDescription(String value) {
    emit(state.copyWith(description: value, clearError: true, saved: false));
  }

  void setDisplayCurrency(String value) {
    emit(
      state.copyWith(displayCurrency: value, clearError: true, saved: false),
    );
  }

  void setWebsite(String value) {
    emit(state.copyWith(website: value, clearError: true, saved: false));
  }

  void setTwitter(String value) {
    emit(state.copyWith(twitter: value, clearError: true, saved: false));
  }

  void setInstagram(String value) {
    emit(state.copyWith(instagram: value, clearError: true, saved: false));
  }

  void setEnabled(bool value) {
    emit(state.copyWith(enabled: value, clearError: true, saved: false));
  }

  Future<void> save() async {
    if (state.nym.isEmpty || state.isBusy) return;
    emit(state.copyWith(isSaving: true, clearError: true, saved: false));
    try {
      final command = SavePaymentPageCommand(
        nym: state.nym,
        header: state.header.trim(),
        description: state.description.trim(),
        displayCurrency: state.displayCurrency,
        website: _blankToNull(state.website),
        twitter: _blankToNull(state.twitter),
        instagram: _blankToNull(state.instagram),
        enabled: state.enabled,
      );
      final page = await _savePaymentPage.execute(command: command);
      if (isClosed) return;
      emit(
        PaymentPageState.fromPage(
          page,
        ).copyWith(isSaving: false, saved: true, clearError: true),
      );
    } on PaymentPageApplicationError catch (e) {
      if (isClosed) return;
      emit(state.copyWith(isSaving: false, error: paymentPageErrorMessage(e)));
    } on Exception catch (e) {
      if (isClosed) return;
      log.warning('Payment Page save failed', error: e);
      emit(
        state.copyWith(
          isSaving: false,
          error: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  Future<void> archive() async {
    if (state.nym.isEmpty || state.isBusy) return;
    emit(state.copyWith(isArchiving: true, clearError: true, archived: false));
    try {
      await _archivePaymentPage.execute(
        command: ArchivePaymentPageCommand(nym: state.nym),
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          isArchiving: false,
          clearPage: true,
          archived: true,
          saved: false,
          clearError: true,
        ),
      );
    } on PaymentPageApplicationError catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(isArchiving: false, error: paymentPageErrorMessage(e)),
      );
    } on Exception catch (e) {
      if (isClosed) return;
      log.warning('Payment Page archive failed', error: e);
      emit(
        state.copyWith(
          isArchiving: false,
          error: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  Future<void> uploadImage(List<int> bytes) async {
    if (state.nym.isEmpty || !state.hasExistingPage || state.isBusy) return;
    emit(state.copyWith(isUploadingImage: true, clearError: true));
    try {
      final page = await _uploadImage.execute(nym: state.nym, bytes: bytes);
      if (isClosed) return;
      emit(
        PaymentPageState.fromPage(
          page,
        ).copyWith(isUploadingImage: false, clearError: true),
      );
    } on PaymentPageApplicationError catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          isUploadingImage: false,
          error: paymentPageErrorMessage(e),
        ),
      );
    } on Exception catch (e) {
      if (isClosed) return;
      log.warning('Payment Page image upload failed', error: e);
      emit(
        state.copyWith(
          isUploadingImage: false,
          error: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  String? _blankToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
