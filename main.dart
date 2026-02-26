import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'gen_l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'firebase_options.dart';
import 'address_search_page.dart';
import 'taknak_analiz_ekrani.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const TakNakApp());}





class TakNakApp extends StatefulWidget {
  const TakNakApp({super.key});

  static const Color taknakOrange = Color(0xFFFF6A00);
  static const String _kLocaleKey = 'taknak_locale';

  /// Uygulama içinden dili anında değiştirmek için:
  /// TakNakApp.setLocale(context, const Locale('en'));
  static void setLocale(BuildContext context, Locale? locale) {
    final state = context.findAncestorStateOfType<_TakNakAppState>();
    state?._setLocale(locale);
  }

  @override
  State<TakNakApp> createState() => _TakNakAppState();
}

class _TakNakAppState extends State<TakNakApp> {
  Locale? _locale;

  @override
  void initState() {
    super.initState();
    _loadSavedLocale();
  }

  Future<void> _loadSavedLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(TakNakApp._kLocaleKey);
      if (code != null && code.trim().isNotEmpty) {
        setState(() => _locale = Locale(code.trim()));
      }
    } catch (_) {
      // Sessiz geç: kayıtlı dil yoksa zaten sistem diliyle açılacak.
    }
  }

  Future<void> _setLocale(Locale? locale) async {
    setState(() => _locale = locale);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (locale == null) {
        await prefs.remove(TakNakApp._kLocaleKey);
      } else {
        await prefs.setString(TakNakApp._kLocaleKey, locale.languageCode);
      }
    } catch (_) {
      // Sessiz geç
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: const [
        Locale('tr'),
        Locale('en'),
        Locale('ar'),
        Locale('de'),
        Locale('ru'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx)?.appTitle ?? 'TAKNAK',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: TakNakApp.taknakOrange),
      ),
      home: const AuthGate(
        child: LocationPermissionGate(child: HomePage()),
      ),
    );
  }
}

/// =======================
/// APP STORE ( STATE)
/// =======================

enum PaymentMethod { cash, card }

class ActivityRecord {
  final String type;
  final String title;
  final IconData? icon;
  final String dateStr;
  ActivityRecord(this.type, this.title, this.dateStr, {this.icon});
}

class AppStore {
  static String userName = 'Enes';
  static String phone = '+90 5xx xxx xx xx';

  /// Auth durumu (backend entegrasyonu yoksa local state ile yonetilir).
  static final ValueNotifier<bool> isLoggedIn = ValueNotifier<bool>(false);

  static PaymentMethod paymentMethod = PaymentMethod.cash;

  // KVKK/Sözleşme gate
  static bool kvkkAccepted = false;
  static bool contractAccepted = false;

  // Geçmiş aktivite
  static final List<ActivityRecord> history = <ActivityRecord>[];

  static String paymentLabel() {
    switch (paymentMethod) {
      case PaymentMethod.cash:
        return 'Nakit';
      case PaymentMethod.card:
        return 'Kart';
    }
  }

  static bool get consentsOk => kvkkAccepted && contractAccepted;

  static void addHistory(String type, String title) {
    final now = DateTime.now();
    final d =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
    history.insert(0, ActivityRecord(type, title, d));
  }
}

/// ===================
/// AUTH GATE
/// ===================

class AuthGate extends StatelessWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppStore.isLoggedIn,
      builder: (context, loggedIn, _) {
        if (loggedIn) return child;
        return const AuthStartPage();
      },
    );
  }
}

/// =======================
/// FIREBASE (MINIMAL)
/// =======================

class FirebaseService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Basit bir talep kaydı oluşturur.
  /// Koleksiyon: requests
  static Future<String> createRequest({
    required String flowTitle,
    int? basePriceTry,
    Map<String, dynamic>? payload,
  }) async {
    final now = DateTime.now();
    final data = <String, dynamic>{
      'flowTitle': flowTitle,
      'status': 'pending',
      'createdAt': Timestamp.fromDate(now),
      if (basePriceTry != null) 'basePriceTry': basePriceTry,
      'userName': AppStore.userName,
      'userPhone': AppStore.phone,
      'paymentMethod': AppStore.paymentLabel(),
      if (payload != null) 'payload': payload,
    };

    final ref = await _db.collection('requests').add(data);
    return ref.id;
  }
}

/// =======================
/// HOME
/// =======================

