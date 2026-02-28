import 'dart:convert';
import 'package:http/http.dart' as http;

/// =======================================
///  BURAYA KENDİ DEĞERLERİNİ YAZACAKSIN
/// =======================================
/// 1) Google Places/Geocoding API KEY (Google Cloud Console -> APIs & Services -> Credentials)
const String GOOGLE_MAPS_API_KEY = "AIzaSyD4oMeOGCFYcg90FtPvJXKS_v22mq9x7j0";

/// 2) Cloud Run / Cloud Function analyze endpoint (tam URL)
/// Örn: https://xxx-uc.a.run.app/analyze
/// Örn: https://us-central1-xxx.cloudfunctions.net/analyze
///
/// Not: Eğer URL'yi /analyze olmadan yapıştırırsan (sadece domain),
/// ApiService otomatik /analyze denemesi yapar.
const String CLOUD_ANALYZE_URL = "https://taknak-ai-engine-374428838042.europe-west1.run.app";

class LatLngSimple {
  final double lat;
  final double lng;
  const LatLngSimple(this.lat, this.lng);
}

class AiAnalyzeResult {
  final String? fromText;
  final String? toText;
  final String? notes;
  final String? category;

  const AiAnalyzeResult({
    this.fromText,
    this.toText,
    this.notes,
    this.category,
  });

  static AiAnalyzeResult fromAnyJson(dynamic body) {
    if (body is Map<String, dynamic>) {
      String? pickText(dynamic v) {
        if (v == null) return null;
        if (v is String) return v.trim().isEmpty ? null : v.trim();
        if (v is Map) {
          final name = v["name"] ?? v["text"] ?? v["title"];
          if (name is String && name.trim().isNotEmpty) return name.trim();
        }
        final s = v.toString().trim();
        return s.isEmpty ? null : s;
      }

      final from = pickText(body["from"]) ?? pickText(body["from_text"]) ?? pickText(body["origin"]);
      final to = pickText(body["to"]) ?? pickText(body["to_text"]) ?? pickText(body["destination"]);
      final notes = pickText(body["notes"]) ?? pickText(body["note"]) ?? pickText(body["extra"]);
      final category = pickText(body["category"]) ?? pickText(body["type"]);

      return AiAnalyzeResult(fromText: from, toText: to, notes: notes, category: category);
    }
    return const AiAnalyzeResult();
  }
}

class ApiService {
  /// Google Places Autocomplete
  static Future<List<Map<String, dynamic>>> placesAutocomplete(String input) async {
    if (GOOGLE_MAPS_API_KEY.trim().isEmpty) {
      throw Exception("GOOGLE_MAPS_API_KEY girilmemiş.");
    }

    final uri = Uri.https(
      "maps.googleapis.com",
      "/maps/api/place/autocomplete/json",
      {
        "input": input,
        "key": GOOGLE_MAPS_API_KEY,
        "language": "tr",
        "components": "country:tr",
      },
    );

    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception("Places autocomplete hata: ${res.statusCode}");

    final json = jsonDecode(res.body);
    if (json["status"] != "OK" && json["status"] != "ZERO_RESULTS") {
      throw Exception("Places autocomplete status: ${json["status"]} - ${json["error_message"] ?? ""}");
    }

    final preds = (json["predictions"] as List?) ?? [];
    return preds.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  /// Place Details -> Lat/Lng
  static Future<LatLngSimple?> placeDetailsLatLng(String placeId) async {
    if (GOOGLE_MAPS_API_KEY.trim().isEmpty) {
      throw Exception("GOOGLE_MAPS_API_KEY girilmemiş.");
    }

    final uri = Uri.https(
      "maps.googleapis.com",
      "/maps/api/place/details/json",
      {
        "place_id": placeId,
        "fields": "geometry",
        "key": GOOGLE_MAPS_API_KEY,
        "language": "tr",
      },
    );

    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception("Place details hata: ${res.statusCode}");

    final json = jsonDecode(res.body);
    if (json["status"] != "OK") {
      throw Exception("Place details status: ${json["status"]} - ${json["error_message"] ?? ""}");
    }

    final loc = json["result"]?["geometry"]?["location"];
    if (loc is Map && loc["lat"] is num && loc["lng"] is num) {
      return LatLngSimple((loc["lat"] as num).toDouble(), (loc["lng"] as num).toDouble());
    }
    return null;
  }

  /// Text -> Geocoding (AI semt adı döndürdüyse buradan coord çıkarırız)
  static Future<LatLngSimple?> geocodeText(String text) async {
    if (GOOGLE_MAPS_API_KEY.trim().isEmpty) {
      throw Exception("GOOGLE_MAPS_API_KEY girilmemiş.");
    }

    final uri = Uri.https(
      "maps.googleapis.com",
      "/maps/api/geocode/json",
      {
        "address": text,
        "key": GOOGLE_MAPS_API_KEY,
        "language": "tr",
        "region": "tr",
      },
    );

    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception("Geocode hata: ${res.statusCode}");

    final json = jsonDecode(res.body);
    if (json["status"] != "OK") return null;

    final results = (json["results"] as List?) ?? [];
    if (results.isEmpty) return null;

    final loc = results.first["geometry"]?["location"];
    if (loc is Map && loc["lat"] is num && loc["lng"] is num) {
      return LatLngSimple((loc["lat"] as num).toDouble(), (loc["lng"] as num).toDouble());
    }
    return null;
  }

  /// Cloud AI Analyze
  static Future<AiAnalyzeResult> analyzeText(String text) async {
    if (CLOUD_ANALYZE_URL.trim().isEmpty) {
      throw Exception("CLOUD_ANALYZE_URL girilmemiş.");
    }

    Uri uri = Uri.parse(CLOUD_ANALYZE_URL.trim());

    // Eğer kullanıcı /analyze yazmadıysa 404 alırsak otomatik deneriz.
    Future<http.Response> doPost(Uri u) {
      return http
          .post(
        u,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"text": text}),
      )
          .timeout(const Duration(seconds: 25));
    }

    http.Response res = await doPost(uri);

    if (res.statusCode == 404 && (uri.path.isEmpty || uri.path == "/")) {
      final retry = uri.replace(path: "/analyze");
      res = await doPost(retry);
      uri = retry;
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception("Cloud analyze hata: ${res.statusCode} - ${res.body}");
    }

    final body = jsonDecode(res.body);
    return AiAnalyzeResult.fromAnyJson(body);
  }
}
