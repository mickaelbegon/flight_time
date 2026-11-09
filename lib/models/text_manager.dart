import 'package:flight_time/models/custom_callback.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Language { en, fr }

class TranslatableString {
  final String en;
  final String fr;

  TranslatableString({required this.en, required this.fr});

  String get value => TextManager.instance.language == Language.en ? en : fr;
}

class TextManager {
  // Prepare the singleton
  static final TextManager _singleton = TextManager._();
  static TextManager get instance => _singleton;
  TextManager._() {
    SharedPreferences.getInstance().then((prefs) {
      final lang = prefs.getString('language');
      if (lang == 'en') {
        language = Language.en;
      } else if (lang == 'fr') {
        language = Language.fr;
      }
    });
  }

  // The current language
  Language _language = Language.fr;
  Language get language => _language;
  set language(Language value) {
    _language = value;
    onLanguageChanged.notifyListeners();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('language', value.toString().split('.').last);
    });
  }

  final onLanguageChanged = CustomCallback<void Function()>();

  // The title
  TranslatableString get title =>
      TranslatableString(en: 'Flight Time', fr: 'Temps de vol');

  // The MainDrawer related texts
  TranslatableString get camera =>
      TranslatableString(en: 'Camera', fr: 'Caméra');

  TranslatableString get playback =>
      TranslatableString(en: 'Playback', fr: 'Lecture');

  TranslatableString get experimentalCamera => TranslatableString(
      en: 'Nitro Camera (experimental)', fr: 'Nitro Camera (expérimental)');

  // The Recording related texts
  TranslatableString get recordingVideo =>
      TranslatableString(en: 'Video recording', fr: 'Enregistrement vidéo');

  TranslatableString get preparingTrial => TranslatableString(
      en: 'Preparing the video', fr: 'Préparation de la vidéo');

  TranslatableString get visualizingVideo => TranslatableString(
      en: 'Visualizing video', fr: 'Visionnement de la vidéo');

  TranslatableString get fpsWarningTitle =>
      TranslatableString(en: 'Frame rate', fr: 'Fréquence d\'images');

  TranslatableString get fpsWarningDetails => TranslatableString(
        en: 'It is not possible to automatically obtain the acquisition '
            'frequency of the video. If the video reacts too slowly '
            'or too quickly using the frame by frame (< and >) navigation buttons, you '
            'can change the acquisition frequency at the top right of this page.',
        fr: 'Il n\'est pas possible d\'obtenir automatiquement la fréquence '
            'd\'acquisition de la vidéo. Si la vidéo réagit trop '
            'lentement ou trop rapidement en utilisant les boutons de navigation '
            'image par image (< et >), vous pouvez changer la fréquence d\'acquisition en '
            'haut à droite de cette page.',
      );

  // Save trial dialog texts
  TranslatableString get saveTrial =>
      TranslatableString(en: 'Save Trial', fr: 'Sauvegarder l\'essai');

  TranslatableString get athleteName =>
      TranslatableString(en: 'Athlete name', fr: 'Nom de l\'athlète');

  TranslatableString get trialName =>
      TranslatableString(en: 'Trial name', fr: 'Nom de l\'essai');

  // Show trial texts
  TranslatableString get athletes =>
      TranslatableString(en: 'Athletes', fr: 'Athlètes');

  TranslatableString get flightTime =>
      TranslatableString(en: 'Time', fr: 'Temps');

  TranslatableString get flightHeight =>
      TranslatableString(en: 'Height', fr: 'Hauteur');

  TranslatableString get areYouSureDelete => TranslatableString(
      en: 'Do you really want to delete the video?',
      fr: 'Voulez-vous vraiment supprimer la vidéo?');

  // The About page texts
  TranslatableString get about =>
      TranslatableString(en: 'About', fr: 'À propos');

  TranslatableString get howTheAppWorks => TranslatableString(
      en: 'How the app works', fr: 'Fonctionnement de l\'application');

  TranslatableString get howTheAppWorksDetails => TranslatableString(
        en: 'The app allows to film an athlete in action and to select the '
            'take-off and landing moments. The app then calculates the flight '
            'duration and the height reached. The videos can be saved and '
            'viewed later.',
        fr: 'L\'application permet de filmer un athlète en action et de sélectionner '
            'l\'instant de décollage et d\'atterrisage. L\'application calcule alors '
            'la durée du vol et la hauteur atteinte. Les vidéos peuvent être sauvegardées '
            'et visionnées ultérieurement.',
      );

  TranslatableString get videoTutorialTitle =>
      TranslatableString(en: 'Video tutorial', fr: 'Tutoriel vidéo');

  TranslatableString get videoTutorialDetails => TranslatableString(
        en: 'Here is a video that explains how to use the app.',
        fr: 'Voici une vidéo qui explique comment utiliser l\'application.',
      );

  TranslatableString get videoTutorialLink => TranslatableString(
        en: 'Coming soon',
        fr: 'À venir',
      );

  TranslatableString get acknowledgementsTitle =>
      TranslatableString(en: 'Acknowledgements', fr: 'Remerciements');

  TranslatableString get acknowledgementsDetails => TranslatableString(
        en: 'Coming soon',
        fr: 'À venir',
      );

  // Misc texts
  TranslatableString get french => TranslatableString(en: 'Fr', fr: 'Fr');
  TranslatableString get english => TranslatableString(en: 'En', fr: 'En');

  TranslatableString get areYouSureQuit => TranslatableString(
      en: 'Do you really want to quit?', fr: 'Voulez-vous vraiment quitter?');

  TranslatableString get youWillLoseYourProgress => TranslatableString(
      en: 'You will lose your progress.',
      fr: 'Vous perdrez votre progression.');

  // The texts for the buttons
  TranslatableString get confirm =>
      TranslatableString(en: 'Confirm', fr: 'Confirmer');

  TranslatableString get cancel =>
      TranslatableString(en: 'Cancel', fr: 'Annuler');

  TranslatableString get quit => TranslatableString(en: 'Quit', fr: 'Quitter');

  TranslatableString get no => TranslatableString(en: 'No', fr: 'Non');

  TranslatableString get yes => TranslatableString(en: 'Yes', fr: 'Oui');

  TranslatableString get unclassified =>
      TranslatableString(en: 'Unclassified', fr: 'Non classés');
}