enum ServiceType { yolculuk, cekici, nakliye, lastik }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  GoogleMapController? _mapController;

  LatLng? _pendingMoveTarget;
  bool _movedToUserOnce = false;

  static const LatLng _fallback = LatLng(41.015137, 28.979530); // İstanbul

  @override
  void initState() {
    super.initState();
    _prepareMyLocationTarget();
  }

  Future<void> _prepareMyLocationTarget() async {
    if (_movedToUserOnce) return;

    try {
      // Permission is requested by LocationPermissionGate.
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _pendingMoveTarget = LatLng(pos.latitude, pos.longitude);

      // If controller already exists, move now.
      if (_mapController != null) {
        await _moveCameraToTarget(_pendingMoveTarget!);
      }
    } catch (_) {
      // Ignore: we will stay at fallback location.
    }
  }

  Future<void> _moveCameraToTarget(LatLng target) async {
    if (_movedToUserOnce) return;
    try {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(target, 15),
      );
      _movedToUserOnce = true;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _AppDrawer(),
      body: Column(
        children: [
          // TOP APP BAR (mevcut UI korunur)
          SafeArea(
            bottom: false,
            child: Container(
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: TakNakApp.taknakOrange,
              child: Row(
                children: [
                  Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.menu, color: Colors.white),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    "TAKNAK",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // HARITA (üstte)
          SizedBox(
            height: 280,
            width: double.infinity,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GoogleMap(
                    initialCameraPosition: const CameraPosition(
                      target: _fallback,
                      zoom: 12,
                    ),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false, // kendi butonumuzu koyacağız
                    compassEnabled: true,
                    zoomControlsEnabled: false,
                    onMapCreated: (c) async {
                      _mapController = c;
                      if (_pendingMoveTarget != null) {
                        await _moveCameraToTarget(_pendingMoveTarget!);
                      }
                    },
                  ),
                ),

                // "Konumuma git" butonu (harita üstünde)
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: FloatingActionButton(
                    heroTag: 'home_locate_btn',
                    mini: true,
                    backgroundColor: Colors.white,
                    onPressed: () async {
                      await _prepareMyLocationTarget();
                      if (_pendingMoveTarget != null && _mapController != null) {
                        await _mapController!.animateCamera(
                          CameraUpdate.newLatLngZoom(_pendingMoveTarget!, 15),
                        );
                      }
                    },
                    child: const Icon(Icons.my_location, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),

          // KARTLAR (altta) — mevcut UI bozulmadan
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _BottomPanel(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer();

  void _go(BuildContext context, Widget page) async {
    // Drawer'ı kapatıp yeni sayfaya geç.
    Navigator.of(context).pop();
    // Navigator işleminin tamamlanmasını bekle
    await Future.microtask(() {});
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  void _showLanguageSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      Widget tile(String label, String code) {
        return ListTile(
          leading: const Icon(Icons.language),
          title: Text(label),
          onTap: () {
            TakNakApp.setLocale(ctx, Locale(code));
            Navigator.pop(ctx);
          },
        );
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text('Dil Seç', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            tile('Türkçe', 'tr'),
            tile('English', 'en'),
            tile('العربية', 'ar'),
            tile('Deutsch', 'de'),
            tile('Русский', 'ru'),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}


  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: TakNakApp.taknakOrange,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.directions_car_filled,
                        color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'TAKNAK',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Menu
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _DrawerItem(
                    icon: Icons.person_outline,
                    title: 'Profil',
                    onTap: () => _go(context, const ProfilePage()),
                  ),
                  _DrawerItem(
                    icon: Icons.history,
                    title: 'Geçmiş',
                    onTap: () => _go(context, const HistoryPage()),
                  ),
                  _DrawerItem(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Ödemeler',
                    onTap: () => _go(context, const PaymentMethodsPage()),
                  ),
                  _DrawerItem(
                    icon: Icons.smart_toy_outlined,
                    title: 'TakNak AI Analiz',
                    onTap: () => _go(context, TakNakAnalizEkrani()),
                  ),
                                    _DrawerItem(
                    icon: Icons.language_outlined,
                    title: 'Dil',
                    onTap: () => _showLanguageSheet(context),
                  ),
_DrawerItem(
                    icon: Icons.settings_outlined,
                    title: 'Ayarlar',
                    onTap: () => _go(context, const AccountPage()),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Destek (MVP)')),
                    );
                  },
                  icon: const Icon(Icons.support_agent_outlined),
                  label: const Text('Destek'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: onTap,
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            spreadRadius: 2,
            offset: Offset(0, -2),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // search bar
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              // İleride "Nereye / Ne lazım?" arama ekranı yapılacak.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Arama yakında.')),
              );
            },
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE7E7E7)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search, color: Color(0xFF7A7A7A)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Nereye / Ne lazım?',
                      style: TextStyle(
                        fontSize: 15,
                        color: Color(0xFF7A7A7A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Color(0xFF9A9A9A)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // grid
          Row(
            children: [
              Expanded(
                child: _ServiceCard(
                  icon: Icons.directions_car_filled,
                  title: 'Yolculuk',
                  subtitle: 'Paylaşımlı / özel',
                  tag: 'Hızlı',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                      const ServicePage(type: ServiceType.yolculuk),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ServiceCard(
                  icon: Icons.local_shipping_outlined,
                  title: 'Çekici',
                  subtitle: 'Yolda kaldın mı?',
                  tag: '7/24',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                      const ServicePage(type: ServiceType.cekici),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ServiceCard(
                  icon: Icons.inventory_2_outlined,
                  title: 'Nakliye',
                  subtitle: 'Panelvan / Kamyonet',
                  tag: 'Uygun',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                      const ServicePage(type: ServiceType.nakliye),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ServiceCard(
                  icon: Icons.tire_repair_outlined,
                  title: 'Lastik',
                  subtitle: 'Değişim / servis',
                  tag: 'Acil',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                      const ServicePage(type: ServiceType.lastik),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // bottom actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    side: const BorderSide(color: Color(0xFFE1E1E1)),
                  ),
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const _HelpQuickSheet(),
                  ),
                  icon: const Icon(Icons.flash_on_rounded),
                  label: const Text(
                    'Tek dokunuşla en yakın yardım',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: TakNakApp.taknakOrange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const _HelpQuickSheet(),
                  ),
                  icon: const Icon(Icons.flash_on_rounded),
                  label: const Text(
                    'Yardım',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HelpQuickSheet extends StatelessWidget {
  const _HelpQuickSheet();

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String title, String sub, VoidCallback onTap) {
      return ListTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(sub),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('Yardım',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 6),
            item(Icons.directions_car, 'Yolculuk çağır',
                'En yakın sürücüyle eşleş', () async {
                  Navigator.pop(context);
                  await Future.microtask(() {});
                  Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const YolculukFormPage()));
                }),
            item(Icons.local_shipping, 'Çekici çağır', 'En yakın çekici/servis',
                    () async {
                  Navigator.pop(context);
                  await Future.microtask(() {});
                  Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const CekiciFormPage()));
                }),
            item(Icons.tire_repair, 'Lastik yardımı', 'Mobil lastik servisi',
                    () async {
                  Navigator.pop(context);
                  await Future.microtask(() {});
                  Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const LastikFormPage()));
                }),
            item(Icons.call, 'Acil iletişim', '112 / 155 / 156', () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Acil arama – gerçek arama sonra.')),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class ServicePage extends StatelessWidget {
  final ServiceType type;
  const ServicePage({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case ServiceType.yolculuk:
        return const YolculukFormPage();
      case ServiceType.cekici:
        return const CekiciFormPage();
      case ServiceType.nakliye:
        return const NakliyeFormPage();
      case ServiceType.lastik:
        return const LastikFormPage();
    }
  }
}

/// =======================
/// ORTAK: ADRES SEÇİMİ
/// =======================

class PickedLocation {
  final LatLng latLng;
  final String address;
  const PickedLocation({required this.latLng, required this.address});
}

/// Map-based address picker (tap the map -> returns a readable address via reverse-geocode).
class MapPickPage extends StatefulWidget {
  final String title;
  final IconData? icon;
  const MapPickPage({super.key, required this.title, this.icon});

  @override
  State<MapPickPage> createState() => _MapPickPageState();
}

class _MapPickPageState extends State<MapPickPage> {
  GoogleMapController? _controller;
  LatLng _center = const LatLng(41.015137, 28.979530); // Istanbul
  LatLng? _picked;

  @override
  void initState() {
    super.initState();
    _tryCenterOnUser();
  }

  Future<void> _tryCenterOnUser() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );

      _center = LatLng(pos.latitude, pos.longitude);
      if (mounted) setState(() {});
      await _controller?.animateCamera(CameraUpdate.newLatLngZoom(_center, 16));
    } catch (_) {}
  }

  Future<String> _reverseGeocode(LatLng p) async {
    try {
      final placemarks =
      await placemarkFromCoordinates(p.latitude, p.longitude);
      if (placemarks.isEmpty)
        return "${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}";
      final pm = placemarks.first;
      final parts = <String>[
        if ((pm.street ?? '').trim().isNotEmpty) pm.street!.trim(),
        if ((pm.subLocality ?? '').trim().isNotEmpty) pm.subLocality!.trim(),
        if ((pm.locality ?? '').trim().isNotEmpty) pm.locality!.trim(),
        if ((pm.administrativeArea ?? '').trim().isNotEmpty)
          pm.administrativeArea!.trim(),
      ];
      return parts.isEmpty
          ? "${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}"
          : parts.join(", ");
    } catch (_) {
      return "${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}";
    }
  }

  @override
  Widget build(BuildContext context) {
    final marker = _picked == null
        ? const <Marker>{}
        : {
      Marker(markerId: const MarkerId("picked"), position: _picked!),
    };

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: 13),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: marker,
            onMapCreated: (c) => _controller = c,
            onTap: (p) => setState(() => _picked = p),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: ElevatedButton(
              onPressed: () async {
                if (_picked == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Haritaya dokunup bir yer seç.")),
                  );
                  return;
                }
                final addr = await _reverseGeocode(_picked!);
                if (!context.mounted) return;
                Navigator.pop(
                    context, PickedLocation(latLng: _picked!, address: addr));
              },
              child: const Text("Seç"),
            ),
          ),
        ],
      ),
    );
  }
}

const String kGoogleApiKey = 'AIzaSyD4oMeOGCFYcg90FtPvJXKS_v22mq9x7j0';

/// =========================
/// ADRES ARAMA (Nereden/Nereye)
/// =========================
///
/// Bu sayfa 2 farklı yöntem sunar:
/// 1) **Native Google Places Autocomplete (Android)**: En sağlıklısı. Yazınca öneriler çıkar.
/// 2) **Fallback (geocoding paketi)**: Eğer native taraf hazır değilse yine çalışsın diye.
///
/// Not: Native Autocomplete için Android tarafında MethodChannel "taknak/native_places"
/// ve "openAutocomplete" method'u uygulanmış olmalı (MainActivity.kt).

/// =======================
/// YOLCULUK
/// =======================

enum TripMode { paylasimli, ozel, havalimani, rezervasyon }

enum VehicleType { motor, binek, panelvan, vip }

class YolculukFormPage extends StatefulWidget {
  const YolculukFormPage({super.key});

  @override
  State<YolculukFormPage> createState() => _YolculukFormPageState();
}

class _YolculukFormPageState extends State<YolculukFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  TripMode _mode = TripMode.paylasimli;
  VehicleType _vehicle = VehicleType.binek;

  int _people = 1;
  bool _pet = false;

  DateTime? _date;
  TimeOfDay? _time;

  String _fromAddress = '';
  String _toAddress = '';

  // ✅ Mini harita marker'ları için koordinatlar
  LatLng? _fromLatLng;
  LatLng? _toLatLng;

  /// Beklenen format:
  /// "Adres satırı\nlat,lng"
  LatLng? _parseLatLngFromAddressString(String s) {
    final parts = s.split('\n');
    if (parts.length < 2) return null;

    final last = parts.last.trim(); // "lat,lng"
    final ll = last.split(',');
    if (ll.length != 2) return null;

    final lat = double.tryParse(ll[0].trim());
    final lng = double.tryParse(ll[1].trim());
    if (lat == null || lng == null) return null;

    return LatLng(lat, lng);
  }

  String _stripCoords(String s) {
    final parts = s.split('\n');
    return parts.isEmpty ? s : parts.first.trim();
  }

  final TextEditingController _flightCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _flightCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _isReservation => _mode == TripMode.rezervasyon;
  bool get _isAirport => _mode == TripMode.havalimani;

  String _modeLabel(TripMode m) {
    switch (m) {
      case TripMode.paylasimli:
        return 'Paylaşımlı';
      case TripMode.ozel:
        return 'Özel';
      case TripMode.havalimani:
        return 'Havalimanı';
      case TripMode.rezervasyon:
        return 'Rezervasyon';
    }
  }

  String _vehicleLabel(VehicleType v) {
    switch (v) {
      case VehicleType.motor:
        return 'Motor';
      case VehicleType.binek:
        return 'Binek';
      case VehicleType.panelvan:
        return 'Panelvan';
      case VehicleType.vip:
        return 'VIP';
    }
  }

  int _maxPeopleFor(VehicleType v) => v == VehicleType.motor ? 1 : 4;

  int _perKmFor(VehicleType v) {
    switch (v) {
      case VehicleType.binek:
        return 25;
      case VehicleType.panelvan:
        return 25;
      case VehicleType.vip:
        return 35;
      case VehicleType.motor:
        return 25;
    }
  }

  // Mesafe/rota henuz baglanmadiysa sabit bir deger kullanilir.
  double _fallbackKm() => 5.0;

  int _estimatePriceTry() {
    final km = _fallbackKm();
    final perKm = _perKmFor(_vehicle);
    final val = (km * perKm);
    if (val.isNaN || val.isInfinite) return 0;
    return val.round();
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: _date ?? now,
    );
    if (picked == null) return;
    setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final TimeOfDay initial = _time ?? TimeOfDay.now();
    final TimeOfDay? picked =
    await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() => _time = picked);
  }

  void _normalizePeople() {
    final max = _maxPeopleFor(_vehicle);
    if (_people > max) _people = max;
    if (_people < 1) _people = 1;
  }

  Future<void> _pickFrom() async {
    final res = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
          builder: (_) => const AddressSearchPage(title: 'Nereden')),
    );
    if (res == null) return;
    final ll = _parseLatLngFromAddressString(res);
    setState(() {
      _fromLatLng = ll;
      _fromAddress = _stripCoords(res);
    });
  }

  Future<void> _pickTo() async {
    final res = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
          builder: (_) => const AddressSearchPage(title: 'Nereye')),
    );
    if (res == null) return;
    final ll = _parseLatLngFromAddressString(res);
    setState(() {
      _toLatLng = ll;
      _toAddress = _stripCoords(res);
    });
  }

  void _submit() {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    if (_fromAddress.trim().isEmpty || _toAddress.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Lütfen “Nereden” ve “Nereye” adreslerini seç.')),
      );
      return;
    }

    if (_isReservation && (_date == null || _time == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rezervasyon için tarih + saat seç.')));
      return;
    }

    final price = _estimatePriceTry();

    final YolculukRequest req = YolculukRequest(
      fromAddress: _fromAddress,
      toAddress: _toAddress,
      mode: _modeLabel(_mode),
      vehicle: _vehicleLabel(_vehicle),
      people: _people,
      pet: _pet,
      estimatedTry: price,
      reservationDate: _isReservation ? _date : null,
      reservationTime: _isReservation ? _time : null,
      flightCode: _isAirport ? _flightCtrl.text.trim() : '',
      note: _noteCtrl.text.trim(),
      paymentMethod: AppStore.paymentLabel(),
    );

    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => YolculukSummaryPage(request: req)));
  }

  @override
  Widget build(BuildContext context) {
    _normalizePeople();
    final maxPeople = _maxPeopleFor(_vehicle);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: TakNakApp.taknakOrange,
        foregroundColor: Colors.white,
        title: const Text('Yolculuk',
            style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _SectionTitle(
                    icon: Icons.place_outlined,
                    title: 'Adres',
                    subtitle: 'Nereden → Nereye'),
                const SizedBox(height: 10),
                _AddressPickCard(
                  icon: Icons.my_location,
                  title: 'Nereden',
                  value: _fromAddress.isEmpty ? 'Adres seç' : _fromAddress,
                  onTap: _pickFrom,
                ),
                const SizedBox(height: 12),
                _AddressPickCard(
                  icon: Icons.location_on_outlined,
                  title: 'Nereye',
                  value: _toAddress.isEmpty ? 'Adres seç' : _toAddress,
                  onTap: _pickTo,
                ),
                const SizedBox(height: 10),
                _MiniMapCard(from: _fromLatLng, to: _toLatLng),
                const SizedBox(height: 10),
                const _InfoBox(
                  text:
                  'Adresleri seçtikçe mini haritada marker’lar görünür. “Yolculuğu Başlat” ile tam haritaya geçebilirsin.',
                ),
                const SizedBox(height: 18),

                const _SectionTitle(
                  icon: Icons.route_outlined,
                  title: 'Yolculuk tipi',
                  subtitle: 'Paylaşımlı / Özel / Havalimanı / Rezervasyon',
                ),
                const SizedBox(height: 10),
                _TwoRowChips<TripMode>(
                  itemsRow1: const <_ChipItem<TripMode>>[
                    _ChipItem('Paylaşımlı', TripMode.paylasimli),
                    _ChipItem('Özel', TripMode.ozel),
                  ],
                  itemsRow2: const <_ChipItem<TripMode>>[
                    _ChipItem('Havalimanı', TripMode.havalimani),
                    _ChipItem('Rezervasyon', TripMode.rezervasyon),
                  ],
                  value: _mode,
                  onChanged: (m) {
                    setState(() {
                      _mode = m;
                      if (!_isReservation) {
                        _date = null;
                        _time = null;
                      }
                      if (!_isAirport) _flightCtrl.clear();
                    });
                  },
                ),
                const SizedBox(height: 18),

                const _SectionTitle(
                  icon: Icons.directions_car,
                  title: 'Araç seçimi',
                  subtitle: 'Motor / Binek / Panelvan / VIP',
                ),
                const SizedBox(height: 10),
                _TwoRowChips<VehicleType>(
                  itemsRow1: const <_ChipItem<VehicleType>>[
                    _ChipItem('Motor', VehicleType.motor),
                    _ChipItem('Binek', VehicleType.binek),
                  ],
                  itemsRow2: const <_ChipItem<VehicleType>>[
                    _ChipItem('Panelvan', VehicleType.panelvan),
                    _ChipItem('VIP', VehicleType.vip),
                  ],
                  value: _vehicle,
                  onChanged: (v) => setState(() => _vehicle = v),
                ),
                const SizedBox(height: 18),

                const _SectionTitle(
                    icon: Icons.people_alt_outlined,
                    title: 'Kişi sayısı',
                    subtitle: 'Motor: 1 • Diğerleri: max 4'),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    _SmallButton(
                      icon: Icons.remove,
                      onPressed: () => setState(() {
                        if (_people > 1) _people--;
                      }),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE9E9E9)),
                        ),
                        child: Text('$_people kişi',
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _SmallButton(
                      icon: Icons.add,
                      onPressed: () => setState(() {
                        if (_people < maxPeople) _people++;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Seçili araç: ${_vehicleLabel(_vehicle)} • Maks: $maxPeople kişi',
                  style: const TextStyle(
                      color: Colors.black54, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 18),

                const _SectionTitle(
                    icon: Icons.pets_outlined,
                    title: 'Evcil hayvan',
                    subtitle: 'Evcil hayvanım var'),
                const SizedBox(height: 6),
                SwitchListTile(
                  value: _pet,
                  onChanged: (v) => setState(() => _pet = v),
                  activeColor: TakNakApp.taknakOrange,
                  title: const Text('Evcil hayvanım var'),
                  subtitle: const Text('Sürücü bilsin, hazırlıklı gelsin.'),
                ),
                const SizedBox(height: 12),

                // ✅ Km bölümü kaldırıldı
                _InfoBox(
                    text:
                    'Tahmini ücret: ${_estimatePriceTry()} ₺  (bu sadece referans)'),
                const SizedBox(height: 18),

                if (_isAirport) ...<Widget>[
                  const _SectionTitle(
                      icon: Icons.flight_takeoff,
                      title: 'Uçuş bilgisi',
                      subtitle: 'Opsiyonel'),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _flightCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Uçuş kodu (opsiyonel)',
                      hintText: 'Örn: TK1951',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                if (_isReservation) ...<Widget>[
                  const _SectionTitle(
                      icon: Icons.calendar_month,
                      title: 'Rezervasyon zamanı',
                      subtitle: 'Tarih + saat seç'),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16))),
                          onPressed: _pickDate,
                          icon: const Icon(Icons.date_range),
                          label: Text(
                            _date == null
                                ? 'Tarih seç'
                                : '${_date!.day.toString().padLeft(2, '0')}.${_date!.month.toString().padLeft(2, '0')}.${_date!.year}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16))),
                          onPressed: _pickTime,
                          icon: const Icon(Icons.access_time),
                          label: Text(
                              _time == null
                                  ? 'Saat seç'
                                  : _time!.format(context),
                              style:
                              const TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    (_date == null || _time == null)
                        ? 'Rezervasyon için tarih + saat seçmelisin.'
                        : 'Rezervasyon zamanı tamam.',
                    style: TextStyle(
                      color: (_date == null || _time == null)
                          ? Colors.red
                          : Colors.black54,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                const _SectionTitle(
                    icon: Icons.payments_outlined,
                    title: 'Ödeme yöntemi',
                    subtitle: 'Seçim'),
                const SizedBox(height: 10),
                _SummaryCard(
                    title: 'Seçili yöntem',
                    value: AppStore.paymentLabel(),
                    icon: Icons.credit_card),
                const SizedBox(height: 10),
                const _InfoBox(
                    text: 'Ödemeyi şimdi almıyoruz. Bu sadece MVP ekranı.'),

                const SizedBox(height: 18),
                const _SectionTitle(
                    icon: Icons.edit_note_outlined,
                    title: 'Not',
                    subtitle: 'Opsiyonel'),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _noteCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      hintText: 'Örn: Bebek var, bagaj var…',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                _InfoBox(
                    text:
                    'Devam’a basınca özet ekranında bilgileri kontrol edeceğiz.'),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: TakNakApp.taknakOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _submit,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Devam',
                  style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      ),
    );
  }
}

class YolculukRequest {
  final String fromAddress;
  final String toAddress;

  final String mode;
  final String vehicle;
  final int people;
  final bool pet;

  final int estimatedTry;

  final DateTime? reservationDate;
  final TimeOfDay? reservationTime;

  final String flightCode;
  final String note;

  final String paymentMethod;

  const YolculukRequest({
    required this.fromAddress,
    required this.toAddress,
    required this.mode,
    required this.vehicle,
    required this.people,
    required this.pet,
    required this.estimatedTry,
    required this.reservationDate,
    required this.reservationTime,
    required this.flightCode,
    required this.note,
    required this.paymentMethod,
  });
}

class YolculukSummaryPage extends StatelessWidget {
  final YolculukRequest request;
  const YolculukSummaryPage({super.key, required this.request});

  String _dateText() {
    final d = request.reservationDate;
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  String _timeText(BuildContext context) {
    final t = request.reservationTime;
    if (t == null) return '—';
    return t.format(context);
  }

  @override
  Widget build(BuildContext context) {
    final bool isReservation = request.mode == 'Rezervasyon';
    final bool isAirport = request.mode == 'Havalimanı';

    return _SummaryScaffold(
      title: 'Özet & Onay',
      flowTitle: 'Yolculuk',
      basePriceTry: request.estimatedTry <= 0 ? null : request.estimatedTry,
      payload: <String, dynamic>{
        'fromAddress': request.fromAddress,
        'toAddress': request.toAddress,
        'mode': request.mode,
        'vehicle': request.vehicle,
        'people': request.people,
        'pet': request.pet,
        'estimatedTry': request.estimatedTry,
        'flightCode': request.flightCode,
        'note': request.note,
        'paymentMethod': request.paymentMethod,
      },
      cards: <Widget>[
        _SummaryCard(
            title: 'Nereden',
            value: request.fromAddress,
            icon: Icons.my_location),
        _SummaryCard(
            title: 'Nereye',
            value: request.toAddress,
            icon: Icons.location_on_outlined),
        _SummaryCard(
            title: 'Yolculuk tipi',
            value: request.mode,
            icon: Icons.route_outlined),
        _SummaryCard(
            title: 'Araç', value: request.vehicle, icon: Icons.directions_car),
        _SummaryCard(
            title: 'Kişi',
            value: '${request.people} kişi',
            icon: Icons.people_alt_outlined),
        _SummaryCard(
            title: 'Evcil hayvan',
            value: request.pet ? 'Var' : 'Yok',
            icon: Icons.pets_outlined),
        _SummaryCard(
            title: 'Ödeme yöntemi',
            value: request.paymentMethod,
            icon: Icons.credit_card),
        _SummaryCard(
            title: 'Tahmini ücret',
            value: '${request.estimatedTry} ₺ (referans)',
            icon: Icons.payments_outlined),
        if (isAirport)
          _SummaryCard(
            title: 'Uçuş kodu',
            value: request.flightCode.isEmpty ? '—' : request.flightCode,
            icon: Icons.flight_takeoff,
          ),
        if (isReservation) ...<Widget>[
          _SummaryCard(
              title: 'Tarih', value: _dateText(), icon: Icons.date_range),
          _SummaryCard(
              title: 'Saat',
              value: _timeText(context),
              icon: Icons.access_time),
        ],
        _SummaryCard(
            title: 'Not',
            value: request.note.isEmpty ? '—' : request.note,
            icon: Icons.edit_note_outlined),
        const _InfoBox(
          text:
          'Not: Bu fiyat tahminidir. Yolculuk başlamadan önce sabitlenir .',
        ),
      ],
    );
  }
}

/// =======================
/// ÇEKİCİ
/// =======================

class CekiciFormPage extends StatefulWidget {
  const CekiciFormPage({super.key});

  @override
  State<CekiciFormPage> createState() => _CekiciFormPageState();
}

class _CekiciFormPageState extends State<CekiciFormPage> {
  LatLng? _toLatLng;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  String _whereAddress = '';
  String _toAddress = '';

  final List<String> _aracTurleri = <String>[
    'Binek',
    'SUV / Crossover',
    'Hafif ticari (Panelvan)',
    'Motosiklet',
    'Diğer',
  ];

  final List<String> _sorunTurleri = <String>[
    'Çekici (hareket etmiyor)',
    'Kaza / hasar',
    'Akü bitti',
    'Yakıt bitti',
    'Hararet / motor arızası',
    'Diğer',
  ];

  final List<String> _aciliyet = <String>[
    'Hemen',
    '30 dk içinde',
    '1 saat içinde',
    'Acil değil',
  ];

  String? _aracTuru;
  String? _sorunTuru;
  String _aciliyetSecim = 'Hemen';
  final TextEditingController _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickWhere() async {
    final res = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
          builder: (_) => const AddressSearchPage(title: 'Nerede (Konum)')),
    );
    if (res == null) return;
    setState(() => _whereAddress = res);
  }

  Future<void> _pickTo() async {
    final res = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
          builder: (_) => const AddressSearchPage(title: 'Nereye (Opsiyonel)')),
    );
    if (res == null) return;
    final ll = _parseLatLngFromAddressString(res);
    setState(() {
      _toLatLng = ll;
      _toAddress = _stripCoords(res);
    });
  }

  void _submit() {
    final bool ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    if (_whereAddress.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Çekici için “Nerede” adresi seçmelisin.')));
      return;
    }

    final CekiciRequest req = CekiciRequest(
      whereAddress: _whereAddress,
      toAddress: _toAddress,
      aracTuru: _aracTuru ?? '',
      sorunTuru: _sorunTuru ?? '',
      aciliyet: _aciliyetSecim,
      note: _noteCtrl.text.trim(),
      paymentMethod: AppStore.paymentLabel(),
    );

    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CekiciSummaryPage(request: req)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: TakNakApp.taknakOrange,
        foregroundColor: Colors.white,
        title:
        const Text('Çekici', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _SectionTitle(
                    icon: Icons.place_outlined,
                    title: 'Adres',
                    subtitle: 'Nerede zorunlu • Nereye opsiyonel'),
                const SizedBox(height: 10),
                _AddressPickCard(
                  icon: Icons.my_location,
                  title: 'Nerede (Konum)',
                  value: _whereAddress.isEmpty ? 'Adres seç' : _whereAddress,
                  onTap: _pickWhere,
                ),
                const SizedBox(height: 12),
                _AddressPickCard(
                  icon: Icons.location_on_outlined,
                  title: 'Nereye (Opsiyonel)',
                  value: _toAddress.isEmpty ? 'Adres seç' : _toAddress,
                  onTap: _pickTo,
                ),
                const SizedBox(height: 10),
                const _InfoBox(
                    text:
                    'Çekici için en önemli bilgi: bulunduğun konum. İstersen çekilecek yeri de girersin.'),
                const SizedBox(height: 18),
                const _SectionTitle(
                    icon: Icons.directions_car_outlined,
                    title: 'Araç türü',
                    subtitle: 'Hangi araç için çekici?'),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _aracTuru,
                  items: _aracTurleri
                      .map((e) =>
                      DropdownMenuItem<String>(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setState(() => _aracTuru = v),
                  validator: (v) =>
                  (v == null || v.isEmpty) ? 'Araç türü seç' : null,
                  decoration: const InputDecoration(
                      labelText: 'Araç türü', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 18),
                const _SectionTitle(
                    icon: Icons.build_circle_outlined,
                    title: 'Sorun tipi',
                    subtitle: 'Ne oldu?'),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _sorunTuru,
                  items: _sorunTurleri
                      .map((e) =>
                      DropdownMenuItem<String>(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setState(() => _sorunTuru = v),
                  validator: (v) =>
                  (v == null || v.isEmpty) ? 'Sorun tipi seç' : null,
                  decoration: const InputDecoration(
                      labelText: 'Sorun tipi', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 18),
                const _SectionTitle(
                    icon: Icons.timer_outlined,
                    title: 'Aciliyet',
                    subtitle: 'Ne kadar acil?'),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _aciliyetSecim,
                  items: _aciliyet
                      .map((e) =>
                      DropdownMenuItem<String>(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _aciliyetSecim = v ?? 'Hemen'),
                  decoration: const InputDecoration(
                      labelText: 'Aciliyet', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 18),
                const _SectionTitle(
                    icon: Icons.payments_outlined,
                    title: 'Ödeme yöntemi',
                    subtitle: 'Seçim'),
                const SizedBox(height: 10),
                _SummaryCard(
                    title: 'Seçili yöntem',
                    value: AppStore.paymentLabel(),
                    icon: Icons.credit_card),
                const SizedBox(height: 18),
                const _SectionTitle(
                    icon: Icons.edit_note_outlined,
                    title: 'Not',
                    subtitle: 'Opsiyonel'),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _noteCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Örn: Araç çalışıyor ama yürümüyor…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                _InfoBox(
                    text:
                    'Devam’a basınca özet ekranında bilgileri kontrol edeceğiz.'),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: TakNakApp.taknakOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _submit,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Devam',
                  style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      ),
    );
  }
}

class CekiciRequest {
  final String whereAddress;
  final String toAddress;
  final String aracTuru;
  final String sorunTuru;
  final String aciliyet;
  final String note;
  final String paymentMethod;

  const CekiciRequest({
    required this.whereAddress,
    required this.toAddress,
    required this.aracTuru,
    required this.sorunTuru,
    required this.aciliyet,
    required this.note,
    required this.paymentMethod,
  });
}

class CekiciSummaryPage extends StatelessWidget {
  final CekiciRequest request;
  const CekiciSummaryPage({super.key, required this.request});

  @override
  Widget build(BuildContext context) {
    return _SummaryScaffold(
      title: 'Özet & Onay',
      flowTitle: 'Çekici',
      payload: <String, dynamic>{
        'whereAddress': request.whereAddress,
        'toAddress': request.toAddress,
        'aracTuru': request.aracTuru,
        'sorunTuru': request.sorunTuru,
        'aciliyet': request.aciliyet,
        'note': request.note,
        'paymentMethod': request.paymentMethod,
      },
      cards: <Widget>[
        _SummaryCard(
            title: 'Nerede',
            value: request.whereAddress,
            icon: Icons.my_location),
        _SummaryCard(
            title: 'Nereye',
            value: request.toAddress.isEmpty ? '—' : request.toAddress,
            icon: Icons.location_on_outlined),
        _SummaryCard(
            title: 'Araç türü',
            value: request.aracTuru,
            icon: Icons.directions_car_outlined),
        _SummaryCard(
            title: 'Sorun tipi',
            value: request.sorunTuru,
            icon: Icons.build_circle_outlined),
        _SummaryCard(
            title: 'Aciliyet',
            value: request.aciliyet,
            icon: Icons.timer_outlined),
        _SummaryCard(
            title: 'Ödeme yöntemi',
            value: request.paymentMethod,
            icon: Icons.credit_card),
        _SummaryCard(
            title: 'Not',
            value: request.note.isEmpty ? '—' : request.note,
            icon: Icons.edit_note_outlined),
      ],
    );
  }
}

/// =======================
/// NAKLİYE
/// =======================

enum NakliyeType { evdenEve, sebzeMeyve, kumas, diger }

class NakliyeFormPage extends StatefulWidget {
  const NakliyeFormPage({super.key});

  @override
  State<NakliyeFormPage> createState() => _NakliyeFormPageState();
}

class _NakliyeFormPageState extends State<NakliyeFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  String _fromAddress = '';
  String _toAddress = '';
  LatLng? _fromLatLng;
  LatLng? _toLatLng;

  NakliyeType _type = NakliyeType.evdenEve;

  final TextEditingController _aptTypeCtrl = TextEditingController(text: '2+1');
  final TextEditingController _fromFloorCtrl = TextEditingController(text: '1');
  final TextEditingController _toFloorCtrl = TextEditingController(text: '3');
  bool _elevator = true;

  final TextEditingController _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _aptTypeCtrl.dispose();
    _fromFloorCtrl.dispose();
    _toFloorCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFrom() async {
    final res = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
          builder: (_) =>
          const AddressSearchPage(title: 'Nereden (Yük alınacak)')),
    );
    if (res == null) return;
    final ll = _parseLatLngFromAddressString(res);
    setState(() {
      _fromLatLng = ll;
      _fromAddress = _stripCoords(res);
    });
  }

  Future<void> _pickTo() async {
    final res = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
          builder: (_) => const AddressSearchPage(title: 'Nereye (Teslim)')),
    );
    if (res == null) return;
    final ll = _parseLatLngFromAddressString(res);
    setState(() {
      _toLatLng = ll;
      _toAddress = _stripCoords(res);
    });
  }

  String _typeLabel(NakliyeType t) {
    switch (t) {
      case NakliyeType.evdenEve:
        return 'Evden eve';
      case NakliyeType.sebzeMeyve:
        return 'Sebze-meyve';
      case NakliyeType.kumas:
        return 'Kumaş';
      case NakliyeType.diger:
        return 'Diğer';
    }
  }

  bool get _isEvdenEve => _type == NakliyeType.evdenEve;

  void _submit() {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    if (_fromAddress.trim().isEmpty || _toAddress.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Nakliye için “Nereden” ve “Nereye” adreslerini seçmelisin.')),
      );
      return;
    }

    final NakliyeRequest req = NakliyeRequest(
      fromAddress: _fromAddress,
      toAddress: _toAddress,
      type: _typeLabel(_type),
      aptType: _isEvdenEve ? _aptTypeCtrl.text.trim() : '—',
      fromFloor: _isEvdenEve ? _fromFloorCtrl.text.trim() : '—',
      toFloor: _isEvdenEve ? _toFloorCtrl.text.trim() : '—',
      elevator: _isEvdenEve ? _elevator : null,
      note: _noteCtrl.text.trim(),
      paymentMethod: AppStore.paymentLabel(),
    );

    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => NakliyeSummaryPage(request: req)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: TakNakApp.taknakOrange,
        foregroundColor: Colors.white,
        title: const Text('Nakliye',
            style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _SectionTitle(
                    icon: Icons.place_outlined,
                    title: 'Adres',
                    subtitle: 'Nereden → Nereye'),
                const SizedBox(height: 10),
                _AddressPickCard(
                  icon: Icons.my_location,
                  title: 'Nereden (Yük alınacak)',
                  value: _fromAddress.isEmpty ? 'Adres seç' : _fromAddress,
                  onTap: _pickFrom,
                ),
                const SizedBox(height: 12),
                _AddressPickCard(
                  icon: Icons.location_on_outlined,
                  title: 'Nereye (Teslim)',
                  value: _toAddress.isEmpty ? 'Adres seç' : _toAddress,
                  onTap: _pickTo,
                ),
                const SizedBox(height: 10),
                const _InfoBox(
                    text:
                    'Nakliye “teklif usulü”. Adresler doğru olursa teklif daha net gelir.'),
                const SizedBox(height: 18),
                const _SectionTitle(
                    icon: Icons.local_shipping_outlined,
                    title: 'Nakliyat türü',
                    subtitle: 'Teklif usulü: fiyatı ustalar verir.'),
                const SizedBox(height: 10),
                _TwoRowChips<NakliyeType>(
                  itemsRow1: const <_ChipItem<NakliyeType>>[
                    _ChipItem('Evden eve', NakliyeType.evdenEve),
                    _ChipItem('Sebze-meyve', NakliyeType.sebzeMeyve),
                  ],
                  itemsRow2: const <_ChipItem<NakliyeType>>[
                    _ChipItem('Kumaş', NakliyeType.kumas),
                    _ChipItem('Diğer', NakliyeType.diger),
                  ],
                  value: _type,
                  onChanged: (v) => setState(() => _type = v),
                ),
                const SizedBox(height: 18),
                if (_isEvdenEve) ...<Widget>[
                  const _SectionTitle(
                      icon: Icons.apartment_outlined,
                      title: 'Evden eve detayları',
                      subtitle: 'Kat, daire tipi, asansör bilgisi'),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _aptTypeCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Daire tipi (örn: 2+1)',
                        border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Daire tipini gir'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextFormField(
                          controller: _fromFloorCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Çıkış katı',
                              border: OutlineInputBorder()),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Kat gir'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _toFloorCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Varış katı',
                              border: OutlineInputBorder()),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Kat gir'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    value: _elevator,
                    onChanged: (v) => setState(() => _elevator = v),
                    title: const Text('Asansör var'),
                    subtitle: const Text('Yoksa taşıma süresi uzayabilir.'),
                    activeColor: TakNakApp.taknakOrange,
                  ),
                  const SizedBox(height: 10),
                ],
                const _SectionTitle(
                    icon: Icons.payments_outlined,
                    title: 'Ödeme yöntemi',
                    subtitle: 'Seçim'),
                const SizedBox(height: 10),
                _SummaryCard(
                    title: 'Seçili yöntem',
                    value: AppStore.paymentLabel(),
                    icon: Icons.credit_card),
                const SizedBox(height: 18),
                const _SectionTitle(
                    icon: Icons.edit_note_outlined,
                    title: 'Not',
                    subtitle: 'Opsiyonel'),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _noteCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      hintText: 'Örn: 3 koli + 1 çamaşır makinesi…',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                _InfoBox(
                    text:
                    'Devam’a basınca özet ekranı → sonra 3-4 teklif göreceksin.'),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: TakNakApp.taknakOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _submit,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Devam',
                  style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      ),
    );
  }
}

