import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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

  static const Color taknakOrange = Color(0xFFFF8C00);

  Future<void> _shareCertificate() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    try {
      final renderObject = _certificateKey.currentContext?.findRenderObject();
      final boundary = renderObject is RenderRepaintBoundary ? renderObject : null;
      if (boundary == null) {
        throw Exception("Sertifika görseli bulunamadı (RenderRepaintBoundary null).");
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Paylaşım hatası: $e")),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final maxCardWidth = w > 520 ? 520.0 : w;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
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
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.1),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Bugün sadece bir yere gitmediniz, bir hayata dokundunuz.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, height: 1.35, color: Colors.black.withOpacity(0.70)),
                  ),
                  const SizedBox(height: 18),
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
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
                    style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
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
                            errorBuilder: (c, e, s) =>
                                Icon(Icons.local_taxi_rounded, color: accent, size: 28),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "İyilik Sertifikası",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black.withOpacity(0.90)),
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
                      Text("Sayın $userName,", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(
                        "TakNak ile yaptığınız bu yolculuk sayesinde toplumsal fayda modelimize katkıda bulundunuz.",
                        style: TextStyle(fontSize: 13, height: 1.35, color: Colors.black.withOpacity(0.75)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "TakNak her ay gelirinin %10'unu ihtiyaç sahiplerine bağışlar.",
                        style: TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w800, color: Colors.black.withOpacity(0.75)),
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
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.black.withOpacity(0.75)),
                      ),
                    ),
                    _socialIcon(Icons.message_rounded, accent),
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
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black.withOpacity(0.75)),
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
