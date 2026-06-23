import 'package:latlong2/latlong.dart';

class ParkRoute {
  final String id;
  final String name;
  final double distanceKm;
  final int durationMinutes;
  final List<LatLng> points;
  final String description;
  final String difficulty; // '쉬움', '보통', '어려움'

  ParkRoute({
    required this.id,
    required this.name,
    required this.distanceKm,
    required this.durationMinutes,
    required this.points,
    required this.description,
    this.difficulty = '보통',
  });
}