class NakliyeRequest {
  final String fromAddress;
  final String toAddress;

  final String type;
  final String aptType;
  final String fromFloor;
  final String toFloor;
  final bool? elevator;
  final String note;

  final String paymentMethod;

  const NakliyeRequest({
    required this.fromAddress,
    required this.toAddress,
    required this.type,
    required this.aptType,
    required this.fromFloor,
    required this.toFloor,
    required this.elevator,
    required this.note,
    required this.paymentMethod,
  });
}

class NakliyeSummaryPage extends StatelessWidget {
  final NakliyeRequest request;
  const NakliyeSummaryPage({super.key, required this.request});

  @override
  Widget build(BuildContext context) {
    return _SummaryScaffold(
      title: 'Özet & Onay',
      flowTitle: 'Nakliye',
      payload: <String, dynamic>{
        'fromAddress': request.fromAddress,
        'toAddress': request.toAddress,
        'type': request.type,
        'aptType': request.aptType,
        'fromFloor': request.fromFloor,
        'toFloor': request.toFloor,
        'elevator': request.elevator,
        'note': request.note,
        'paymentMethod': request.paymentMethod,
      },
      cards: <Widget>[
        _SummaryCard(
            title: 'Nereden',
            value: request.fromAddress,
            icon: Icons.my_location),
        _SummaryCard(
            title: 'Nereye',
            value: request.toAddress,
            icon: Icons.location_on_outlined),
        _SummaryCard(
            title: 'Nakliyat türü',
            value: request.type,
            icon: Icons.local_shipping_outlined),
        if (request.type == 'Evden eve') ...<Widget>[
          _SummaryCard(
              title: 'Daire tipi',
              value: request.aptType,
              icon: Icons.apartment_outlined),
          _SummaryCard(
              title: 'Çıkış katı',
              value: request.fromFloor,
              icon: Icons.layers_outlined),
          _SummaryCard(
              title: 'Varış katı',
              value: request.toFloor,
              icon: Icons.layers_outlined),
          _SummaryCard(
              title: 'Asansör',
              value: (request.elevator ?? false) ? 'Var' : 'Yok',
              icon: Icons.swap_vert),
        ],
        _SummaryCard(
            title: 'Ödeme yöntemi',
            value: request.paymentMethod,
            icon: Icons.credit_card),
        _SummaryCard(
            title: 'Not',
            value: request.note.isEmpty ? '—' : request.note,
            icon: Icons.edit_note_outlined),
      ],
    );
  }
}

