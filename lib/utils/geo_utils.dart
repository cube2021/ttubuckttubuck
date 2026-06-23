import 'package:latlong2/latlong.dart';

List<LatLng> parseLatLngList(dynamic routeJson) {
  if (routeJson == null) return [];
  try {
    final list = routeJson as List;
    final result = <LatLng>[];
    for (final item in list) {
      if (item == null) continue;
      final latVal = item['lat'] ?? item['latitude'];
      final lngVal = item['lng'] ?? item['lon'] ?? item['longitude'];
      if (latVal == null || lngVal == null) continue;
      double? lat;
      double? lng;
      if (latVal is num) lat = latVal.toDouble(); else lat = double.tryParse(latVal.toString());
      if (lngVal is num) lng = lngVal.toDouble(); else lng = double.tryParse(lngVal.toString());
      if (lat == null || lng == null) continue;
      result.add(LatLng(lat, lng));
    }
    return result;
  } catch (_) {
    return [];
  }
}
