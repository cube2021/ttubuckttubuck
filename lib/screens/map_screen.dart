import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:convert';
import '../services/park_service.dart';
import '../services/sync_service.dart';
import '../models/park.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MapMode { idle, gpsRecording, drawing }

class MapScreen extends StatefulWidget {
  final bool isDesignatingRoute;
  const MapScreen({super.key, this.isDesignatingRoute = false});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _titleController = TextEditingController();
  LatLng _currentPosition = const LatLng(37.5665, 126.9780);
  List<LatLng> _route = [];
  List<LatLng> _milestones = []; // 1km 마다 추가되는 평가 점
  MapMode _mode = MapMode.idle;
  double _distance = 0.0;
  int _elapsedSeconds = 0;
  StreamSubscription<Position>? _positionStream;
  Timer? _timer;
  bool _isSaving = false;

  // Park recommendations
  List<Park> _recommendedParks = [];
  bool _isSearchingParks = false;

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // 영구 거부 시 설정 다이얼로그 표시
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF161B22),
            title: const Text('위치 권한 필요', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: const Text(
              '산책 경로를 기록하려면 위치 권한이 필요합니다.\n설정에서 위치 권한을 허용해 주세요.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소', style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await Geolocator.openAppSettings();
                },
                child: const Text('설정 열기', style: TextStyle(color: Color(0xFF2EA043), fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
      return;
    }

    if (permission == LocationPermission.denied) return;

    try {
      // 마지막 알려진 위치를 먼저 즉시 적용 (2분 이내의 신선한 데이터만)
      final lastKnown = await Geolocator.getLastKnownPosition();
      final bool isFresh = lastKnown != null && 
          DateTime.now().difference(lastKnown.timestamp).inMinutes < 2;

      if (isFresh) {
        setState(() {
          _currentPosition = LatLng(lastKnown.latitude, lastKnown.longitude);
        });
        _mapController.move(_currentPosition, 15);
      }

      // 더 정확한 현재 위치로 업데이트 (타임아웃 10초)
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
        });
        _mapController.move(_currentPosition, 15);
      }
    } catch (e) {
      debugPrint('GPS 위치 획득 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('📍 GPS 신호를 찾을 수 없습니다. 잠시 후 다시 시도해 주세요.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: '재시도',
              textColor: Colors.white,
              onPressed: _determinePosition,
            ),
          ),
        );
      }
    }
  }

  // ───── GPS 기록 모드 ─────
  void _startGpsRecording() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⏳ GPS 신호를 잡는 중입니다... 잠시만 대기해주세요.'),
        duration: Duration(seconds: 2),
      ),
    );

    // GPS 신호 안정화를 위해 2초 대기
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

    setState(() {
      _mode = MapMode.gpsRecording;
      _currentPosition = LatLng(position.latitude, position.longitude);
      _route = [_currentPosition];
      _distance = 0.0;
      _elapsedSeconds = 0;
      _recommendedParks = [];
      _milestones = [];
    });
    
    _mapController.move(_currentPosition, 15);
    _startTimer();

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position pos) {
      final newPos = LatLng(pos.latitude, pos.longitude);
      setState(() {
        if (_route.isNotEmpty) {
          final stepDist = Geolocator.distanceBetween(
                _route.last.latitude, _route.last.longitude,
                newPos.latitude, newPos.longitude,
              ) / 1000;
          
          // 1km 구간 체크
          int oldKm = _distance.floor();
          _distance += stepDist;
          int newKm = _distance.floor();
          
          if (newKm > oldKm && newKm > 0) {
            _milestones.add(newPos);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('🎉 $newKm km 지점 통과! 평가 점이 기록되었습니다.'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        _currentPosition = newPos;
        _route.add(newPos);
      });
      _mapController.move(newPos, 15);
    });
  }

  // ───── 직접 그리기 모드 ─────
  void _startDrawing() {
    setState(() {
      _mode = MapMode.drawing;
      _route = [];
      _distance = 0.0;
      _recommendedParks = [];
    });
  }

  void _onMapTap(TapPosition _, LatLng latlng) {
    if (_mode != MapMode.drawing) return;
    setState(() {
      if (_route.isNotEmpty) {
        _distance += Geolocator.distanceBetween(
              _route.last.latitude, _route.last.longitude,
              latlng.latitude, latlng.longitude,
            ) / 1000;
      }
      _route.add(latlng);
    });
  }

  void _undoLastPoint() {
    if (_route.length <= 1) return;
    setState(() {
      _route.removeLast();
      _distance = 0;
      for (int i = 1; i < _route.length; i++) {
        _distance += Geolocator.distanceBetween(
              _route[i - 1].latitude, _route[i - 1].longitude,
              _route[i].latitude, _route[i].longitude,
            ) / 1000;
      }
    });
  }

  // ───── 타이머 ─────
  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsedSeconds++);
    });
  }

  String get _formattedTime {
    final m = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ───── 기록 종료 및 저장 ─────
  Future<void> _stopAndSave() async {
    _positionStream?.cancel();
    _timer?.cancel();
    
    if (_route.length < 2) {
      setState(() => _mode = MapMode.idle);
      return;
    }

    if (widget.isDesignatingRoute) {
      _titleController.text = '내 지정 산책 루트';
    } else {
      _titleController.text = '${DateTime.now().month}월 ${DateTime.now().day}일 산책';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('산책을 완료할까요? 🚶‍♂️', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _mode == MapMode.gpsRecording
                  ? '총 ${_distance.toStringAsFixed(2)}km / $_formattedTime'
                  : '경로 거리: ${_distance.toStringAsFixed(2)}km',
              style: const TextStyle(color: Color(0xFF2EA043), fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const Text('기록 이름', style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                hintText: '오늘의 산책 이름을 지어주세요',
                hintStyle: const TextStyle(color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2EA043))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _mode = MapMode.idle);
            },
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _saveRoute();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2EA043),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('저장하기', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveRoute() async {
    setState(() {
      _isSaving = true;
      _mode = MapMode.idle;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final routeJson = _route.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
        final milestonesJson = _milestones.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
        
        final recordData = {
          'user_id': user.id,
          'title': _titleController.text.trim(),
          'distance_km': double.parse(_distance.toStringAsFixed(3)),
          'duration_seconds': _elapsedSeconds,
          'route': routeJson,
          'milestones': milestonesJson,
        };
        
        if (widget.isDesignatingRoute) {
          final prefs = await SharedPreferences.getInstance();
          final String? routesString = prefs.getString('designated_routes_list_${user.id}');
          List<dynamic> routesList = [];
          if (routesString != null) {
            try {
              routesList = jsonDecode(routesString);
            } catch (_) {}
          }
          
          final String newRouteId = DateTime.now().millisecondsSinceEpoch.toString();
          final String routeName = _titleController.text.trim().isEmpty ? '내 지정 산책 루트' : _titleController.text.trim();
          
          final newRouteItem = {
            'id': newRouteId,
            'name': routeName,
            'route': routeJson,
          };
          
          routesList.add(newRouteItem);
          
          await prefs.setString('designated_routes_list_${user.id}', jsonEncode(routesList));
          await prefs.setString('designated_route_${user.id}', jsonEncode(routeJson));
          await prefs.setString('designated_route_id_${user.id}', newRouteId);
        } else {
          await SyncService().saveWalkRecord(recordData);
        }
      }

      setState(() {
        _isSaving = false;
        _route = [];
        _distance = 0.0;
        _elapsedSeconds = 0;
        _milestones = [];
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isDesignatingRoute ? '지정 루트가 성공적으로 설정되었습니다. 🎉' : '산책 기록이 성공적으로 저장되었습니다. 🎉'), 
            backgroundColor: const Color(0xFF2EA043)
          ),
        );
        if (widget.isDesignatingRoute) {
          Navigator.pop(context); // 지정 루트 모드일 땐 바로 이전 화면으로
        }
      }
    } catch (e) {
      debugPrint('저장 오류: $e');
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isDesignatingRoute ? '내 동네(선호 루트) 지정하기' : '산책 루트 추가 및 변경', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('산책 경로', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    Text(
                      _mode == MapMode.gpsRecording
                          ? '🔴 GPS 기록 중...'
                          : '내 동네의 산책 경로를 실시간 GPS로 기록해 보세요',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),

        // 지도
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _currentPosition,
                      initialZoom: 15,
                      onTap: _onMapTap,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                        subdomains: ['a', 'b', 'c', 'd'],
                        userAgentPackageName: 'com.ttubuk.ttubuk_ttubuk',
                      ),
                      // 내 경로
                      PolylineLayer(
                        polylines: _route.length >= 2 ? [
                          Polyline(
                            points: _route,
                            color: _mode == MapMode.drawing
                                ? Colors.blueAccent
                                : const Color(0xFF2EA043),
                            strokeWidth: 5,
                          ),
                        ] : <Polyline>[],
                      ),
                      // 공원 마커
                      MarkerLayer(
                        markers: [
                          // 현재 위치
                          Marker(
                            point: _currentPosition,
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
                          // 그리기 모드 경로 점
                          if (_mode == MapMode.drawing)
                            ..._route.map((p) => Marker(
                              point: p,
                              width: 16,
                              height: 16,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 1),
                                ),
                              ),
                            )),
                          // 공원 마커
                          ..._recommendedParks.map<Marker>((park) => Marker(
                            point: park.location,
                            width: 100,
                            height: 70,
                            child: GestureDetector(
                              onTap: () => _showParkDetail(park),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade700,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2)),
                                      ],
                                    ),
                                    child: const Icon(Icons.park, color: Colors.white, size: 18),
                                  ),
                                  const SizedBox(height: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      park.name,
                                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )),
                          // 1km 평가 점 마커
                          ..._milestones.asMap().entries.map((entry) => Marker(
                            point: entry.value,
                            width: 30,
                            height: 30,
                            child: Container(
                              decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
                              child: Center(
                                child: Text(
                                  '${entry.key + 1}',
                                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                            ),
                          )),
                        ],
                      ),
                    ],
                  ),
                  // 검색 중 오버레이
                  if (_isSearchingParks)
                    Container(
                      color: Colors.black54,
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Color(0xFF2EA043)),
                            SizedBox(height: 16),
                            Text('주변 공원을 찾고 있어요... 🌳', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  // 내 위치 버튼
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: FloatingActionButton(
                      mini: true,
                      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                      onPressed: _determinePosition,
                      child: const Icon(LucideIcons.locateFixed, color: Color(0xFF2EA043)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 하단 컨트롤 패널
        SafeArea(
          bottom: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                // 통계 카드
                if (_mode != MapMode.idle)
                  GlassmorphicContainer(
                    width: double.infinity,
                    height: 72,
                    borderRadius: 20,
                    blur: 20,
                    alignment: Alignment.center,
                    border: 1,
                    linearGradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.05)]),
                    borderGradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withOpacity(0.2), Colors.white.withOpacity(0.05)]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _statItem('거리', '${_distance.toStringAsFixed(2)} km', LucideIcons.footprints),
                          if (_mode == MapMode.gpsRecording)
                            _statItem('시간', _formattedTime, LucideIcons.timer),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                // 버튼
                if (_mode == MapMode.idle) ...[
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: _actionButton(
                            icon: LucideIcons.navigation,
                            label: 'GPS 기록',
                            color: const Color(0xFF2EA043),
                            onTap: _startGpsRecording,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: _actionButton(
                            icon: LucideIcons.edit3,
                            label: '직접 그리기',
                            color: Colors.blueAccent,
                            onTap: _startDrawing,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      if (_mode == MapMode.drawing) ...[
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _undoLastPoint,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white.withOpacity(0.1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(LucideIcons.undo2, size: 20),
                                  SizedBox(width: 8),
                                  Text('되돌리기', style: TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _stopAndSave,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: _isSaving
                                ? const CircularProgressIndicator(color: Colors.white)
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.check_circle_outline, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        _mode == MapMode.gpsRecording ? '기록 종료 및 저장' : '경로 완성 및 저장',
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF2EA043)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2EA043))),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _actionButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildParkList() {
    return Container(
      height: 140,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _recommendedParks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final park = _recommendedParks[i];
          return GestureDetector(
            onTap: () {
              _mapController.move(park.location, 16);
              _showParkDetail(park);
            },
            child: Container(
              width: 160,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(park.typeLabel, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(park.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Text('경로에서 ${park.distanceFromRoute.toInt()}m', style: const TextStyle(color: Color(0xFF2EA043), fontSize: 11)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showParkDetail(Park park) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(park.typeLabel, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 4),
            Text(park.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('경로에서 약 ${park.distanceFromRoute.toInt()}m 거리에 있어요.', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(LucideIcons.mapPin),
                label: const Text('지도에서 보기'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2EA043), padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