/// =======================
/// LASTİK
/// =======================

enum TireCondition { sifir, ikinciEl }

class LastikFormPage extends StatefulWidget {
  const LastikFormPage({super.key});

  @override
  State<LastikFormPage> createState() => _LastikFormPageState();
}

class _LastikFormPageState extends State<LastikFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  String _whereAddress = '';

  String _tireSize = '205/55 R16';

  bool _wantSpare = false;
  TireCondition _spareCondition = TireCondition.sifir;

  bool _hasLugLockKey = true;
  final TextEditingController _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  String _condLabel(TireCondition c) =>
      c == TireCondition.sifir ? 'Sıfır' : '2. el';

  Future<void> _pickWhere() async {
    final res = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
          builder: (_) => const AddressSearchPage(title: 'Nerede (Konum)')),
    );
    if (res == null) return;
    setState(() => _whereAddress = res);
  }

  void _submit() {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    if (_whereAddress.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Lastik için “Nerede” adresi seçmelisin.')));
      return;
    }

    final LastikRequest req = LastikRequest(
      whereAddress: _whereAddress,
      tireSize: _tireSize,
      wantSpare: _wantSpare,
      spareCondition: _wantSpare ? _condLabel(_spareCondition) : '—',
      hasLugLockKey: _hasLugLockKey,
      note: _noteCtrl.text.trim(),
      paymentMethod: AppStore.paymentLabel(),
    );

    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => LastikSummaryPage(request: req)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: TakNakApp.taknakOrange,
        foregroundColor: Colors.white,
        title:
        const Text('Lastik', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _SectionTitle(
                    icon: Icons.place_outlined,
                    title: 'Adres',
                    subtitle: 'Servis buraya gelsin'),
                const SizedBox(height: 10),
                _AddressPickCard(
                  icon: Icons.my_location,
                  title: 'Nerede (Konum)',
                  value: _whereAddress.isEmpty ? 'Adres seç' : _whereAddress,
                  onTap: _pickWhere,
                ),
                const SizedBox(height: 10),
                const _InfoBox(
                    text:
                    'Lastik hizmeti: bulunduğun konuma mobil servis gelir.'),
                const SizedBox(height: 18),
                const _SectionTitle(
                    icon: Icons.straighten_outlined,
                    title: 'Lastik ebatı',
                    subtitle: 'Yolcu lastik ebatı seç'),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _tireSize,
                  items: const <String>[
                    '175/65 R14',
                    '185/65 R15',
                    '195/65 R15',
                    '205/55 R16',
                    '215/55 R17',
                    '225/45 R17',
                    '235/55 R18',
                  ]
                      .map((e) =>
                      DropdownMenuItem<String>(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setState(() => _tireSize = v ?? _tireSize),
                  decoration: const InputDecoration(
                      labelText: 'Ebat', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 18),
                const _SectionTitle(
                    icon: Icons.add_circle_outline,
                    title: 'Ek / yedek lastik',
                    subtitle: 'İstersen biz temin edelim (teklif usulü)'),
                const SizedBox(height: 6),
                SwitchListTile(
                  value: _wantSpare,
                  onChanged: (v) => setState(() => _wantSpare = v),
                  title: const Text('Ek/yedek lastik istiyorum'),
                  subtitle: const Text('Fiyatı ustalar teklif eder.'),
                  activeColor: TakNakApp.taknakOrange,
                ),
                if (_wantSpare) ...<Widget>[
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _ChipButton(
                          label: 'Sıfır',
                          selected: _spareCondition == TireCondition.sifir,
                          onTap: () => setState(
                                  () => _spareCondition = TireCondition.sifir),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ChipButton(
                          label: '2. el',
                          selected: _spareCondition == TireCondition.ikinciEl,
                          onTap: () => setState(
                                  () => _spareCondition = TireCondition.ikinciEl),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                const _SectionTitle(
                    icon: Icons.key_outlined,
                    title: 'Bijon şifresi',
                    subtitle: 'Bijon şifresi / kilit anahtarı yanında mı?'),
                const SizedBox(height: 6),
                SwitchListTile(
                  value: _hasLugLockKey,
                  onChanged: (v) => setState(() => _hasLugLockKey = v),
                  title: const Text('Bijon şifresi yanımda'),
                  subtitle: const Text('Yoksa işlem uzayabilir.'),
                  activeColor: TakNakApp.taknakOrange,
                ),
                const SizedBox(height: 10),
                const _SectionTitle(
                    icon: Icons.payments_outlined,
                    title: 'Ödeme yöntemi',
                    subtitle: 'Seçim'),
                const SizedBox(height: 10),
                _SummaryCard(
                    title: 'Seçili yöntem',
                    value: AppStore.paymentLabel(),
                    icon: Icons.credit_card),
                const SizedBox(height: 18),
                const _SectionTitle(
                    icon: Icons.edit_note_outlined,
                    title: 'Not',
                    subtitle: 'Opsiyonel'),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _noteCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Örn: Stepne yok, lastik tamamen indi…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                _InfoBox(
                    text: 'Devam → Özet → Onay → 3-4 teklif arasından seç.'),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: TakNakApp.taknakOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _submit,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Devam',
                  style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      ),
    );
  }
}

class LastikRequest {
  final String whereAddress;

  final String tireSize;
  final bool wantSpare;
  final String spareCondition;
  final bool hasLugLockKey;
  final String note;

  final String paymentMethod;

  const LastikRequest({
    required this.whereAddress,
    required this.tireSize,
    required this.wantSpare,
    required this.spareCondition,
    required this.hasLugLockKey,
    required this.note,
    required this.paymentMethod,
  });
}

class LastikSummaryPage extends StatelessWidget {
  final LastikRequest request;
  const LastikSummaryPage({super.key, required this.request});

  @override
  Widget build(BuildContext context) {
    return _SummaryScaffold(
      title: 'Özet & Onay',
      flowTitle: 'Lastik',
      payload: <String, dynamic>{
        'whereAddress': request.whereAddress,
        'tireSize': request.tireSize,
        'wantSpare': request.wantSpare,
        'spareCondition': request.spareCondition,
        'hasLugLockKey': request.hasLugLockKey,
        'note': request.note,
        'paymentMethod': request.paymentMethod,
      },
      cards: <Widget>[
        _SummaryCard(
            title: 'Nerede',
            value: request.whereAddress,
            icon: Icons.my_location),
        _SummaryCard(
            title: 'Ebat',
            value: request.tireSize,
            icon: Icons.straighten_outlined),
        _SummaryCard(
          title: 'Ek/yedek lastik',
          value:
          request.wantSpare ? 'Evet (${request.spareCondition})' : 'Hayır',
          icon: Icons.add_circle_outline,
        ),
        _SummaryCard(
            title: 'Bijon şifresi',
            value: request.hasLugLockKey ? 'Var' : 'Yok',
            icon: Icons.key_outlined),
        _SummaryCard(
            title: 'Ödeme yöntemi',
            value: request.paymentMethod,
            icon: Icons.credit_card),
        _SummaryCard(
            title: 'Not',
            value: request.note.isEmpty ? '—' : request.note,
            icon: Icons.edit_note_outlined),
      ],
    );
  }
}

/// =======================
/// ÖZET & ONAY — (YOLCULUK: tek eşleşme)
/// =======================

class _SummaryScaffold extends StatelessWidget {
  final String title;
  final IconData? icon;
  final List<Widget> cards;
  final String flowTitle;
  final int? basePriceTry;
  final Map<String, dynamic>? payload;

  const _SummaryScaffold({
    required this.title,
    required this.cards,
    required this.flowTitle,
    this.icon,
    this.basePriceTry,
    this.payload,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: TakNakApp.taknakOrange,
        foregroundColor: Colors.white,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: ListView.separated(
          itemCount: cards.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => cards[i],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _PrimaryButton(
                label: 'Onayla',
                icon: Icons.check_circle_outline,
                onPressed: () async {
                  // ✅ Firestore'a talep yaz
                  try {
                    await FirebaseService.createRequest(
                      flowTitle: flowTitle,
                      basePriceTry: basePriceTry,
                      payload: payload,
                    );
                  } catch (e) {
                    // Firebase sorunu olsa bile akış bozulmasın
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RequestCreatedPage(
                          flowTitle: flowTitle, basePriceTry: basePriceTry),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _SecondaryButton(
                  label: 'Geri dön / Düzenle',
                  onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
      ),
    );
  }
}

/// =======================
/// FLOW SCREENS
/// =======================

class RequestCreatedPage extends StatefulWidget {
  final String flowTitle;
  final int? basePriceTry;

  const RequestCreatedPage(
      {super.key, required this.flowTitle, this.basePriceTry});

  @override
  State<RequestCreatedPage> createState() => _RequestCreatedPageState();
}

class _RequestCreatedPageState extends State<RequestCreatedPage> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => SearchingPage(
              flowTitle: widget.flowTitle, basePriceTry: widget.basePriceTry),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return _CenterFlowScaffold(
      title: widget.flowTitle,
      icon: Icons.check_circle,
      bigText: 'Talep oluşturuldu',
      subText: 'Eşleştirme başlatılıyor…',
      showSpinner: true,
    );
  }
}

class SearchingPage extends StatefulWidget {
  final String flowTitle;
  final int? basePriceTry;

  const SearchingPage({super.key, required this.flowTitle, this.basePriceTry});

  @override
  State<SearchingPage> createState() => _SearchingPageState();
}

class _SearchingPageState extends State<SearchingPage> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1700), () {
      if (!mounted) return;

      // ✅ YOLCULUK: TEK EŞLEŞME
      if (widget.flowTitle == 'Yolculuk') {
        final OfferMock match = OfferMock.makeSingleMatch(widget.basePriceTry);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) =>
                SingleMatchPage(flowTitle: widget.flowTitle, match: match),
          ),
        );
        return;
      }

      // ✅ DİĞERLERİ: TEKLİF LİSTESİ
      final List<OfferMock> offers =
      OfferMock.makeMockOffers(widget.flowTitle, widget.basePriceTry);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              OffersListPage(flowTitle: widget.flowTitle, offers: offers),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return _CenterFlowScaffold(
      title: widget.flowTitle,
      icon: Icons.search,
      bigText: 'Aranıyor…',
      subText: widget.flowTitle == 'Yolculuk'
          ? 'En yakın sürücüyle eşleştiriyoruz.'
          : 'Yakınındaki servisler/ustalar taranıyor.',
      showSpinner: true,
    );
  }
}

