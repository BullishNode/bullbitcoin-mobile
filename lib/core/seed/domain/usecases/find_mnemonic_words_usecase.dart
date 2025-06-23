import 'package:bb_mobile/core/seed/domain/repositories/word_list_repository.dart';

class FindMnemonicWordsUsecase {
  final WordListRepository _wordListRepository;

  FindMnemonicWordsUsecase({required WordListRepository wordListRepository})
    : _wordListRepository = wordListRepository;

  List<String> execute(String firstLetters) {
    final words = _wordListRepository.getWordsStartingWith(firstLetters);
    return words;
  }
}
