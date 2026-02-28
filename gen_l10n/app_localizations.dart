import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen_l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('ru'),
    Locale('tr')
  ];

  /// No description provided for @menuProfile.
  ///
  /// In tr, this message translates to:
  /// **'Profil'**
  String get menuProfile;

  /// No description provided for @menuHistory.
  ///
  /// In tr, this message translates to:
  /// **'Geçmiş'**
  String get menuHistory;

  /// No description provided for @menuPayments.
  ///
  /// In tr, this message translates to:
  /// **'Ödemeler'**
  String get menuPayments;

  /// No description provided for @menuAiAnalyze.
  ///
  /// In tr, this message translates to:
  /// **'TakNak AI Analiz'**
  String get menuAiAnalyze;

  /// No description provided for @menuLanguage.
  ///
  /// In tr, this message translates to:
  /// **'Dil'**
  String get menuLanguage;

  /// No description provided for @menuSettings.
  ///
  /// In tr, this message translates to:
  /// **'Ayarlar'**
  String get menuSettings;

  /// No description provided for @support.
  ///
  /// In tr, this message translates to:
  /// **'Destek'**
  String get support;

  /// No description provided for @languageSelectTitle.
  ///
  /// In tr, this message translates to:
  /// **'Dil Seç'**
  String get languageSelectTitle;

  /// No description provided for @langTurkish.
  ///
  /// In tr, this message translates to:
  /// **'Türkçe'**
  String get langTurkish;

  /// No description provided for @langEnglish.
  ///
  /// In tr, this message translates to:
  /// **'English'**
  String get langEnglish;

  /// No description provided for @langArabic.
  ///
  /// In tr, this message translates to:
  /// **'العربية'**
  String get langArabic;

  /// No description provided for @langGerman.
  ///
  /// In tr, this message translates to:
  /// **'Deutsch'**
  String get langGerman;

  /// No description provided for @langRussian.
  ///
  /// In tr, this message translates to:
  /// **'Русский'**
  String get langRussian;

  /// No description provided for @homeSearchHint.
  ///
  /// In tr, this message translates to:
  /// **'Nereye / Ne lazım?'**
  String get homeSearchHint;

  /// No description provided for @serviceTrip.
  ///
  /// In tr, this message translates to:
  /// **'Yolculuk'**
  String get serviceTrip;

  /// No description provided for @serviceTripSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Paylaşımlı / özel'**
  String get serviceTripSubtitle;

  /// No description provided for @serviceTow.
  ///
  /// In tr, this message translates to:
  /// **'Çekici'**
  String get serviceTow;

  /// No description provided for @serviceTowSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Yolda kaldın mı?'**
  String get serviceTowSubtitle;

  /// No description provided for @serviceCargo.
  ///
  /// In tr, this message translates to:
  /// **'Nakliye'**
  String get serviceCargo;

  /// No description provided for @serviceCargoSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Panelvan / Kamyonet'**
  String get serviceCargoSubtitle;

  /// No description provided for @serviceTire.
  ///
  /// In tr, this message translates to:
  /// **'Lastik'**
  String get serviceTire;

  /// No description provided for @serviceTireSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Değişim / servis'**
  String get serviceTireSubtitle;

  /// No description provided for @oneTapHelp.
  ///
  /// In tr, this message translates to:
  /// **'Tek dokunuşla en yakın\nyardım'**
  String get oneTapHelp;

  /// No description provided for @helpButton.
  ///
  /// In tr, this message translates to:
  /// **'Yardım'**
  String get helpButton;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'de', 'en', 'ru', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
