import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/park_service.dart';
import '../services/weather_transform_service.dart';
import '../services/hot_route_service.dart';
import '../services/gemini_service.dart';
import '../services/region_service.dart';
import '../services/user_preferences_service.dart';
import '../models/user_preferences.dart';
import '../models/park.dart';
import 'package:showcaseview/showcaseview.dart';
import '../utils/tutorial_keys.dart';
import '../widgets/park_review_sheet.dart';
import '../widgets/park_rating_badge.dart';

class RecommendationScreen extends StatefulWidget {
  const RecommendationScreen({super.key});

  @override
  State<RecommendationScreen> createState() => _RecommendationScreenState();
}

class _RecommendationScreenState extends State<RecommendationScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final MapController _mapController = MapController();
  
  bool _isLoading = true;
  Timer? _loadingTimer;
  String? _loadingMessage;

  List<Park> _parks = [];
  LatLng _center = const LatLng(37.5665, 126.9780);
  bool _hasRealLocation = false; // 실제 GPS 위치를 받았는지 여부
  String _regionName = '현재 위치 주변';

  // 실시간 GPS 스트림
  StreamSubscription<Position>? _positionStream;
  LatLng? _lastReloadedAt; // 마지막으로 공원을 갱신한 위치

  // 공유 탭 관련 상태 변수
  int _activeTab = 0;
  List<Map<String, dynamic>> _sharedRoutes = [];
  Map<String, dynamic>? _selectedSharedRoute;
  List<LatLng> _sharedRoutePoints = [];
  bool _isSharedLoading = false;

  // 핫 코스 관련 상태 변수
  List<HotWalkRoute> _hotRoutes = [];
  bool _isHotLoading = false;

  // 날씨 적합도 상태 변수
  String _weatherEvaluation = '';

  // AI 지역별 추천 상태 변수
  List<Park> _aiDongParks = [];
  List<Park> _aiGuParks = [];
  List<Park> _aiDoParks = [];
  bool _isAiRegionLoading = false;
  String _dongName = '';
  String _guName = '';
  String _doName = '';

  // 탐색 탭 내부 상태
  int _innerExploreTab = 0;

  // 좋아요 정보 로컬 저장
  Map<String, bool> _likedRoutes = {};
  Map<String, int> _localLikeCounts = {};

  @override
  void initState() {
    super.initState();
    _loadLikedData();
    _initGps(); // GPS 먼저 초기화, 위치 확인 후 데이터 로드
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    _positionStream?.cancel();
    super.dispose();
  }

  /// GPS 초기화 — lastKnown / getCurrentPosition / 스트림 세 소스 동시 시도
  /// 가장 먼저 오는 위치로 초기 로딩 시작, 이후 스트림이 실시간 업데이트
  Future<void> _initGps() async {
    setState(() {
      _isLoading = true;
      _startLoadingTimer();
    });

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() => _isLoading = false);
        _stopLoadingTimer();
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF161B22),
            title: const Text('위치 권한 필요', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            content: const Text(
              '주변 공원을 찾으려면 위치 권한이 필요합니다.\n설정에서 위치 권한을 허용해 주세요.',
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

    if (permission == LocationPermission.denied) {
      if (mounted) {
        setState(() => _isLoading = false);
        _stopLoadingTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('📍 위치 권한이 거부되었습니다.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // ── 세 소스 동시 시도, 가장 먼저 오는 위치 사용 ──
    final completer = Completer<LatLng>();
    void resolve(LatLng loc) {
      if (!completer.isCompleted) completer.complete(loc);
    }

    // ① lastKnown — 즉시 (캐시) - 2분 이내의 신선한 위치만 허용
    Geolocator.getLastKnownPosition().then((pos) {
      if (pos != null) {
        final isFresh = DateTime.now().difference(pos.timestamp).inMinutes < 2;
        if (isFresh) resolve(LatLng(pos.latitude, pos.longitude));
      }
    }).catchError((_) {});

    // ② getCurrentPosition — 네트워크 위치 (10초 타임아웃)
    Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10),
    ).then((pos) {
      resolve(LatLng(pos.latitude, pos.longitude));
    }).catchError((_) {});

    // ③ 실시간 스트림 — 첫 이벤트도 초기 위치 소스로 활용
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      ),
    ).listen(
      (Position pos) {
        if (!mounted) return;
        final newLatLng = LatLng(pos.latitude, pos.longitude);

        // 초기 위치 completer에도 전달
        resolve(newLatLng);

        // 실시간 지도 중심 업데이트
        setState(() {
          _center = newLatLng;
          _hasRealLocation = true;
        });
        try { _mapController.move(newLatLng, _mapController.camera.zoom); } catch (_) {}

        // 100m 이상 이동 시 공원 재검색
        if (_lastReloadedAt != null) {
          final moved = Geolocator.distanceBetween(
            _lastReloadedAt!.latitude, _lastReloadedAt!.longitude,
            newLatLng.latitude, newLatLng.longitude,
          );
          if (moved >= 100 && !_isLoading) {
            _lastReloadedAt = newLatLng;
            _loadRecommendations();
          }
        }
      },
      onError: (e) => debugPrint('GPS 스트림 오류: $e'),
    );

    // 셋 중 하나라도 성공하면 즉시 로딩 (최대 20초 대기)
    try {
      final initialLocation = await completer.future
          .timeout(const Duration(seconds: 20));
      if (mounted) {
        setState(() {
          _center = initialLocation;
          _hasRealLocation = true;
          _lastReloadedAt = initialLocation;
        });
        _loadRecommendations();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        _stopLoadingTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('📍 GPS 신호를 찾을 수 없습니다. 위치 서비스가 켜져 있는지 확인해 주세요.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: '재시도',
              textColor: Colors.white,
              onPressed: _initGps,
            ),
          ),
        );
      }
    }
  }

  void _startLoadingTimer() {
    _loadingTimer?.cancel();
    _loadingMessage = null;
    int ticks = 0;
    _loadingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      ticks++;
      if (ticks == 3) {
        if (mounted) setState(() => _loadingMessage = '데이터를 불러오는데에 조금 시간이 걸리고 있어요');
      } else if (ticks == 10) {
        if (mounted) setState(() => _loadingMessage = '데이터를 불러오는데에 생각보다 오래걸리고 있어요. 이 상태가 오랜 시간동안 지속된다면 앱을 재 실행 해주세요');
      }
    });
  }

  void _stopLoadingTimer() {
    _loadingTimer?.cancel();
    if (mounted) {
      setState(() => _loadingMessage = null);
    }
  }

  Future<void> _loadLikedData() async {
    final prefs = await SharedPreferences.getInstance();
    final likedString = prefs.getString('liked_routes') ?? '{}';
    final countsString = prefs.getString('liked_counts') ?? '{}';
    setState(() {
      _likedRoutes = Map<String, bool>.from(jsonDecode(likedString));
      _localLikeCounts = Map<String, int>.from(jsonDecode(countsString));
    });
  }

  Future<void> _toggleLike(String id) async {
    final isLiked = _likedRoutes[id] ?? false;
    setState(() {
      _likedRoutes[id] = !isLiked;
      _localLikeCounts[id] = (_localLikeCounts[id] ?? 0) + (isLiked ? -1 : 1);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('liked_routes', jsonEncode(_likedRoutes));
    await prefs.setString('liked_counts', jsonEncode(_localLikeCounts));
  }

  Future<void> _loadRecommendations() async {
    setState(() {
      _isLoading = true;
      _startLoadingTimer();
    });
    try {
      // GPS는 _initGps()에서 관리 — 여기선 현재 _center 값을 그대로 사용
      final location = _center;

      final parks = await ParkService.findParksNearRouteFast([location], 2.0);
      final weather = await WeatherTransformService.fetch(location.latitude, location.longitude);

      if (mounted) {
        setState(() {
          _parks = parks;
          _weatherEvaluation = weather.walkingScoreMessage;
          _isLoading = false;
        });
        _stopLoadingTimer();
        if (TutorialKeys.isTutorialRunning) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            TutorialKeys.mainLayoutKey.currentState?.startExploreTutorial();
          });
        }
        _loadAiRegionParks(location);
      }
    } catch (e) {
      debugPrint('추천 공원 불러오기 오류: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _stopLoadingTimer();
      }
    }
  }

  Future<void> _loadAiRegionParks(LatLng location) async {
    if (!mounted) return;
    setState(() => _isAiRegionLoading = true);
    try {
      final region = await RegionService.reverseGeocode(location);
      if (region != null) {
        final doName = region['do'] ?? '';
        final guName = region['gu'] ?? '';
        final dongName = region['dong'] ?? '';
        
        if (mounted) {
          setState(() {
            _doName = doName;
            _guName = guName;
            _dongName = dongName;
          });
        }
        
        final prefs = await UserPreferencesService.load();
        
        final results = await Future.wait([
          dongName.isNotEmpty ? GeminiService.getRegionParksAsList(regionName: '$doName $guName $dongName', preferences: prefs) : Future.value(<Park>[]),
          guName.isNotEmpty ? GeminiService.getRegionParksAsList(regionName: '$doName $guName', preferences: prefs) : Future.value(<Park>[]),
          doName.isNotEmpty ? GeminiService.getRegionParksAsList(regionName: doName, preferences: prefs) : Future.value(<Park>[]),
        ]);

        const dist = Distance();
        for (var list in results) {
          for (var park in list) {
            park.distanceFromRoute = dist.distance(location, park.location).toDouble();
          }
        }

        if (mounted) {
          setState(() {
            _aiDongParks = results[0];
            _aiGuParks = results[1];
            _aiDoParks = results[2];
            _isAiRegionLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isAiRegionLoading = false);
      }
    } catch (e) {
      debugPrint('AI 지역 추천 로드 실패: $e');
      if (mounted) setState(() => _isAiRegionLoading = false);
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
      if (TutorialKeys.isTutorialRunning) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          TutorialKeys.mainLayoutKey.currentState?.startExploreTutorial();
        });
      }
    }
  }

  Future<void> _loadHotRoutes() async {
    if (!mounted) return;
    setState(() => _isHotLoading = true);
    
    try {
      final data = await Supabase.instance.client
          .from('walk_records')
          .select()
          .order('likes', ascending: false)
          .limit(20);
      
      final hot = List<Map<String, dynamic>>.from(data)
          .where((r) => (r['title'] as String? ?? '').startsWith('[공유] '))
          .toList();
          
      if (mounted) {
        setState(() {
          _hotRoutes = hot.map((r) {
            return HotWalkRoute(
              title: r['title'] ?? '',
              displayTitle: (r['title'] ?? '').replaceFirst('[공유] ', ''),
              shareCount: r['likes'] ?? 0, // shareCount를 좋아요 수로 임시 사용
              avgDistanceKm: (r['distance_km'] as num?)?.toDouble() ?? 0.0,
              avgDurationSeconds: r['duration_seconds'] ?? 0,
            );
          }).toList();
          _isHotLoading = false;
        });
      }
    } catch (e) {
      debugPrint('핫 코스 로드 실패 (likes 정렬): $e');
      if (mounted) setState(() => _isHotLoading = false);
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
                  '공유 🗺️',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _activeTab == 1 ? Colors.white : textColor.withOpacity(0.6),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _activeTab = 2;
                  _loadHotRoutes();
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  color: _activeTab == 2 ? const Color(0xFF2EA043) : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  '핫 코스 🔥',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _activeTab == 2 ? Colors.white : textColor.withOpacity(0.6),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)}km';
    }
    return '${meters.toInt()}m';
  }

  Marker _buildCustomMarker(Park park, {bool isAi = false}) {
    final int minutes = (park.distanceFromRoute / 66.6).ceil();
    return Marker(
      point: park.location,
      width: 140,
      height: 80,
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isAi ? Colors.orange.withOpacity(0.9) : Colors.green.shade700.withOpacity(0.9),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(park.name, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${_formatDistance(park.distanceFromRoute)} (약 $minutes분)', style: const TextStyle(color: Colors.white, fontSize: 9)),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Container(
            decoration: BoxDecoration(
              color: isAi ? Colors.orange : Colors.green.shade700,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(isAi ? LucideIcons.sparkles : Icons.park, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    final bool isScreenLoading = _activeTab == 0 ? _isLoading : _isSharedLoading;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          _activeTab == 0 ? '주변 공원 🌳' : '추천 산책로 공유 🗺️',
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
          Showcase(
            key: TutorialKeys.exploreTabBarKey,
            description: '이 탭을 눌러 주변 공원을 보거나 다른 사람들이 공유한 산책로를 볼 수 있습니다!',
            child: _buildTabSwitcher(textColor, isDark),
          ),
          const SizedBox(height: 4),
          if (isScreenLoading)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF2EA043)),
                    if (_loadingMessage != null) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _loadingMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textColor.withOpacity(0.8),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else ...[
            // ─── 상단 지도 영역 ───
            if (_activeTab == 0 || (_activeTab == 1 && _selectedSharedRoute != null))
              Expanded(
                flex: 2,
                child: Showcase(
                  key: TutorialKeys.exploreMapKey,
                  description: '내 위치 또는 지정 루트 주변 공원과 공유 산책로를 지도로 봅니다.',
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
                                  if (_innerExploreTab == 0) ..._parks.map((p) => _buildCustomMarker(p, isAi: false)),
                                  if (_innerExploreTab == 1) ..._aiDongParks.map((p) => _buildCustomMarker(p, isAi: true)),
                                  if (_innerExploreTab == 2) ..._aiGuParks.map((p) => _buildCustomMarker(p, isAi: true)),
                                  if (_innerExploreTab == 3) ..._aiDoParks.map((p) => _buildCustomMarker(p, isAi: true)),
                                ],
                              ),
                            ] else if (_activeTab == 1 && _sharedRoutePoints.isNotEmpty) ...[
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
                        // GPS 재탐색 버튼
                        Positioned(
                          bottom: (_activeTab == 1 && _selectedSharedRoute != null) ? 60 : 12,
                          right: 12,
                          child: FloatingActionButton(
                            heroTag: 'gps_rescan_btn',
                            mini: true,
                            backgroundColor: const Color(0xFF2EA043),
                            onPressed: _initGps,
                            child: const Icon(Icons.my_location, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ),
              ),
            if (_activeTab == 0 || (_activeTab == 1 && _selectedSharedRoute != null)) const SizedBox(height: 16),

            // ─── 하단 목록 영역 ───
            Expanded(
              flex: _activeTab == 0 || (_activeTab == 1 && _selectedSharedRoute != null) ? 3 : 5,
              child: _buildListArea(textColor),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildListArea(Color textColor) {
    if (_activeTab == 0) return _buildParksList(textColor);
    if (_activeTab == 1) return _buildSharedRoutesList(textColor);
    return _buildHotRoutesList(textColor);
  }

  Widget _buildAiParkSection(String title, List<Park> parks, Color textColor) {
    if (parks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 4),
          child: Row(
            children: [
              const Icon(LucideIcons.sparkles, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
            ],
          ),
        ),
        ...parks.map((park) {
          final minutes = (park.distanceFromRoute / 66.6).ceil();
          return GestureDetector(
            onTap: () => _mapController.move(park.location, 16.0),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                    child: const Icon(LucideIcons.sparkles, color: Colors.orange),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(park.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                        const SizedBox(height: 4),
                        Text(park.openDate, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        if (park.hasToilet || park.hasParking) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (park.hasToilet) ...[
                                const Icon(Icons.wc, size: 12, color: Colors.blueAccent),
                                const SizedBox(width: 2),
                                Text('화장실', style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.6))),
                                const SizedBox(width: 6),
                              ],
                              if (park.hasParking) ...[
                                const Icon(Icons.local_parking, size: 12, color: Colors.indigo),
                                const SizedBox(width: 2),
                                Text('주차장', style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.6))),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${_formatDistance(park.distanceFromRoute)}\n약 $minutes분', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange)),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => ParkReviewSheet(parkName: park.name),
                          );
                        },
                        child: ParkRatingBadge(parkName: park.name, textColor: textColor),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(color: Colors.white12),
        ),
      ],
    );
  }

  Widget _buildInnerTab(int index, String title, Color textColor) {
    final isSelected = _innerExploreTab == index;
    return GestureDetector(
      onTap: () => setState(() => _innerExploreTab = index),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2EA043) : textColor.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? const Color(0xFF2EA043) : textColor.withOpacity(0.1)),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: isSelected ? Colors.white : textColor.withOpacity(0.7),
          ),
        ),
      ),
    );
  }

  Widget _buildParksList(Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_weatherEvaluation.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.cloudSun, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(child: Text(_weatherEvaluation, style: const TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              _buildInnerTab(0, '내 주변 🌳', textColor),
              if (_dongName.isNotEmpty) _buildInnerTab(1, _dongName, textColor),
              if (_guName.isNotEmpty) _buildInnerTab(2, _guName, textColor),
              if (_doName.isNotEmpty) _buildInnerTab(3, _doName, textColor),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            children: [
              if (_isAiRegionLoading)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator(color: Colors.orange)),
                )
              else ...[
                if (_innerExploreTab == 1 && _dongName.isNotEmpty) _buildAiParkSection('$_dongName 추천 공원', _aiDongParks, textColor),
                if (_innerExploreTab == 2 && _guName.isNotEmpty) _buildAiParkSection('$_guName 추천 공원', _aiGuParks, textColor),
                if (_innerExploreTab == 3 && _doName.isNotEmpty) _buildAiParkSection('$_doName 추천 공원', _aiDoParks, textColor),
              ],
              if (_innerExploreTab == 0) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, left: 4),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.mapPin, color: Color(0xFF2EA043), size: 20),
                      const SizedBox(width: 8),
                      Text('현재 내 주변 공원', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                    ],
                  ),
                ),
                if (_parks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16, left: 4),
                    child: Text('주변에 공원을 찾지 못했습니다.', style: TextStyle(color: textColor.withOpacity(0.5))),
                  )
                else
                  ..._parks.map((park) {
                    final minutes = (park.distanceFromRoute / 66.6).ceil();
                    return GestureDetector(
                      onTap: () => _mapController.move(park.location, 16.0),
                      child: Container(
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
                              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
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
                                  if (park.hasToilet || park.hasParking) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        if (park.hasToilet) ...[
                                          const Icon(Icons.wc, size: 12, color: Colors.blueAccent),
                                          const SizedBox(width: 2),
                                          Text('화장실', style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.6))),
                                          const SizedBox(width: 6),
                                        ],
                                        if (park.hasParking) ...[
                                          const Icon(Icons.local_parking, size: 12, color: Colors.indigo),
                                          const SizedBox(width: 2),
                                          Text('주차장', style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.6))),
                                        ],
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${_formatDistance(park.distanceFromRoute)}\n약 $minutes분', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF2EA043))),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () {
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => ParkReviewSheet(parkName: park.name),
                                    );
                                  },
                                  child: ParkRatingBadge(parkName: park.name, textColor: textColor),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSharedRoutesList(Color textColor) {
    if (_sharedRoutes.isEmpty) return const Center(child: Text('공유된 산책로가 아직 없습니다.'));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: _sharedRoutes.length,
      itemBuilder: (context, index) {
        final record = _sharedRoutes[index];
        final id = record['id'] as String? ?? '';
        final title = record['title'] as String? ?? '공유 산책로';
        final displayTitle = title.replaceFirst('[공유] ', '');
        final dist = (record['distance_km'] as num).toDouble();
        final dur = record['duration_seconds'] as int? ?? 0;
        final isSelected = _selectedSharedRoute?['id'] == id;
        
        final isLiked = _likedRoutes[id] ?? false;
        final likeCount = _localLikeCounts[id] ?? (record['likes'] as int? ?? 0);

        return GestureDetector(
          onTap: () => _selectSharedRoute(record),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF2EA043).withOpacity(0.1) : textColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? const Color(0xFF2EA043) : textColor.withOpacity(0.1),
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF2EA043).withOpacity(0.2) : textColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(LucideIcons.map, color: isSelected ? const Color(0xFF2EA043) : textColor.withOpacity(0.5)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayTitle, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(LucideIcons.footprints, size: 12, color: textColor.withOpacity(0.4)),
                          const SizedBox(width: 4),
                          Text('${dist.toStringAsFixed(1)}km', style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.5))),
                          const SizedBox(width: 12),
                          Icon(LucideIcons.timer, size: 12, color: textColor.withOpacity(0.4)),
                          const SizedBox(width: 4),
                          Text(_formatDuration(dur), style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.5))),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    IconButton(
                      icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: isLiked ? Colors.red : textColor.withOpacity(0.3), size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _toggleLike(id),
                    ),
                    const SizedBox(height: 4),
                    Text('$likeCount', style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.5))),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHotRoutesList(Color textColor) {
    if (_hotRoutes.isEmpty) return const Center(child: Text('인기 코스가 없습니다.'));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: _hotRoutes.length,
      itemBuilder: (context, index) {
        final route = _hotRoutes[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: textColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Text('${index + 1}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.orange)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(route.displayTitle, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                    const SizedBox(height: 4),
                    Text('좋아요: ${route.shareCount}개', style: const TextStyle(fontSize: 12, color: Colors.orange)),
                  ],
                ),
              ),
              const Icon(LucideIcons.flame, color: Colors.orange),
            ],
          ),
        );
      },
    );
  }
}
