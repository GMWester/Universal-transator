import 'core/config.dart';
import 'core/paths.dart';
import 'core/settings.dart';
import 'data/characters.dart';
import 'data/dictionary.dart';
import 'data/grammar.dart';
import 'data/languages.dart';
import 'data/packs.dart';
import 'l10n/strings.dart';
import 'speech/speech.dart';
import 'translate/translator.dart';
import 'update/updater.dart';

/// All services of the app.
class AppState {
  AppState._(this.settings);
  static late AppState I;

  final Settings settings;
  late final Dictionary dict;
  late final Speech speech;
  late final Translator translator;

  LanguageRepository get langs => LanguageRepository.instance;
  PackManager get packs => PackManager.instance;
  Grammar get grammar => Grammar.instance;
  Characters get chars => Characters.instance;
  Updater get updater => Updater.instance;
  S get s => S(settings.appLanguage);

  static Future<AppState> init() async {
    final settings = await Settings.load();
    final st = AppState._(settings);
    await AppConfig.load();
    await AppPaths.init();
    await Future.wait([
      LanguageRepository.instance.init(settings.appLanguage),
      Grammar.instance.init(),
      Characters.instance.init(),
      Updater.instance.init(),
    ]);
    await PackManager.instance.init();
    st.dict = Dictionary(PackManager.instance);
    st.speech = Speech(st.dict, settings);
    st.translator = Translator(st.dict, Grammar.instance, settings);
    return I = st;
  }
}
