// lib/app_config.dart
/// Tek yerden config yönetimi
/// - Google Places / Geocoding / Maps Web servisleri için API key
/// - Cloud Run AI analiz endpoint base URL
///
/// NOT: API KEY'i ve URL'i kendi değerlerinle değiştir.
const String GOOGLE_MAPS_API_KEY = "AIzaSyD4oMeOGCFYcg90FtPvJXKS_v22mq9x7j0";

/// Cloud Run base URL (sonunda / olmadan da olur)
const String CLOUD_ANALYZE_URL =
    "https://taknak-ai-engine-374428838042.europe-west1.run.app";
