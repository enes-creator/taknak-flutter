import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'address_search_page.dart';
import 'api_service.dart';

class TakNakAnalizEkrani extends StatefulWidget {
  const TakNakAnalizEkrani({super.key});

  @override
  State<TakNakAnalizEkrani> createState() => _TakNakAnalizEkraniState();
}

class _TakNakAnalizEkraniState extends State<TakNakAnalizEkrani> {
  // 🔑 KESİN ÇÖZÜM: Key'i direkt buraya yazıyoruz, hata şansı yok.
  static const String MY_API_KEY = "AIzaSyD4oMeOGCFYcg90FtPvJXKS_v22mq9x7j0";

  final TextEditingController _c = TextEditingController();
  GoogleMapController? _mapController;

  bool _loading = false;
  String? _error;

  String? fromAddress, toAddress;
  LatLng? fromLatLng, toLatLng;

  // Haritayı işaretçilere göre ortala
  void _updateMapFocus() {
    if (_mapController == null) return;
    if (fromLatLng != null && toLatLng != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            fromLatLng!.latitude < toLatLng!.latitude
                ? fromLatLng!.latitude
                : toLatLng!.latitude,
            fromLatLng!.longitude < toLatLng!.longitude
                ? fromLatLng!.longitude
                : toLatLng!.longitude,
          ),
          northeast: LatLng(
            fromLatLng!.latitude > toLatLng!.latitude
                ? fromLatLng!.latitude
                : toLatLng!.latitude,
            fromLatLng!.longitude > toLatLng!.longitude
                ? fromLatLng!.longitude
                : toLatLng!.longitude,
          ),
        ),
        50,
      ));
    } else if (fromLatLng != null) {
      _mapController!
          .animateCamera(CameraUpdate.newLatLngZoom(fromLatLng!, 14));
    }
  }

  Future<void> _analyze() async {
    final txt = _c.text.trim();
    if (txt.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await ApiService.analyzeText(txt);

      setState(() {
        fromAddress = result.fromText;
        toAddress = result.toText;
      });

      if (fromAddress != null) {
        final loc = await _geocode(fromAddress!);
        if (loc != null) fromLatLng = loc;
      }
      if (toAddress != null) {
        final loc = await _geocode(toAddress!);
        if (loc != null) toLatLng = loc;
      }

      setState(() {});
      _updateMapFocus();
    } catch (e) {
      setState(() => _error = "Analiz hatası: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<LatLng?> _geocode(String address) async {
    try {
      final uri = Uri.https("maps.googleapis.com", "/maps/api/geocode/json", {
        "address": address,
        "key": MY_API_KEY, // ✅ Kendi tanımladığımız değişkeni kullanıyoruz
        "language": "tr",
      });

      final res = await http.get(uri);
      final data = jsonDecode(res.body);

      if (data["status"] == "OK") {
        final loc = data["results"][0]["geometry"]["location"];
        return LatLng(loc["lat"], loc["lng"]);
      }
    } catch (e) {
      debugPrint("Geocode Error: $e");
    }
    return null;
  }

  Future<void> _pickManual(bool isFrom) async {
    final dynamic result = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) =>
              AddressSearchPage(title: isFrom ? "Nereden" : "Nereye")),
    );

    if (result != null && result is Map) {
      setState(() {
        if (isFrom) {
          fromAddress = result["address"];
          fromLatLng = LatLng(result["lat"], result["lng"]);
        } else {
          toAddress = result["address"];
          toLatLng = LatLng(result["lat"], result["lng"]);
        }
      });
      _updateMapFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7EEE9),
      appBar: AppBar(
          title: const Text("TakNak Süper Zeka Analiz"),
          backgroundColor: const Color(0xFFFF6A00)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.black12)),
            child: TextField(
              controller: _c,
              maxLines: 3,
              decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: "Örn: Beşiktaş'tan Ataşehir'e..."),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _loading ? null : _analyze,
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6A00),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15))),
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Süper Analiz Yap",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child:
                    Text(_error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 220,
              child: GoogleMap(
                initialCameraPosition: const CameraPosition(
                    target: LatLng(41.01, 28.97), zoom: 11),
                onMapCreated: (c) => _mapController = c,
                markers: {
                  if (fromLatLng != null)
                    Marker(
                        markerId: const MarkerId("f"), position: fromLatLng!),
                  if (toLatLng != null)
                    Marker(markerId: const MarkerId("t"), position: toLatLng!),
                },
                liteModeEnabled: false,
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
              ),
            ),
          ),
          const SizedBox(height: 15),
          _AddressBox(
              title: "Nereden",
              value: fromAddress,
              onTap: () => _pickManual(true)),
          const SizedBox(height: 8),
          _AddressBox(
              title: "Nereye",
              value: toAddress,
              onTap: () => _pickManual(false)),
          const SizedBox(height: 20),
          SizedBox(
            height: 60,
            child: ElevatedButton(
              onPressed:
                  (fromLatLng != null && toLatLng != null) ? () {} : null,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15))),
              child: const Text("YOLCULUĞU BAŞLAT",
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressBox extends StatelessWidget {
  final String title;
  final String? value;
  final VoidCallback onTap;
  const _AddressBox(
      {required this.title, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF7A4A35), width: 1.5)),
        child: Row(
          children: [
            const Icon(Icons.location_on, color: Color(0xFF7A4A35)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                          fontWeight: FontWeight.bold)),
                  Text(value ?? "Belirlenmedi",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          overflow: TextOverflow.ellipsis)),
                ])),
            const Icon(Icons.edit, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
