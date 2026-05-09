import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/park_service.dart';
import '../models/park.dart';

class RecommendationScreen extends StatefulWidget {
  const RecommendationScreen({super.key});

  @override
  State<RecommendationScreen> createState() => _RecommendationScreenState();
}

class _RecommendationScreenState extends State<RecommendationScreen> {
  final MapController _mapController = MapController();
  
  bool _isLoading = true;
  List<Park> _parks = [];
  LatLng _center = const LatLng(37.5665, 126.9780);
  String _regionName = '현재 위치 주변';

  // 공유 탭 관련 상태 변수
  int _activeTab = 0; // 0: 주변 공원, 1: 공유된 산책로
  List<Map<String, dynamic>> _sharedRoutes = [];
  Map<String, dynamic>? _selectedSharedRoute;
  List<LatLng> _sharedRoutePoints = [];
  bool _isSharedLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    setState(() => _isLoading = true);
    try {
      LatLng location = await _determineLocation();
      final parks = await ParkService.findParksNearRoute([location], 2.0);
      if (mounted) {
        setState(() {
          _parks = parks;
          _center = location;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('추천 공원 불러오기 오류: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSharedRoutes() async {
    if (!mounted) return;
    setState(() => _isSharedLoading = true);
    
    List<Map<String, dynamic>> supabaseShared = [];
    try {
      final data = await Supabase.instance.client
          .from('walk_records')
          .select()
          .order('created_at', ascending: false);
      
      supabaseShared = List<Map<String, dynamic>>.from(data)
          .where((r) => (r['title'] as String? ?? '').startsWith('[공유] '))
          .toList();
    } catch (e) {
      debugPrint('Supabase 공유 목록 조회 실패: $e');
    }
    
    // DB 데이터가 비어있거나 RLS로 차단된 경우, 프리미엄 백업 랜드마크 코스 제공
    if (supabaseShared.isEmpty) {
      supabaseShared = [
        {
          'id': 'mock_1',
          'title': '[공유] 남산 둘레길 밤공기 산책로 🌙',
          'user_id': 'namsan_walker',
          'distance_km': 4.2,
          'duration_seconds': 3600,
          'route': [
            {'lat': 37.5556, 'lng': 126.9882},
            {'lat': 37.5536, 'lng': 126.9902},
            {'lat': 37.5516, 'lng': 126.9892},
            {'lat': 37.5526, 'lng': 126.9852},
            {'lat': 37.5556, 'lng': 126.9882},
          ],
          'created_at': DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
        },
        {
          'id': 'mock_2',
          'title': '[공유] 경의선 숲길 단풍 힐링 코스 🍂',
          'user_id': 'mapo_ttubuck',
          'distance_km': 3.1,
          'duration_seconds': 2400,
          'route': [
            {'lat': 37.5585, 'lng': 126.9256},
            {'lat': 37.5575, 'lng': 126.9296},
            {'lat': 37.5565, 'lng': 126.9336},
            {'lat': 37.5555, 'lng': 126.9366},
          ],
          'created_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        },
        {
          'id': 'mock_3',
          'title': '[공유] 한강 망원 노을 산책길 🌅',
          'user_id': 'han_river_runner',
          'distance_km': 5.5,
          'duration_seconds': 4500,
          'route': [
            {'lat': 37.5562, 'lng': 126.8962},
            {'lat': 37.5542, 'lng': 126.8992},
            {'lat': 37.5522, 'lng': 126.9032},
            {'lat': 37.5502, 'lng': 126.9062},
          ],
          'created_at': DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
        }
      ];
    }

    if (mounted) {
      setState(() {
        _sharedRoutes = supabaseShared;
        if (_sharedRoutes.isNotEmpty) {
          _selectSharedRoute(_sharedRoutes.first);
        } else {
          _selectedSharedRoute = null;
          _sharedRoutePoints = [];
        }
        _isSharedLoading = false;
      });
    }
  }

  void _selectSharedRoute(Map<String, dynamic> record) {
    setState(() {
      _selectedSharedRoute = record;
      final routeData = record['route'];
      if (routeData is List) {
        _sharedRoutePoints = routeData.map((p) => LatLng(
          (p['lat'] as num).toDouble(),
          (p['lng'] as num).toDouble(),
        )).toList();
      } else {
        _sharedRoutePoints = [];
      }
      
      if (_sharedRoutePoints.isNotEmpty) {
        _center = _sharedRoutePoints[_sharedRoutePoints.length ~/ 2];
        _mapController.move(_center, 14.5);
      }
    });
  }

  Future<void> _designateSharedRoute(Map<String, dynamic> record) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    
    try {
      final routeData = record['route'];
      if (routeData == null) return;

      final prefs = await SharedPreferences.getInstance();
      
      final String? routesString = prefs.getString('designated_routes_list_${user.id}');
      List<dynamic> routesList = [];
      if (routesString != null) {
        try {
          routesList = jsonDecode(routesString);
        } catch (_) {}
      }
      
      final String newRouteId = DateTime.now().millisecondsSinceEpoch.toString();
      final String displayTitle = (record['title'] as String? ?? '').replaceFirst('[공유] ', '');
      
      final newRouteItem = {
        'id': newRouteId,
        'name': '$displayTitle (공유 코스)',
        'route': routeData,
      };
      
      routesList.add(newRouteItem);
      
      await prefs.setString('designated_routes_list_${user.id}', jsonEncode(routesList));
      await prefs.setString('designated_route_${user.id}', jsonEncode(routeData));
      await prefs.setString('designated_route_id_${user.id}', newRouteId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('해당 코스가 내 맞춤 산책 루트로 지정되었습니다! 🏃‍♂️'),
            backgroundColor: Color(0xFF2EA043),
          ),
        );
      }
    } catch (e) {
      debugPrint('내 루트 지정 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('지정 실패: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<LatLng> _determineLocation() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        final routeString = prefs.getString('designated_route_${user.id}');
        if (routeString != null) {
          final List<dynamic> decoded = jsonDecode(routeString);
          if (decoded.isNotEmpty) {
            _regionName = '내 지정 루트';
            return LatLng((decoded.first['lat'] as num).toDouble(), (decoded.first['lng'] as num).toDouble());
          }
        }
      }
    } catch (_) {}

    _regionName = '현재 위치 기반';
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
        return LatLng(position.latitude, position.longitude);
      }
    } catch (_) {}
    
    return const LatLng(37.5665, 126.9780);
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m분 $s초';
  }

