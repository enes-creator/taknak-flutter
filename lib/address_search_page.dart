import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'app_config.dart'; // ✅ API Key buradan geliyor

class AddressSearchPage extends StatefulWidget {
  final String title;
  const AddressSearchPage({super.key, this.title = "Adres Seç"});

  @override
  State<AddressSearchPage> createState() => _AddressSearchPageState();
}

class _AddressSearchPageState extends State<AddressSearchPage> {
  // ✅ DÜZELTİLDİ: app_config.dart içindeki isimle aynı (S harfi var)
  final String googlePlacesApiKey = GOOGLE_MAPS_API_KEY;

  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  bool _popping = false;
  String? _error;
  List<_Prediction> _items = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      await _search(q.trim());
    });
  }

  Future<void> _search(String q) async {
    if (!mounted) return;
    if (q.isEmpty) {
      setState(() {
        _items = [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.https(
          "maps.googleapis.com", "/maps/api/place/autocomplete/json", {
        "input": q,
        "key": googlePlacesApiKey,
        "language": "tr",
        "components": "country:tr",
      });

      final res = await http.get(uri);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final status = (data["status"] ?? "").toString();

      if (status != "OK" && status != "ZERO_RESULTS") {
        throw Exception("Autocomplete hata: $status");
      }

      final preds = (data["predictions"] as List? ?? [])
          .map((e) => _Prediction.fromJson(e as Map<String, dynamic>))
          .toList();

      if (!mounted) return;
      setState(() {
        _items = preds;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _selectPrediction(_Prediction p) async {
    if (_popping) return;
    _popping = true;

    try {
      setState(() {
        _error = null;
        _loading = true;
      });

      final uri =
          Uri.https("maps.googleapis.com", "/maps/api/place/details/json", {
        "place_id": p.placeId,
        "key": googlePlacesApiKey,
        "language": "tr",
        "fields": "formatted_address,geometry",
      });

      final res = await http.get(uri);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final result = (data["result"] as Map?)?.cast<String, dynamic>() ?? {};

      final details = {
        "address": (result["formatted_address"] ?? p.description).toString(),
        "lat": (result["geometry"]?["location"]?["lat"] as num?)?.toDouble(),
        "lng": (result["geometry"]?["location"]?["lng"] as num?)?.toDouble(),
      };

      if (!mounted) return;

      // ✅ NAVİGASYON HATASINI ÇÖZEN YER (debugLocked fix)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context, details);
        }
      });
    } catch (e) {
      _popping = false;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF6F1ED);
    const border = Color(0xFF7A4E2A);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text(widget.title, style: const TextStyle(color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: border, width: 1.5),
                borderRadius: BorderRadius.circular(14),
                color: Colors.white.withOpacity(0.4),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.search),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onChanged: _onQueryChanged,
                      decoration: const InputDecoration(
                          border: InputBorder.none, hintText: "Adres ara…"),
                    ),
                  ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            Expanded(
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(_items[i].mainText),
                  subtitle: Text(_items[i].secondaryText ?? ""),
                  onTap: () => _selectPrediction(_items[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Prediction {
  final String placeId;
  final String description;
  final String mainText;
  final String? secondaryText;

  _Prediction(
      {required this.placeId,
      required this.description,
      required this.mainText,
      this.secondaryText});

  factory _Prediction.fromJson(Map<String, dynamic> j) {
    final fmt =
        (j["structured_formatting"] as Map?)?.cast<String, dynamic>() ?? {};
    return _Prediction(
      placeId: (j["place_id"] ?? "").toString(),
      description: (j["description"] ?? "").toString(),
      mainText: (fmt["main_text"] ?? j["description"]).toString(),
      secondaryText: fmt["secondary_text"]?.toString(),
    );
  }
}