/// =======================
/// YOLCULUK: TEK SÜRÜCÜ EŞLEŞME
/// =======================

class SingleMatchPage extends StatelessWidget {
  final String flowTitle;
  final OfferMock match;

  const SingleMatchPage(
      {super.key, required this.flowTitle, required this.match});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!AppStore.consentsOk) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LegalInfoPage()),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        backgroundColor: TakNakApp.taknakOrange,
        foregroundColor: Colors.white,
        title: const Text('Sürücü bulundu',
            style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
        child: Column(
          children: <Widget>[
            const _InfoBox(
                text:
                'En yakın sürücüyle eşleştin. İstersen iptal edebilir ya da takip ekranına geçebilirsin.'),
            const SizedBox(height: 12),
            _OfferDriverCard(offer: match),
            const SizedBox(height: 12),
            _SummaryCard(
                title: 'Tahmini varış',
                value: '${match.etaMin} dk',
                icon: Icons.timer_outlined),
            const SizedBox(height: 12),
            _SummaryCard(
                title: 'Tahmini ücret',
                value: '${match.priceTry} ₺ (referans)',
                icon: Icons.payments_outlined),
            const SizedBox(height: 12),
            _SummaryCard(
                title: 'Ödeme',
                value: AppStore.paymentLabel(),
                icon: Icons.credit_card),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _SecondaryButton(
                  label: 'İptal',
                  onPressed: () {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('İptal.')));
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PrimaryButton(
                  label: 'Takibe geç',
                  icon: Icons.navigation_outlined,
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                          builder: (_) => TrackingStepsPage(
                              flowTitle: flowTitle, offer: match)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// =======================
/// TEKLİF MODELLERİ (MOCK)
/// =======================

class OfferMock {
  final int priceTry;
  final int etaMin;
  final String providerName;
  final double rating;
  final int reviewCount;
  final String vehicleText;
  final String plateMasked;
  final bool isRecommended;
  final bool hasInvoice;
  final String paymentText;

  final bool canProvideNewTire;
  final bool canProvideUsedTire;

  const OfferMock({
    required this.priceTry,
    required this.etaMin,
    required this.providerName,
    required this.rating,
    required this.reviewCount,
    required this.vehicleText,
    required this.plateMasked,
    required this.isRecommended,
    required this.hasInvoice,
    required this.paymentText,
    required this.canProvideNewTire,
    required this.canProvideUsedTire,
  });

  // ✅ Yolculuk için tek sürücü
  static OfferMock makeSingleMatch(int? basePriceTry) {
    final int base =
    (basePriceTry == null || basePriceTry <= 0) ? 220 : basePriceTry;
    return OfferMock(
      priceTry: base,
      etaMin: 5,
      providerName: 'Sürücü • En Yakın',
      rating: 4.8,
      reviewCount: 610,
      vehicleText: 'Binek • Konfor',
      plateMasked: '34 YAK **',
      isRecommended: true,
      hasInvoice: false,
      paymentText: 'Nakit / Kart',
      canProvideNewTire: false,
      canProvideUsedTire: false,
    );
  }

  static List<OfferMock> makeMockOffers(String flowTitle, int? basePriceTry) {
    if (flowTitle == 'Lastik') {
      return const <OfferMock>[
        OfferMock(
          priceTry: 380,
          etaMin: 9,
          providerName: 'Lastikçi • Usta Ali',
          rating: 4.7,
          reviewCount: 212,
          vehicleText: 'Mobil Lastik Servisi',
          plateMasked: '34 LST **',
          isRecommended: true,
          hasInvoice: true,
          paymentText: 'Nakit / Kart',
          canProvideNewTire: true,
          canProvideUsedTire: true,
        ),
        OfferMock(
          priceTry: 320,
          etaMin: 14,
          providerName: 'Lastikçi • Hızlı Servis',
          rating: 4.3,
          reviewCount: 98,
          vehicleText: 'Yerinde Müdahale',
          plateMasked: '34 TKR **',
          isRecommended: false,
          hasInvoice: false,
          paymentText: 'Nakit',
          canProvideNewTire: true,
          canProvideUsedTire: false,
        ),
        OfferMock(
          priceTry: 450,
          etaMin: 6,
          providerName: 'Lastikçi • 7/24 Nokta',
          rating: 4.8,
          reviewCount: 341,
          vehicleText: 'Mobil + Atölye',
          plateMasked: '34 NOK **',
          isRecommended: false,
          hasInvoice: true,
          paymentText: 'Nakit / Kart',
          canProvideNewTire: true,
          canProvideUsedTire: true,
        ),
        OfferMock(
          priceTry: 300,
          etaMin: 18,
          providerName: 'Lastikçi • Ekonomik',
          rating: 4.1,
          reviewCount: 57,
          vehicleText: 'Atölye Çıkışı',
          plateMasked: '34 ECO **',
          isRecommended: false,
          hasInvoice: false,
          paymentText: 'Nakit',
          canProvideNewTire: false,
          canProvideUsedTire: true,
        ),
      ];
    }

    if (flowTitle == 'Nakliye') {
      return const <OfferMock>[
        OfferMock(
          priceTry: 1650,
          etaMin: 22,
          providerName: 'Nakliye • Panelvan Usta',
          rating: 4.6,
          reviewCount: 144,
          vehicleText: 'Panelvan • 10 m³',
          plateMasked: '34 PNV **',
          isRecommended: true,
          hasInvoice: true,
          paymentText: 'Nakit / Kart',
          canProvideNewTire: false,
          canProvideUsedTire: false,
        ),
        OfferMock(
          priceTry: 1400,
          etaMin: 35,
          providerName: 'Nakliye • Ekonomik',
          rating: 4.2,
          reviewCount: 73,
          vehicleText: 'Kamyonet • 13 m³',
          plateMasked: '34 KMY **',
          isRecommended: false,
          hasInvoice: false,
          paymentText: 'Nakit',
          canProvideNewTire: false,
          canProvideUsedTire: false,
        ),
        OfferMock(
          priceTry: 1900,
          etaMin: 18,
          providerName: 'Nakliye • Hızlı VIP',
          rating: 4.9,
          reviewCount: 288,
          vehicleText: 'VIP • Hızlı Yük',
          plateMasked: '34 VIP **',
          isRecommended: false,
          hasInvoice: true,
          paymentText: 'Kart / Link',
          canProvideNewTire: false,
          canProvideUsedTire: false,
        ),
        OfferMock(
          priceTry: 1550,
          etaMin: 28,
          providerName: 'Nakliye • Uygun Fiyat',
          rating: 4.4,
          reviewCount: 102,
          vehicleText: 'Panelvan • 12 m³',
          plateMasked: '34 UYG **',
          isRecommended: false,
          hasInvoice: false,
          paymentText: 'Nakit / Kart',
          canProvideNewTire: false,
          canProvideUsedTire: false,
        ),
      ];
    }

    // Çekici default
    return const <OfferMock>[
      OfferMock(
        priceTry: 650,
        etaMin: 16,
        providerName: 'Çekici • Kurtarıcı 34',
        rating: 4.8,
        reviewCount: 410,
        vehicleText: 'Çekici Kamyon',
        plateMasked: '34 CKC **',
        isRecommended: true,
        hasInvoice: true,
        paymentText: 'Nakit / Kart',
        canProvideNewTire: false,
        canProvideUsedTire: false,
      ),
      OfferMock(
        priceTry: 540,
        etaMin: 25,
        providerName: 'Çekici • Ekonomik',
        rating: 4.3,
        reviewCount: 120,
        vehicleText: 'Çekici',
        plateMasked: '34 ECO **',
        isRecommended: false,
        hasInvoice: false,
        paymentText: 'Nakit',
        canProvideNewTire: false,
        canProvideUsedTire: false,
      ),
      OfferMock(
        priceTry: 720,
        etaMin: 12,
        providerName: 'Çekici • Hızlı Müdahale',
        rating: 4.7,
        reviewCount: 233,
        vehicleText: 'Çekici + Vinç',
        plateMasked: '34 HIZ **',
        isRecommended: false,
        hasInvoice: true,
        paymentText: 'Kart / Link',
        canProvideNewTire: false,
        canProvideUsedTire: false,
      ),
      OfferMock(
        priceTry: 590,
        etaMin: 20,
        providerName: 'Çekici • Yakın Servis',
        rating: 4.4,
        reviewCount: 98,
        vehicleText: 'Çekici',
        plateMasked: '34 YKN **',
        isRecommended: false,
        hasInvoice: false,
        paymentText: 'Nakit / Kart',
        canProvideNewTire: false,
        canProvideUsedTire: false,
      ),
    ];
  }
}

/// =======================
/// TEKLİF LİSTESİ (Çekici/Nakliye/Lastik)
/// =======================

class OffersListPage extends StatelessWidget {
  final String flowTitle;
  final List<OfferMock> offers;

  const OffersListPage(
      {super.key, required this.flowTitle, required this.offers});

  @override
  Widget build(BuildContext context) {
    final OfferMock cheapest =
    offers.reduce((a, b) => a.priceTry <= b.priceTry ? a : b);
    final OfferMock fastest =
    offers.reduce((a, b) => a.etaMin <= b.etaMin ? a : b);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: TakNakApp.taknakOrange,
        foregroundColor: Colors.white,
        title: Text('$flowTitle • Teklifler',
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            const _InfoBox(
                text: '3-4 teklif geldi. Karşılaştırıp istediğini seç.'),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: offers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final o = offers[i];

                  String badge = '';
                  if (o.isRecommended) badge = 'Önerilen';
                  if (identical(o, cheapest))
                    badge = badge.isEmpty ? 'En ucuz' : '$badge • En ucuz';
                  if (identical(o, fastest))
                    badge = badge.isEmpty ? 'En hızlı' : '$badge • En hızlı';

                  return _OfferListCard(
                    offer: o,
                    badgeText: badge,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => OfferDetailPage(
                                flowTitle: flowTitle, offer: o)),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            _SecondaryButton(
              label: 'Yeniden ara',
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                    builder: (_) => SearchingPage(flowTitle: flowTitle)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OfferDetailPage extends StatelessWidget {
  final String flowTitle;
  final OfferMock offer;

  const OfferDetailPage(
      {super.key, required this.flowTitle, required this.offer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: TakNakApp.taknakOrange,
        foregroundColor: Colors.white,
        title: Text('$flowTitle • Teklif Detayı',
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 190),
        child: Column(
          children: <Widget>[
            _OfferDriverCard(offer: offer),
            const SizedBox(height: 12),
            _SummaryCard(
                title: 'Ücret',
                value: '${offer.priceTry} ₺',
                icon: Icons.payments_outlined),
            const SizedBox(height: 12),
            _SummaryCard(
                title: 'Varış',
                value: '${offer.etaMin} dk',
                icon: Icons.timer_outlined),
            const SizedBox(height: 12),
            _SummaryCard(
                title: 'Ödeme (seçimin)',
                value: AppStore.paymentLabel(),
                icon: Icons.credit_card),
            const SizedBox(height: 12),
            _SummaryCard(
                title: 'Fiş / Fatura',
                value: offer.hasInvoice ? 'Var' : 'Yok',
                icon: Icons.receipt_long_outlined),
            if (flowTitle == 'Lastik') ...<Widget>[
              const SizedBox(height: 12),
              _SummaryCard(
                  title: 'Lastik temini',
                  value: _tireSupplyText(offer),
                  icon: Icons.settings),
            ],
            const SizedBox(height: 12),
            const _InfoBox(text: 'Kabul edince takip adımlarına geçeceğiz.'),
            const SizedBox(height: 12),
            const _InfoBox(
                text: 'Not: Hizmet başladıktan sonra iptal ücretli olabilir .'),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _SecondaryButton(
                      label: 'Ara',
                      onPressed: () => ScaffoldMessenger.of(context)
                          .showSnackBar(
                          const SnackBar(content: Text('Arama (yakında)'))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SecondaryButton(
                      label: 'Mesaj',
                      onPressed: () => ScaffoldMessenger.of(context)
                          .showSnackBar(
                          const SnackBar(content: Text('Mesaj (yakında)'))),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _PrimaryButton(
                label: 'Kabul Et',
                icon: Icons.check,
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                      builder: (_) => TrackingStepsPage(
                          flowTitle: flowTitle, offer: offer)),
                ),
              ),
              const SizedBox(height: 10),
              _SecondaryButton(
                  label: 'Tekliflere geri dön',
                  onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
      ),
    );
  }

  static String _tireSupplyText(OfferMock o) {
    final List<String> arr = <String>[];
    if (o.canProvideNewTire) arr.add('Sıfır');
    if (o.canProvideUsedTire) arr.add('2. el');
    if (arr.isEmpty) return 'Sadece işlem';
    return arr.join(' + ');
  }
}

/// =======================
/// TAKİP (ortak)
/// =======================

class TrackingStepsPage extends StatefulWidget {
  final String flowTitle;
  final OfferMock offer;

  const TrackingStepsPage(
      {super.key, required this.flowTitle, required this.offer});

  @override
  State<TrackingStepsPage> createState() => _TrackingStepsPageState();
}

class _TrackingStepsPageState extends State<TrackingStepsPage> {
  // Sertifika/teşekkür ekranında göstermek için basit bir yolculuk id'si.
  late final String _tripId = DateTime.now().millisecondsSinceEpoch.toString();

  int _step = 0;
  bool _autoNavigated = false;

  final List<_TrackStep> _steps = const <_TrackStep>[
    _TrackStep(
        title: 'Yola çıktı',
        subtitle: 'Sürücü/servis hazırlanıyor ve hareket etti.'),
    _TrackStep(title: 'Yaklaşıyor', subtitle: 'Konumuna doğru geliyor.'),
    _TrackStep(title: 'Geldi', subtitle: 'Sürücü/servis bulunduğun noktada.'),
    _TrackStep(title: 'Tamamlandı', subtitle: 'İşlem tamamlandı.'),
  ];

  @override
  void initState() {
    super.initState();
    _autoAdvance();
  }

  void _autoAdvance() {
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        if (_step < _steps.length - 1) {
          _step++;
          _autoAdvance();
        }
      });

      // ✅ Yolculuk bitti: kullanıcı butona basmadan otomatik devam
      if (mounted && _step == _steps.length - 1) {
        _onTripCompleted();
      }
    });
  }

  void _onTripCompleted() {
    if (_autoNavigated) return;
    _autoNavigated = true;

    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;

      // Kart seçildiyse önce ödeme ekranı (MVP demo ödeme)
      if (AppStore.paymentMethod == PaymentMethod.card) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => PaymentCheckoutPage(
              userName: AppStore.userName,
              tripId: _tripId,
            ),
          ),
        );
        return;
      }

      // Nakit: direkt teşekkür/sertifika
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TripCompletedThankYouPage(
            userName: AppStore.userName,
            tripId: _tripId,
            city: null,
          ),
        ),
      );
    });
  }

  Widget _banner() {
    // ✅ İstediğin canlı uyarılar
    if (_step == 1) {
      return const _InfoBox(
        text: 'Sürücü adresinize yaklaştı.\nLütfen sürücüyü bekletmeyin.',
      );
    }
    if (_step == 2) {
      return const _InfoBox(
        text: 'Sürücü geldi.\nLütfen aracı hızlıca bulun ve işlemi başlatın.',
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: TakNakApp.taknakOrange,
        foregroundColor: Colors.white,
        title: Text('${widget.flowTitle} • Takip',
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        child: Column(
          children: <Widget>[
            _OfferDriverCard(offer: widget.offer),
            const SizedBox(height: 12),
            _banner(),
            if (_step == 1 || _step == 2) const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE9E9E9)),
              ),
              child: Column(
                children: List<Widget>.generate(_steps.length, (i) {
                  final bool done = i <= _step;
                  final Color dot =
                  done ? TakNakApp.taknakOrange : const Color(0xFFCCCCCC);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 18,
                          height: 18,
                          margin: const EdgeInsets.only(top: 2),
                          decoration:
                          BoxDecoration(color: dot, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                _steps[i].title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: done ? Colors.black87 : Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(_steps[i].subtitle,
                                  style:
                                  const TextStyle(color: Colors.black54)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _SecondaryButton(
                      label: 'Ara',
                      onPressed: () => ScaffoldMessenger.of(context)
                          .showSnackBar(
                          const SnackBar(content: Text('Arama (yakında)'))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SecondaryButton(
                      label: 'Mesaj',
                      onPressed: () => ScaffoldMessenger.of(context)
                          .showSnackBar(
                          const SnackBar(content: Text('Mesaj (yakında)'))),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Kullanıcı "tamamlandı"yı görmeden kaçmasın diye burada
              // "Ana sayfaya dön" butonu yok. Son adımda otomatik yönlendiriyoruz.
              if (_step >= _steps.length - 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    AppStore.paymentMethod == PaymentMethod.card
                        ? 'Ödeme ekranına yönlendiriliyorsunuz…'
                        : 'Teşekkür ekranına yönlendiriliyorsunuz…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withOpacity(0.55),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackStep {
  final String title;
  final IconData? icon;
  final String subtitle;
  const _TrackStep({required this.title, required this.subtitle, this.icon});
}

/// =======================
/// FLOW UI: Center
/// =======================

class _CenterFlowScaffold extends StatelessWidget {
  final String title;
  final IconData icon;
  final String bigText;
  final String subText;
  final bool showSpinner;

  const _CenterFlowScaffold({
    required this.title,
    required this.icon,
    required this.bigText,
    required this.subText,
    required this.showSpinner,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: TakNakApp.taknakOrange,
        foregroundColor: Colors.white,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: TakNakApp.taknakOrange.withAlpha(18),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Icon(icon, size: 42, color: Colors.black87),
              ),
              const SizedBox(height: 14),
              Text(bigText,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 22)),
              const SizedBox(height: 6),
              Text(subText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 14),
              if (showSpinner) const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

/// =======================
/// DRAWER + PROFILE PAGES
/// =======================

class _TakNakDrawer extends StatelessWidget {
  const _TakNakDrawer();

  void _open(BuildContext context, Widget page) async {
    Navigator.pop(context);
    await Future.microtask(() {});
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              decoration: BoxDecoration(
                color: TakNakApp.taknakOrange.withAlpha(18),
                border: const Border(
                  bottom: BorderSide(color: Color(0xFFE9E9E9)),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE9E9E9)),
                    ),
                    child: const Icon(Icons.person, size: 30),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(AppStore.userName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 18)),
                        const SizedBox(height: 4),
                        Text(AppStore.phone,
                            style: const TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _open(context, const ProfilePage()),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.mail_outline),
                    title: const Text('Mesajlarım',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    onTap: () => _open(context, const MessagesPage()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.map_outlined),
                    title: const Text('Geçmiş aktivite',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    onTap: () => _open(context, const HistoryPage()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: const Text('Rezervasyonlarım',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    onTap: () => _open(context, const ReservationsPage()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.credit_card),
                    title: const Text('Ödeme Yöntemlerim',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    onTap: () => _open(context, const PaymentMethodsPage()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('Hesabım',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    onTap: () => _open(context, const AccountPage()),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.policy_outlined),
                    title: const Text('Yasal Bilgilendirme',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    onTap: () => _open(context, const LegalInfoPage()),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('v0.1.0',
                  style: TextStyle(
                      color: Colors.black45, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: TakNakApp.taknakOrange,
        foregroundColor: Colors.white,
        title:
        const Text('Profil', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: TakNakApp.taknakOrange.withAlpha(18),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.person, size: 46),
            ),
            const SizedBox(height: 12),
            Text(AppStore.userName,
                style:
                const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 4),
            Text(AppStore.phone,
                style: const TextStyle(
                    color: Colors.black54, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            const _InfoBox(
                text:
                'Profil düzenleme, doğrulama ve fotoğraf yükleme sonraki sürümde.'),
          ],
        ),
      ),
    );
  }
}

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _EmptyStateScaffold(
      title: 'Mesajlarım',
      icon: Icons.mail_outline,
      text: 'Henüz mesaj yok.\nSürücü/usta mesajlaşması sonraki sürümde.',
    );
  }
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _EmptyStateScaffold(
      title: 'Geçmiş aktivite',
      icon: Icons.map_outlined,
      text: 'Henüz geçmiş aktivite yok.\nİlk işlemden sonra burada göreceksin.',
    );
  }
}

class ReservationsPage extends StatelessWidget {
  const ReservationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _EmptyStateScaffold(
      title: 'Rezervasyonlarım',
      icon: Icons.calendar_month_outlined,
      text: 'Henüz rezervasyon yok.\nRezervasyon akışı MVP+.',
    );
  }
}

class PaymentMethodsPage extends StatefulWidget {
  const PaymentMethodsPage({super.key});

  @override
  State<PaymentMethodsPage> createState() => _PaymentMethodsPageState();
}

class _PaymentMethodsPageState extends State<PaymentMethodsPage> {
  PaymentMethod _method = AppStore.paymentMethod;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: TakNakApp.taknakOrange,
        foregroundColor: Colors.white,
        title: const Text('Ödeme Yöntemlerim',
            style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            const _InfoBox(
                text:
                'Bu ekran sadece seçimidir. Gerçek ödeme entegrasyonu sonra (iyzico vb).'),
            const SizedBox(height: 12),
            RadioListTile<PaymentMethod>(
              value: PaymentMethod.cash,
              groupValue: _method,
              onChanged: (v) =>
                  setState(() => _method = v ?? PaymentMethod.cash),
              title: const Text('Nakit',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              subtitle: const Text('Sürücü/usta ile elden ödeme.'),
            ),
            RadioListTile<PaymentMethod>(
              value: PaymentMethod.card,
              groupValue: _method,
              onChanged: (v) =>
                  setState(() => _method = v ?? PaymentMethod.cash),
              title: const Text('Kart',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              subtitle: const Text('Online ödeme.'),
            ),
            const Spacer(),
            _PrimaryButton(
              label: 'Kaydet',
              icon: Icons.check,
              onPressed: () {
                setState(() => AppStore.paymentMethod = _method);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('Seçildi: ${AppStore.paymentLabel()}')),
                );
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 10),
            _SecondaryButton(
                label: 'Vazgeç', onPressed: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }
}

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: TakNakApp.taknakOrange,
        foregroundColor: Colors.white,
        title: const Text('Hesabım',
            style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            _SummaryCard(
                title: 'Kullanıcı',
                value: AppStore.userName,
                icon: Icons.person),
            const SizedBox(height: 12),
            _SummaryCard(
                title: 'Telefon', value: AppStore.phone, icon: Icons.phone),
            const SizedBox(height: 12),
            _SummaryCard(
                title: 'Ödeme yöntemi',
                value: AppStore.paymentLabel(),
                icon: Icons.credit_card),
            const SizedBox(height: 12),
            const _InfoBox(
                text:
                'Hesap doğrulama, cihaz güvenliği, şifre vb. sonraki sürümde.'),
            const Spacer(),
            _SecondaryButton(
              label: 'Çıkış',
              onPressed: () {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Çıkış')));
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class LegalInfoPage extends StatelessWidget {
  const LegalInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: TakNakApp.taknakOrange,
        foregroundColor: Colors.white,
        title: const Text('Yasal Bilgilendirme',
            style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: const <Widget>[
            _InfoBox(
              text:
              'KVKK & Sözleşme\n\n• Bu sürümde gerçek kişisel veri işlemesi yapılmıyor.\n• Yayına çıkmadan önce KVKK metni + açık rıza ekranı zorunlu olacak.',
            ),
            SizedBox(height: 12),
            _InfoBox(
              text:
              'İptal Politikası\n\n• Hizmet başladıktan sonra iptal ücretli olabilir.\n• Sürücü/usta yola çıktıktan sonra iptal ederseniz bedel yansıyabilir.',
            ),
            SizedBox(height: 12),
            _InfoBox(
              text:
              'Sorumluluk\n\n• Bu uygulama sadece eşleştirme/iletişim arayüzüdür.\n• Yayına çıkmadan önce kapsamlı hizmet şartları eklenecek.',
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStateScaffold extends StatelessWidget {
  final String title;
  final IconData icon;
  final String text;

  const _EmptyStateScaffold({
    required this.title,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: TakNakApp.taknakOrange,
        foregroundColor: Colors.white,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: TakNakApp.taknakOrange.withAlpha(18),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Icon(icon, size: 42, color: Colors.black87),
              ),
              const SizedBox(height: 14),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}

/// =======================
/// HOME UI PARTS
/// =======================

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEDEDED),
      alignment: Alignment.center,
      child: const Text(
        'Harita şimdilik kapalı.\n(API key ekleyince açacağız)',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5E5)),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.search, color: Colors.black54),
          SizedBox(width: 10),
          Expanded(
            child: Text('Nereye / Ne lazım?',
                style: TextStyle(
                    color: Colors.black54, fontWeight: FontWeight.w700)),
          ),
          Icon(Icons.chevron_right, color: Colors.black45),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String subtitle;
  final String tag;
  final VoidCallback onTap;

  const _ServiceCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tag,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        height: 120,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE9E9E9)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: TakNakApp.taknakOrange.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 18),
                ),
                const Spacer(),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F4F4),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFE2E2E2)),
                  ),
                  child: Text(tag,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 12)),
                ),
              ],
            ),
            const Spacer(),
            Text(title,
                style:
                const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: const TextStyle(
                    color: Colors.black54, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// =======================
/// UI HELPERS
/// =======================

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionTitle(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: TakNakApp.taknakOrange.withAlpha(18),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: Colors.black87),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(
                      color: Colors.black54, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String text;
  const _InfoBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TakNakApp.taknakOrange.withAlpha(18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TakNakApp.taknakOrange.withAlpha(50)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}
class _MiniMapCard extends StatelessWidget {
  final LatLng? from;
  final LatLng? to;

  const _MiniMapCard({required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    final LatLng fallback = const LatLng(41.0082, 28.9784); // İstanbul
    final LatLng center = from ?? to ?? fallback;

    final markers = <Marker>{};
    if (from != null) {
      markers.add(Marker(markerId: const MarkerId('from'), position: from!));
    }
    if (to != null) {
      markers.add(Marker(markerId: const MarkerId('to'), position: to!));
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: SizedBox(
              height: 160,
              width: double.infinity,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(target: center, zoom: 12),
                markers: markers,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                compassEnabled: false,
                mapToolbarEnabled: false,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    (from == null && to == null)
                        ? 'Adres seçince marker çıkacak'
                        : 'Marker’lar hazır',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                ElevatedButton(
                  onPressed: (from == null && to == null)
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _FullMapPage(from: from, to: to),
                            ),
                          );
                        },
                  child: const Text('Yolculuğu Başlat'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FullMapPage extends StatelessWidget {
  final LatLng? from;
  final LatLng? to;

  const _FullMapPage({required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    final LatLng fallback = const LatLng(41.0082, 28.9784); // İstanbul
    final LatLng center = from ?? to ?? fallback;

    final markers = <Marker>{};
    if (from != null) {
      markers.add(Marker(markerId: const MarkerId('from'), position: from!));
    }
    if (to != null) {
      markers.add(Marker(markerId: const MarkerId('to'), position: to!));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Harita'),
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: center, zoom: 14),
        markers: markers,
        myLocationButtonEnabled: true,
        zoomControlsEnabled: true,
      ),
    );
  }
}




class _ChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChipButton(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? TakNakApp.taknakOrange.withAlpha(18) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? TakNakApp.taknakOrange.withAlpha(120)
                : const Color(0xFFE9E9E9),
          ),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _SmallButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: const BorderSide(color: Color(0xFFE9E9E9)),
          foregroundColor: Colors.black87,
        ),
        onPressed: onPressed,
        child: Icon(icon),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _PrimaryButton(
      {required this.label, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: TakNakApp.taknakOrange,
          foregroundColor: Colors.white,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _SecondaryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black87,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _SummaryCard(
      {required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9E9E9)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: TakNakApp.taknakOrange.withAlpha(18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.black87),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: const TextStyle(
                        color: Colors.black54, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferDriverCard extends StatelessWidget {
  final OfferMock offer;
  const _OfferDriverCard({required this.offer});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9E9E9)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
              color: Color(0x14000000), blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: TakNakApp.taknakOrange.withAlpha(18),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.person, size: 30, color: Colors.black87),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(offer.providerName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 4),
                Text('${offer.vehicleText} • Plaka: ${offer.plateMasked}',
                    style: const TextStyle(
                        color: Colors.black54, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    const Icon(Icons.star, size: 18, color: Colors.amber),
                    const SizedBox(width: 6),
                    Text(
                        '${offer.rating.toStringAsFixed(1)}  (${offer.reviewCount})',
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferListCard extends StatelessWidget {
  final OfferMock offer;
  final String badgeText;
  final VoidCallback onTap;

  const _OfferListCard({
    required this.offer,
    required this.badgeText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE9E9E9)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
                color: Color(0x12000000), blurRadius: 14, offset: Offset(0, 6)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: TakNakApp.taknakOrange.withAlpha(18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.person, color: Colors.black87),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(offer.providerName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(height: 3),
                      Text('${offer.vehicleText} • ${offer.plateMasked}',
                          style: const TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                if (badgeText.isNotEmpty)
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: TakNakApp.taknakOrange.withAlpha(18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: TakNakApp.taknakOrange.withAlpha(70)),
                    ),
                    child: Text(badgeText,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                    child: _MiniStat(
                        title: 'Ücret',
                        value: '${offer.priceTry} ₺',
                        icon: Icons.payments_outlined)),
                const SizedBox(width: 12),
                Expanded(
                    child: _MiniStat(
                        title: 'Varış',
                        value: '${offer.etaMin} dk',
                        icon: Icons.timer_outlined)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                const Icon(Icons.star, size: 18, color: Colors.amber),
                const SizedBox(width: 6),
                Text(
                    '${offer.rating.toStringAsFixed(1)}  (${offer.reviewCount})',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const Spacer(),
                const Text('Detay',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right,
                    size: 20, color: Colors.black54),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _MiniStat(
      {required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TakNakApp.taknakOrange.withAlpha(14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TakNakApp.taknakOrange.withAlpha(40)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: Colors.black87),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: const TextStyle(
                        color: Colors.black54, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipItem<T> {
  final String label;
  final T value;
  const _ChipItem(this.label, this.value);
}

class _TwoRowChips<T> extends StatelessWidget {
  final List<_ChipItem<T>> itemsRow1;
  final List<_ChipItem<T>> itemsRow2;
  final T value;
  final ValueChanged<T> onChanged;

  const _TwoRowChips({
    required this.itemsRow1,
    required this.itemsRow2,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget row(List<_ChipItem<T>> items) {
      return Row(
        children: <Widget>[
          Expanded(
            child: _ChipButton(
              label: items[0].label,
              selected: value == items[0].value,
              onTap: () => onChanged(items[0].value),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ChipButton(
              label: items[1].label,
              selected: value == items[1].value,
              onTap: () => onChanged(items[1].value),
            ),
          ),
        ],
      );
    }

    return Column(
      children: <Widget>[
        row(itemsRow1),
        const SizedBox(height: 12),
        row(itemsRow2),
      ],
    );
  }
}

/// Requests location permission once and keeps the app running even if user denies.
/// (Map will still work; blue dot needs permission.)
class LocationPermissionGate extends StatefulWidget {
  final Widget child;
  const LocationPermissionGate({super.key, required this.child});

  @override
  State<LocationPermissionGate> createState() => _LocationPermissionGateState();
}

/// ===================
/// AUTH SCREENS (UI ONLY)
/// ===================

enum AuthMode { login, register }

class AuthStartPage extends StatelessWidget {
  const AuthStartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      TakNakApp.taknakOrange.withOpacity(0.12),
                      Colors.white,
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.black12),
                          boxShadow: const [
                            BoxShadow(
                              blurRadius: 10,
                              offset: Offset(0, 6),
                              color: Color(0x11000000),
                            )
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: TakNakApp.taknakOrange,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'TakNak',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '''Sürüş, çekici, nakliye...
tek uygulamada.''',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Tek uygulamada sürüş, çekici, nakliye ve daha fazlası.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TakNakApp.taknakOrange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AuthMethodPage(mode: AuthMode.login),
                          ),
                        );
                      },
                      child: const Text('Giriş yap', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,
                        side: const BorderSide(color: Colors.black12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AuthMethodPage(mode: AuthMode.register),
                          ),
                        );
                      },
                      child: const Text('Kayıt ol', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => AppStore.isLoggedIn.value = true,
                    child: const Text('Misafir olarak devam et'),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class AuthMethodPage extends StatelessWidget {
  final AuthMode mode;
  const AuthMethodPage({super.key, required this.mode});

  @override
  Widget build(BuildContext context) {
    final title = mode == AuthMode.login ? 'Tekrar hoş geldiniz' : 'Hoş geldin';
    final subtitle = mode == AuthMode.login
        ? 'Aşağıdaki seçeneklerden biriyle giriş yap'
        : 'Aşağıdaki seçeneklerden biriyle kayıt ol';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 18),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: TakNakApp.taknakOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => PhoneAuthPage(mode: mode)),
                  );
                },
                child: const Text('Telefon numarasıyla devam et', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 54,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.black12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => EmailAuthPage(mode: mode)),
                  );
                },
                child: const Text('E-posta/kullanıcı adı ile devam edin', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const Spacer(),
            Text(
              'Not: Doğrulama altyapısı yakında aktif edilecek.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class PhoneAuthPage extends StatefulWidget {
  final AuthMode mode;
  const PhoneAuthPage({super.key, required this.mode});

  @override
  State<PhoneAuthPage> createState() => _PhoneAuthPageState();
}

class _PhoneAuthPageState extends State<PhoneAuthPage> {
  final TextEditingController _controller = TextEditingController();
  bool _useSms = true;

  bool get _valid => _digitsOnly(_controller.text).length >= 10;

  static String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Telefon numaranı gir')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Text('🇹🇷', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 8),
                      Text('+90'),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: 'Telefon numarası',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Bu numarayı doğrulamak için bir kod göndereceğiz. Veriler onayın olmadan asla üçüncü taraflarla paylaşılmayacak.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 18),
            _radioRow(
              title: 'SMS kullan',
              value: true,
              group: _useSms,
              onChanged: (v) => setState(() => _useSms = v),
            ),
            _radioRow(
              title: 'WhatsApp kullan',
              value: false,
              group: _useSms,
              onChanged: (v) => setState(() => _useSms = v),
            ),
            const Spacer(),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: TakNakApp.taknakOrange,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.black12,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _valid
                    ? () {
                  final phone = '+90 ${_digitsOnly(_controller.text)}';
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OtpPage(
                        phone: phone,
                        viaWhatsApp: !_useSms,
                      ),
                    ),
                  );
                }
                    : null,
                child: const Text('Devam et', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _radioRow({
    required String title,
    required bool value,
    required bool group,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
            Radio<bool>(
              value: value,
              groupValue: group,
              onChanged: (v) => onChanged(v ?? true),
              activeColor: TakNakApp.taknakOrange,
            ),
          ],
        ),
      ),
    );
  }
}

class OtpPage extends StatefulWidget {
  final String phone;
  final bool viaWhatsApp;
  const OtpPage({super.key, required this.phone, required this.viaWhatsApp});

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  final TextEditingController _code = TextEditingController();
  bool get _valid => _code.text.trim().length >= 4;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Doğrulama kodu')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.phone} numarasına ${widget.viaWhatsApp ? 'WhatsApp' : 'SMS'} ile bir kod gönderdik.',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'Kodu gir',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const Spacer(),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: TakNakApp.taknakOrange,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.black12,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _valid
                    ? () {
                  AppStore.isLoggedIn.value = true;
                  Navigator.of(context).popUntil((r) => r.isFirst);
                }
                    : null,
                child: const Text('Girişi tamamla', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmailAuthPage extends StatefulWidget {
  final AuthMode mode;
  const EmailAuthPage({super.key, required this.mode});

  @override
  State<EmailAuthPage> createState() => _EmailAuthPageState();
}

class _EmailAuthPageState extends State<EmailAuthPage> {
  final TextEditingController _id = TextEditingController();

  bool get _valid => _id.text.trim().length >= 3;

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == AuthMode.login
        ? 'E-postanı veya kullanıcı adını gir'
        : 'E-posta veya kullanıcı adı';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _id,
              decoration: InputDecoration(
                hintText: 'E-posta ya da kullanıcı adı',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const Spacer(),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: TakNakApp.taknakOrange,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.black12,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _valid
                    ? () {
                  // Dogrulama altyapisi eklenene kadar basit giris akisi.
                  AppStore.isLoggedIn.value = true;
                  Navigator.of(context).popUntil((r) => r.isFirst);
                }
                    : null,
                child: Text(
                  widget.mode == AuthMode.login ? 'Giriş bağlantısı al' : 'Devam et',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationPermissionGateState extends State<LocationPermissionGate> {
  @override
  void initState() {
    super.initState();
    _ensurePermission();
  }

  Future<void> _ensurePermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ===============================
// ÖDEME + YOLCULUK SONU AKIŞI
// ===============================

class PaymentCheckoutPage extends StatefulWidget {
  const PaymentCheckoutPage({
    super.key,
    required this.userName,
    this.tripId,
    this.city,
  });

  final String userName;
  final String? tripId;
  final String? city;

  @override
  State<PaymentCheckoutPage> createState() => _PaymentCheckoutPageState();
}

class _PaymentCheckoutPageState extends State<PaymentCheckoutPage> {
  bool _processing = true;

  @override
  void initState() {
    super.initState();
    _fakePayment();
  }

  Future<void> _fakePayment() async {
    // Gerçek ödeme entegrasyonu gelene kadar 1.4sn'lik "processing" animasyonu.
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    setState(() => _processing = false);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TripCompletedThankYouPage(
          userName: widget.userName,
          tripId: widget.tripId,
          city: widget.city,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        title: const Text("Ödeme"),
      ),
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _processing ? Icons.lock_clock_rounded : Icons.check_circle_rounded,
                size: 56,
                color: TakNakApp.taknakOrange,
              ),
              const SizedBox(height: 14),
              Text(
                _processing ? "Ödeme alınıyor..." : "Ödeme alındı!",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(
                _processing
                    ? "Bankanızla güvenli bağlantı kuruluyor."
                    : "Teşekkürler, yolculuk tamamlandı ekranına yönlendiriliyorsunuz.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black.withOpacity(0.65)),
              ),
              const SizedBox(height: 16),
              if (_processing)
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class TripCompletedThankYouPage extends StatefulWidget {
  const TripCompletedThankYouPage({
    super.key,
    required this.userName,
    this.tripId,
    this.city,
  });

  final String userName;
  final String? tripId;
  final String? city;

  @override
  State<TripCompletedThankYouPage> createState() => _TripCompletedThankYouPageState();
}

class _TripCompletedThankYouPageState extends State<TripCompletedThankYouPage> {
  final GlobalKey _certificateKey = GlobalKey();
  bool _sharing = false;

  // TakNak renkleri (senin istediğin #FF8C00)
  static const Color taknakOrange = Color(0xFFFF8C00);

  Future<void> _shareCertificate() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    try {
      final boundary = _certificateKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception("Sertifika görseli bulunamadı (RenderRepaintBoundary null). ");
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception("PNG üretilemedi (byteData null).");

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/taknak_iyilik_sertifikasi_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: "TakNak ile yaptığım yolculukla toplumsal fayda modeline katkı sağladım. 🧡",
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Paylaşım hatası: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final maxCardWidth = w > 520 ? 520.0 : w;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
        title: const Text(""),
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxCardWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  const Text(
                    "Yolculuk Tamamlandı!",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Bugün sadece bir yere gitmediniz, bir hayata dokundunuz.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: Colors.black.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Sertifika (paylaşılacak alan)
                  RepaintBoundary(
                    key: _certificateKey,
                    child: _CertificateCard(
                      userName: widget.userName,
                      tripId: widget.tripId,
                      city: widget.city,
                      accent: taknakOrange,
                    ),
                  ),

                  const Spacer(),

                  ElevatedButton.icon(
                    onPressed: _sharing ? null : _shareCertificate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: taknakOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    icon: _sharing
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                        : const Icon(Icons.ios_share_rounded),
                    label: Text(
                      _sharing ? "Hazırlanıyor..." : "Sertifikamı Paylaş",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Paylaşım ekranı telefonunun menüsüyle açılır (WhatsApp/Instagram vb.).",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withOpacity(0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CertificateCard extends StatelessWidget {
  const _CertificateCard({
    required this.userName,
    this.tripId,
    this.city,
    required this.accent,
  });

  final String userName;
  final String? tripId;
  final String? city;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final dateStr = _formatDateTR(DateTime.now());

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFFF8F8F8),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 44,
                        height: 44,
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Image.asset(
                            "assets/taknak_logo.png",
                            fit: BoxFit.contain,
                            errorBuilder: (c, e, s) => Icon(Icons.local_taxi_rounded, color: accent, size: 28),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "İyilik Sertifikası",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.black.withOpacity(0.9),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black.withOpacity(0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Sayın $userName,",
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "TakNak ile yaptığınız bu yolculuk sayesinde toplumsal fayda modelimize katkıda bulundunuz.",
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: Colors.black.withOpacity(0.75),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip("Tarih: $dateStr", accent),
                          if (city != null && city!.trim().isNotEmpty) _chip("Şehir: $city", accent),
                          if (tripId != null && tripId!.trim().isNotEmpty) _chip("Yolculuk: #$tripId", accent),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Paylaş ve iyiliği büyüt 🧡",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.black.withOpacity(0.75),
                        ),
                      ),
                    ),
                    // Material icon setinde "whatsapp" yok; sembolik ikon kullanıyoruz.
                    _socialIcon(Icons.chat_bubble_rounded, accent),
                    const SizedBox(width: 8),
                    _socialIcon(Icons.camera_alt_rounded, accent),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _chip(String text, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.black.withOpacity(0.75),
        ),
      ),
    );
  }

  static Widget _socialIcon(IconData icon, Color accent) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Icon(icon, size: 18, color: accent),
    );
  }

  static String _formatDateTR(DateTime d) {
    String two(int n) => n.toString().padLeft(2, "0");
    return "${two(d.day)}.${two(d.month)}.${d.year}";
  }
}

// -----------------------------
// Shared widget: Address pick card
// -----------------------------
class _AddressPickCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  const _AddressPickCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool empty = value == 'Adres seç';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE9E9E9)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: TakNakApp.taknakOrange.withAlpha(18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.black87),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: const TextStyle(
                          color: Colors.black54, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: empty ? Colors.black38 : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.black54),
          ],
        ),
      ),
    );
  }
}

// ===================
// Address helper utils (AddressSearchPage sonucu için)
// Format: "Adres satırı\nlat,lng"
// ===================
LatLng? _parseLatLngFromAddressString(String s) {
  final parts = s.split('\n');
  if (parts.length < 2) return null;

  final last = parts.last.trim(); // "lat,lng"
  final ll = last.split(',');
  if (ll.length != 2) return null;

  final lat = double.tryParse(ll[0].trim());
  final lng = double.tryParse(ll[1].trim());
  if (lat == null || lng == null) return null;

  return LatLng(lat, lng);
}

String _stripCoords(String s) {
  final parts = s.split('\n');
  return parts.isEmpty ? s : parts.first.trim();
}