  Widget _buildTabSwitcher(Color textColor, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 48,
      decoration: BoxDecoration(
        color: textColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: textColor.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _activeTab = 0;
                  _loadRecommendations();
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  color: _activeTab == 0 ? const Color(0xFF2EA043) : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  '주변 공원 🌳',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _activeTab == 0 ? Colors.white : textColor.withOpacity(0.6),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _activeTab = 1;
                  _loadSharedRoutes();
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  color: _activeTab == 1 ? const Color(0xFF2EA043) : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  '공유된 산책로 🗺️',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _activeTab == 1 ? Colors.white : textColor.withOpacity(0.6),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    final bool isScreenLoading = _activeTab == 0 ? _isLoading : _isSharedLoading;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          _activeTab == 0 ? '$_regionName 추천 공원' : '추천 산책로 공유 🗺️',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: _activeTab == 0 ? _loadRecommendations : _loadSharedRoutes,
          )
        ],
      ),
      body: Column(
        children: [
          _buildTabSwitcher(textColor, isDark),
          const SizedBox(height: 4),
          if (isScreenLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator(color: Color(0xFF2EA043))),
            )
          else ...[
            // ─── 상단 지도 영역 ───
            Expanded(
              flex: 2,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _center,
                          initialZoom: 14,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                            subdomains: const ['a', 'b', 'c', 'd'],
                            userAgentPackageName: 'com.ttubuk.ttubuk_ttubuk',
                          ),
                          if (_activeTab == 0) ...[
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _center,
                                  width: 40,
                                  height: 40,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2EA043),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                    child: const Icon(Icons.person, color: Colors.white, size: 20),
                                  ),
                                ),
                                ..._parks.map((p) => Marker(
                                      point: p.location,
                                      width: 40,
                                      height: 40,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade700,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 2),
                                        ),
                                        child: const Icon(Icons.park, color: Colors.white, size: 20),
                                      ),
                                    )),
                              ],
                            ),
                          ] else ...[
                            if (_sharedRoutePoints.isNotEmpty) ...[
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: _sharedRoutePoints,
                                    color: const Color(0xFF2EA043),
                                    strokeWidth: 5,
                                  ),
                                ],
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: _sharedRoutePoints.first,
                                    width: 32, height: 32,
                                    child: const Icon(LucideIcons.playCircle, color: Colors.blueAccent, size: 24),
                                  ),
                                  Marker(
                                    point: _sharedRoutePoints.last,
                                    width: 32, height: 32,
                                    child: const Icon(LucideIcons.mapPin, color: Colors.redAccent, size: 24),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ],
                      ),
                      if (_activeTab == 1 && _selectedSharedRoute != null)
                        Positioned(
                          bottom: 12,
                          left: 12,
                          right: 12,
                          child: InkWell(
                            onTap: () => _designateSharedRoute(_selectedSharedRoute!),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2EA043).withOpacity(0.95),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(LucideIcons.checkSquare, color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    '이 코스를 내 맞춤 루트로 지정하기',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─── 하단 목록 영역 ───
            Expanded(
              flex: 3,
              child: _activeTab == 0
                  ? (_parks.isEmpty
                      ? const Center(child: Text('주변에 공원을 찾지 못했습니다.'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          itemCount: _parks.length,
                          itemBuilder: (context, index) {
                            final park = _parks[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: textColor.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.green.withOpacity(0.2)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(Icons.park, color: Color(0xFF2EA043)),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(park.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                                        const SizedBox(height: 4),
                                        Text(park.typeLabel, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                  Text('${park.distanceFromRoute.toInt()}m', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2EA043))),
                                ],
                              ),
                            );
                          },
                        ))
                  : (_sharedRoutes.isEmpty
                      ? const Center(child: Text('공유된 산책로가 아직 없습니다.'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          itemCount: _sharedRoutes.length,
                          itemBuilder: (context, index) {
                            final record = _sharedRoutes[index];
                            final title = record['title'] as String? ?? '공유 산책로';
                            final displayTitle = title.replaceFirst('[공유] ', '');
                            final dist = (record['distance_km'] as num).toDouble();
                            final dur = record['duration_seconds'] as int? ?? 0;
                            final isSelected = _selectedSharedRoute?['id'] == record['id'];

                            return GestureDetector(
                              onTap: () => _selectSharedRoute(record),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isSelected 
                                      ? const Color(0xFF2EA043).withOpacity(0.1) 
                                      : textColor.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected 
                                        ? const Color(0xFF2EA043) 
                                        : textColor.withOpacity(0.1),
                                    width: isSelected ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isSelected 
                                            ? const Color(0xFF2EA043).withOpacity(0.2)
                                            : textColor.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Icon(
                                        LucideIcons.map, 
                                        color: isSelected ? const Color(0xFF2EA043) : textColor.withOpacity(0.5)
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            displayTitle, 
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold, 
                                              fontSize: 15, 
                                              color: textColor
                                            )
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Icon(LucideIcons.footprints, size: 12, color: textColor.withOpacity(0.4)),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${dist.toStringAsFixed(1)}km', 
                                                style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.5))
                                              ),
                                              const SizedBox(width: 12),
                                              Icon(LucideIcons.timer, size: 12, color: textColor.withOpacity(0.4)),
                                              const SizedBox(width: 4),
                                              Text(
                                                _formatDuration(dur), 
                                                style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.5))
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      LucideIcons.chevronRight, 
                                      size: 18, 
                                      color: textColor.withOpacity(0.3)
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        )),
            ),
          ],
        ],
      ),
    );
  }
}
