import 'package:latlong2/latlong.dart';

class Park {
  final String name;
  final LatLng location;
  final String typeLabel;
  double distanceFromRoute;

  Park({
    required this.name,
    required this.location,
    required this.typeLabel,
    required this.distanceFromRoute,
  });
}
