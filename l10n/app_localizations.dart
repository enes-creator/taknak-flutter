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
/// import 'l10n/app_localizations.dart';
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

  /// No description provided for @appTitle.
  ///
  /// In tr, this message translates to:
  /// **'TakNak'**
  String get appTitle;

  /// No description provided for @devam.
  ///
  /// In tr, this message translates to:
  /// **'Devam'**
  String get devam;

  /// No description provided for @iptal.
  ///
  /// In tr, this message translates to:
  /// **'İptal'**
  String get iptal;

  /// No description provided for @tamam.
  ///
  /// In tr, this message translates to:
  /// **'Tamam'**
  String get tamam;

  /// No description provided for @uygula.
  ///
  /// In tr, this message translates to:
  /// **'Uygula'**
  String get uygula;

  /// No description provided for @hata.
  ///
  /// In tr, this message translates to:
  /// **'Hata'**
  String get hata;

  /// No description provided for @yukleniyor.
  ///
  /// In tr, this message translates to:
  /// **'Yükleniyor...'**
  String get yukleniyor;

  /// No description provided for @belirlenmedi.
  ///
  /// In tr, this message translates to:
  /// **'Belirlenmedi'**
  String get belirlenmedi;

  /// No description provided for @superAnalizBaslik.
  ///
  /// In tr, this message translates to:
  /// **'TakNak Süper Zeka'**
  String get superAnalizBaslik;

  /// No description provided for @analizYapButon.
  ///
  /// In tr, this message translates to:
  /// **'Süper Analiz Yap'**
  String get analizYapButon;

  /// No description provided for @ornekMetin.
  ///
  /// In tr, this message translates to:
  /// **'Örn: Beşiktaş\'tan Ataşehir\'e 3+1 ev taşınacak...'**
  String get ornekMetin;

  /// No description provided for @analizSonucu.
  ///
  /// In tr, this message translates to:
  /// **'Analiz Sonucu'**
  String get analizSonucu;

  /// No description provided for @yolculuguBaslat.
  ///
  /// In tr, this message translates to:
  /// **'YOLCULUĞU BAŞLAT'**
  String get yolculuguBaslat;

  /// No description provided for @adresBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Adres'**
  String get adresBaslik;

  /// No description provided for @nereden.
  ///
  /// In tr, this message translates to:
  /// **'Nereden'**
  String get nereden;

  /// No description provided for @nereye.
  ///
  /// In tr, this message translates to:
  /// **'Nereye'**
  String get nereye;

  /// No description provided for @adresAra.
  ///
  /// In tr, this message translates to:
  /// **'Adres ara...'**
  String get adresAra;

  /// No description provided for @adresSec.
  ///
  /// In tr, this message translates to:
  /// **'Adres Seç'**
  String get adresSec;

  /// No description provided for @konumAliniyor.
  ///
  /// In tr, this message translates to:
  /// **'Konum alınıyor...'**
  String get konumAliniyor;

  /// No description provided for @haritaKapaliUyari.
  ///
  /// In tr, this message translates to:
  /// **'Harita kapalı, lütfen listeden seçiniz.'**
  String get haritaKapaliUyari;

  /// No description provided for @yolculukTipiBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Yolculuk Tipi'**
  String get yolculukTipiBaslik;

  /// No description provided for @paylasimli.
  ///
  /// In tr, this message translates to:
  /// **'Paylaşımlı'**
  String get paylasimli;

  /// No description provided for @ozel.
  ///
  /// In tr, this message translates to:
  /// **'Özel'**
  String get ozel;

  /// No description provided for @havalimani.
  ///
  /// In tr, this message translates to:
  /// **'Havalimanı'**
  String get havalimani;

  /// No description provided for @rezervasyon.
  ///
  /// In tr, this message translates to:
  /// **'Rezervasyon'**
  String get rezervasyon;

  /// No description provided for @aracSecimiBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Araç Seçimi'**
  String get aracSecimiBaslik;

  /// No description provided for @motor.
  ///
  /// In tr, this message translates to:
  /// **'Motor'**
  String get motor;

  /// No description provided for @binek.
  ///
  /// In tr, this message translates to:
  /// **'Binek'**
  String get binek;

  /// No description provided for @panelvan.
  ///
  /// In tr, this message translates to:
  /// **'Panelvan'**
  String get panelvan;

  /// No description provided for @vip.
  ///
  /// In tr, this message translates to:
  /// **'VIP'**
  String get vip;

  /// No description provided for @kamyonet.
  ///
  /// In tr, this message translates to:
  /// **'Kamyonet'**
  String get kamyonet;

  /// No description provided for @tir.
  ///
  /// In tr, this message translates to:
  /// **'TIR'**
  String get tir;

  /// No description provided for @kadinSurucu.
  ///
  /// In tr, this message translates to:
  /// **'Sadece Kadın Sürücü'**
  String get kadinSurucu;

  /// No description provided for @evcilHayvan.
  ///
  /// In tr, this message translates to:
  /// **'Evcil Hayvan Dostu'**
  String get evcilHayvan;

  /// No description provided for @engelliErisimi.
  ///
  /// In tr, this message translates to:
  /// **'Engelli Erişimi Uygun'**
  String get engelliErisimi;

  /// No description provided for @genisArac.
  ///
  /// In tr, this message translates to:
  /// **'6-8 Kişilik Geniş Araç'**
  String get genisArac;

  /// No description provided for @yardimciPersonel.
  ///
  /// In tr, this message translates to:
  /// **'Yardımcı Personel İsteği'**
  String get yardimciPersonel;
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
