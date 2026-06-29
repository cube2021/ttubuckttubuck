import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:ui' as ui;
import '../services/config.dart';
import '../services/park_service.dart';
import '../services/gemini_service.dart';
import '../models/park.dart';
import '../models/user_preferences.dart';
import '../models/weather_context.dart';
import '../services/user_preferences_service.dart';
import '../services/weather_transform_service.dart';
import '../widgets/recommendation_feedback_bar.dart';
import '../models/park_route.dart';
import '../services/park_route_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import '../utils/geo_utils.dart';
import 'package:showcaseview/showcaseview.dart';
import '../utils/tutorial_keys.dart';
import '../services/park_review_service.dart';
import '../widgets/park_review_sheet.dart';
import '../widgets/park_rating_badge.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String? selectedMood;
  List<Map<String, dynamic>> _records = [];
  String? _googleFitError; // Debug logger for native Google Fit issues
  Map<String, dynamic>? _selectedRecord;
  List<Park> _recommendedParks = [];
  bool isLoading = false;
  String _userName = ' ';
  String? _preferredRegion;
  bool _useDesignatedRoute = true;
  int _currentStep = 0; // 0: Start, 1: Mood, 2: Route, 3: Result
  String? _aiRecommendationText; // Gemini AI 추천 메시지
  UserPreferences _userPreferences = UserPreferences.defaults;
  WeatherContext _weatherContext = WeatherContext.fallback;
  List<LatLng> _currentRouteForMap = [];
  bool _isExperimentalEnabled = false; // 실험적 기능 설정
  final MapController _mapController = MapController();
  
  // Weather & Dust States
  String _weatherTemp = '--';
  String _weatherDesc = '날씨 정보 없음';
  String _locationName = '위치 찾는 중...';
  double? _pm10;
  double? _pm25;
  double? _pop; // 강수 확률
  IconData _weatherIcon = LucideIcons.cloud;
  Color _weatherIconColor = Colors.grey;

  // Google Fit State
  String _stepCount = '0';
  Timer? _googleFitTimer;

  final List<Map<String, dynamic>> moods = [
    {'id': 'happy', 'emoji': '😊', 'label': '신나요', 'color': Colors.amber, 'keyword': '활기찬'},
    {'id': 'calm', 'emoji': '🧘', 'label': '평온해요', 'color': Colors.lightBlueAccent, 'keyword': '고즈넉한'},
    {'id': 'tired', 'emoji': '😫', 'label': '지쳐요', 'color': Colors.grey, 'keyword': '편안한'},
    {'id': 'gloomy', 'emoji': '😔', 'label': '우울해요', 'color': Colors.blueGrey, 'keyword': '기분전환에 좋은'},
  ];

  // Attendance State
  bool _hasCheckedInToday = false;
  int _attendanceStreak = 0;

  @override
  void initState() {
    super.initState();
    _fetchUserName();
    _fetchWeather();
    _fetchRecords();
    _initGoogleFitSteps();
    _checkAttendanceStatus();
    _loadExperimentalSetting();
    NotificationService().scheduleDailyAttendanceNotification();
  }

  Future<void> _loadExperimentalSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isExperimentalEnabled = prefs.getBool('experimental_park_recommendation') ?? false;
      });
    }
  }

  Future<void> _checkAttendanceStatus() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final today = DateTime.now().toString().split(' ')[0];
    try {
      final rows = await Supabase.instance.client
          .from('attendance_records')
          .select('check_in_date, streak')
          .eq('user_id', user.id)
          .order('check_in_date', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        final last = rows[0];
        if (mounted) {
          setState(() {
            _hasCheckedInToday = last['check_in_date'] == today;
            _attendanceStreak = last['streak'] as int? ?? 0;
          });
        }
      }
    } catch (e) {
      debugPrint('출석 상태 로드 실패: $e');
    }
  }

  Future<void> _performAttendanceCheck() async {
    if (_hasCheckedInToday) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final today = DateTime.now().toString().split(' ')[0];
    final yesterday = DateTime.now().subtract(const Duration(days: 1)).toString().split(' ')[0];

    try {
      // 서버에서 마지막 출석 데이터 조회
      final rows = await Supabase.instance.client
          .from('attendance_records')
          .select('check_in_date, streak')
          .eq('user_id', user.id)
          .order('check_in_date', ascending: false)
          .limit(1);

      int newStreak = 1;
      if (rows.isNotEmpty) {
        final last = rows[0];
        if (last['check_in_date'] == today) return; // 이미 쯄서
        if (last['check_in_date'] == yesterday) {
          newStreak = (last['streak'] as int? ?? 0) + 1;
        }
      }

      // Supabase에 출석 기록
      await Supabase.instance.client.from('attendance_records').insert({
        'user_id': user.id,
        'check_in_date': today,
        'streak': newStreak,
      });

      if (mounted) {
        setState(() {
          _hasCheckedInToday = true;
          _attendanceStreak = newStreak;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 출석 완료! 연속 ${newStreak}일 출석했습니다.'),
            backgroundColor: const Color(0xFF2EA043),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('출석 처리 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('출석 처리 중 오류가 발생했습니다. 다시 시도해 주세요.'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _initGoogleFitSteps() {
    // 앱 진입 시 최초 1회 즉시 로드
    _fetchStepsFromNativeSensor();

    // 10초마다 실시간 원시 센서 값 초고속 동기화 (로컬 쿼리라 배터리 무리 제로!)
    _googleFitTimer?.cancel();
    _googleFitTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchStepsFromNativeSensor();
    });
  }

  Future<void> _fetchStepsFromNativeSensor() async {
    const channel = MethodChannel('com.ttubuk.ttubuk_ttubuk/steps');
    try {
      // 1. 기기에 하드웨어 만보기 센서가 실존하는지 확인
      final bool isAvailable = await channel.invokeMethod<bool>('isSensorAvailable') ?? false;
      if (!isAvailable) {
        if (mounted) {
          setState(() {
            _googleFitError = '기기에 만보기 센서 하드웨어가 탑재되어 있지 않습니다.';
          });
        }
        return;
      }

      // 2. 부팅 이후 총 누적 원시 걸음수 수신
      final int rawSteps = await channel.invokeMethod<int>('getRawSensorSteps') ?? 0;
      
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toString().split(' ')[0]; // yyyy-MM-dd
      
      // 3. 로컬 저장소에서 오늘 날짜의 기준점(Base) 가져오기
      int? baseSteps = prefs.getInt('native_base_steps_$today');
      
      // 4. 만약 기준점이 없거나 폰이 재부팅되어 센서 누적값이 초기화된 경우
      if (baseSteps == null || rawSteps < baseSteps || baseSteps == 0) {
        // 현재 원시값을 오늘의 기준점으로 등록!
        await prefs.setInt('native_base_steps_$today', rawSteps);
        baseSteps = rawSteps;
      }

      // 5. 오늘 걸음수 산출: 현재 누적값 - 오늘 시작 지점
      final int todaySteps = rawSteps - baseSteps;

      if (mounted) {
        setState(() {
          _stepCount = todaySteps.toString();
          _googleFitError = null; // 성공 시 에러 배너 클리어
        });
        debugPrint('로컬 물리 센서 갱신 성공: $todaySteps 걸음 (raw: $rawSteps, base: $baseSteps)');
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _googleFitError = '하드웨어 센서 에러 [${e.code}]: ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _googleFitError = '센서 조회 예외: $e';
        });
      }
    }
  }

  Future<void> _loadBackupSteps() async {
    if (!mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toString().split(' ')[0];
      final savedSteps = prefs.getInt('daily_steps_$today') ?? 0;
      setState(() {
        _stepCount = savedSteps.toString();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _googleFitTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchRecords() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final data = await Supabase.instance.client
          .from('walk_records')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(5);
      if (mounted) setState(() => _records = List<Map<String, dynamic>>.from(data));
    } catch (e) { debugPrint('기록 불러오기 실패: $e'); }
  }

  Future<void> _fetchUserName() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final data = await Supabase.instance.client.from('profiles').select('full_name').eq('id', user.id).single();
        if (mounted) {
          setState(() {
            _userName = (data['full_name']?.toString().isNotEmpty == true) ? data['full_name'] : '유저';
          });
        }
      }
    } catch (e) { 
      debugPrint("이름 불러오기 실패: $e"); 
      if (mounted) setState(() => _userName = '유저');
    }
  }

  Future<void> _fetchWeather() async {
    try {
      // 위치 권한 먼저 확인 및 요청
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      Position? position;
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        // lastKnown 가져오기 (2분 이내의 신선한 데이터만 즉시 사용)
        final lastKnown = await Geolocator.getLastKnownPosition();
        final bool isFresh = lastKnown != null && 
            DateTime.now().difference(lastKnown.timestamp).inMinutes < 2;

        if (isFresh) {
          position = lastKnown;
        }

        // 백그라운드에서 최신 위치로 날씨 갱신 (UI 블로킹 없음)
        Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
        ).then((freshPos) {
          if (mounted) {
            _fetchWeatherFromCoords(freshPos.latitude, freshPos.longitude);
          }
        }).catchError((_) {});

        // 신선한 lastKnown이 없는 경우(최초 설치 또는 오래됨) 블로킹 대기
        if (position == null) {
          try {
            position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 15),
            );
          } catch (_) {}
        }
      }

      final lat = position?.latitude ?? 37.5665;
      final lon = position?.longitude ?? 126.9780;
      final bool usingFallback = position == null;

      await _fetchWeatherFromCoords(lat, lon, usingFallback: usingFallback);
    } catch (e) {
      debugPrint("날씨/미세먼지 불러오기 실패: $e");
    }
  }

  Future<void> _fetchWeatherFromCoords(double lat, double lon, {bool usingFallback = false}) async {
    try {
      final weatherUrl = 'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=${AppConfig.weatherApiKey}&units=metric&lang=kr';
      final airUrl = 'https://api.openweathermap.org/data/2.5/air_pollution?lat=$lat&lon=$lon&appid=${AppConfig.weatherApiKey}';

      final results = await Future.wait([
        http.get(Uri.parse(weatherUrl)),
        http.get(Uri.parse(airUrl)),
      ]);
      final weatherRes = results[0];
      final airRes = results[1];

      if (weatherRes.statusCode == 200 && mounted) {
        final data = json.decode(weatherRes.body);
        String krLocationName = usingFallback ? '서울' : (data['name'] ?? '알 수 없음');
        if (!usingFallback) {
          try {
            final nomUrl = 'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=json&accept-language=ko';
            final nomRes = await http.get(Uri.parse(nomUrl), headers: {'User-Agent': 'ttubuk_ttubuk_app'});
            if (nomRes.statusCode == 200) {
              final nomData = json.decode(utf8.decode(nomRes.bodyBytes));
              if (nomData['address'] != null) {
                final addr = nomData['address'];
                krLocationName = addr['suburb'] ?? addr['town'] ?? addr['borough'] ?? addr['city'] ?? data['name'];
              }
            }
          } catch (_) {}
        }
        if (mounted) {
          setState(() {
            _weatherTemp = data['main']['temp'].toStringAsFixed(1);
            _weatherDesc = data['weather'][0]['description'];
            _locationName = krLocationName;
            _setWeatherIcon(data['weather'][0]['main']);
          });
        }
      }

      if (airRes.statusCode == 200 && mounted) {
        final data = json.decode(airRes.body);
        if (data['list'] != null && data['list'].isNotEmpty) {
          final components = data['list'][0]['components'];
          if (mounted) {
            setState(() {
              _pm10 = (components['pm10'] as num?)?.toDouble();
              _pm25 = (components['pm2_5'] as num?)?.toDouble();
            });
          }
        }
      }
    } catch (e) {
      debugPrint("날씨 API 호출 실패: $e");
    }
  }

  void _setWeatherIcon(String main) {
    switch (main.toLowerCase()) {
      case 'clear': _weatherIcon = LucideIcons.sun; _weatherIconColor = Colors.amber; break;
      case 'clouds': _weatherIcon = LucideIcons.cloud; _weatherIconColor = Colors.white70; break;
      case 'rain': case 'drizzle': _weatherIcon = LucideIcons.cloudRain; _weatherIconColor = Colors.blue; break;
      case 'snow': _weatherIcon = LucideIcons.snowflake; _weatherIconColor = Colors.lightBlueAccent; break;
      case 'thunderstorm': _weatherIcon = LucideIcons.cloudLightning; _weatherIconColor = Colors.purpleAccent; break;
      default: _weatherIcon = LucideIcons.cloud; _weatherIconColor = Colors.grey;
    }
  }

  List<LatLng> _parseRoute(dynamic routeJson) {
    return parseLatLngList(routeJson);
  }

  Future<List<LatLng>> _getDesignatedRoute() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        final routeString = prefs.getString('designated_route_${user.id}');
        if (routeString != null) {
          final List<dynamic> decoded = jsonDecode(routeString);
          return parseLatLngList(decoded);
        }
      }
      return [];
    } catch (e) {
      debugPrint("지정 루트 불러오기 실패: $e");
      return [];
    }
  }

  void _handleRecommend() async {
    setState(() { isLoading = true; _currentStep = 3; _recommendedParks = []; _aiRecommendationText = null; });
    try {


      List<LatLng> route;
      double dist;
      
      if (!_useDesignatedRoute && _selectedRecord != null) {
        route = _parseRoute(_selectedRecord!['route']);
        dist = (_selectedRecord!['distance_km'] as num?)?.toDouble() ?? 1.0;
      } else {
        route = await _getDesignatedRoute();
        if (route.isEmpty) {
          try {
            Position? position = await Geolocator.getLastKnownPosition();
            if (position == null) {
              position = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.medium,
                timeLimit: const Duration(seconds: 3),
              );
            }
            route = [LatLng(position.latitude, position.longitude)];
          } catch (_) {
            route = [const LatLng(37.5665, 126.9780)];
          }
        }
        dist = 1.0;
      }
      
      _userPreferences = await UserPreferencesService.load();
      final anchor = route.isNotEmpty ? route.first : const LatLng(37.5665, 126.9780);
      _weatherContext = await WeatherTransformService.fetch(
        anchor.latitude,
        anchor.longitude,
      );

      final parks = await ParkService.findParksNearRouteFast(
        route,
        dist,
        moodId: selectedMood,
        weather: _weatherContext,
      );

      // 주변 공원은 AI 추천 없이 단순 정보만 보여줍니다.
      String? aiText;
      aiText = null;

      if (mounted) setState(() { 
        _recommendedParks = parks.take(5).toList(); 
        _aiRecommendationText = aiText;
        _currentRouteForMap = route;
        isLoading = false; 
      });
    } catch (e) {
      debugPrint('추천 오류: $e');
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('추천 생성 중 오류가 발생했습니다: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 50, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(textColor, isDark),
            const SizedBox(height: 16),
            _buildExtraStatsRow(textColor, isDark),
            const SizedBox(height: 32),
            _buildCurrentStepContent(textColor, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color textColor, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('안녕하세요,', style: TextStyle(fontSize: 18, color: textColor.withOpacity(0.6))),
            Text('$_userName님!', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2EA043))),
          ],
        ),
        _buildWeatherBadge(textColor, isDark),
      ],
    );
  }

  Widget _buildWeatherBadge(Color textColor, bool isDark) {
    return Showcase(
      key: TutorialKeys.homeWeatherKey,
      description: '오늘의 날씨와 기온을 한눈에 확인하세요!',
      child: GlassmorphicContainer(
        width: 110, height: 50, borderRadius: 12, blur: 20, alignment: Alignment.center, border: 1,
        linearGradient: LinearGradient(colors: [textColor.withOpacity(0.1), textColor.withOpacity(0.05)]),
        borderGradient: LinearGradient(colors: [textColor.withOpacity(0.2), textColor.withOpacity(0.05)]),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_weatherIcon, size: 20, color: _weatherIconColor),
            const SizedBox(width: 8),
            Text('$_weatherTemp°C', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildExtraStatsRow(Color textColor, bool isDark) {
    String pmLevel = '확인 중';
    Color pmColor = Colors.grey;
    if (_pm10 != null) {
      if (_pm10! <= 30) { pmLevel = '좋음'; pmColor = Colors.blue; }
      else if (_pm10! <= 80) { pmLevel = '보통'; pmColor = Colors.green; }
      else if (_pm10! <= 150) { pmLevel = '나쁨'; pmColor = Colors.orange; }
      else { pmLevel = '매우 나쁨'; pmColor = Colors.red; }
    }

    return Column(
      children: [
        if (_googleFitError != null) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.alertCircle, size: 16, color: Colors.redAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _googleFitError!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.mapPin, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(_locationName, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: pmColor.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                  child: Text('미세 $pmLevel', style: TextStyle(color: pmColor, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: textColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.footprints, size: 12, color: Color(0xFF2EA043)),
                      const SizedBox(width: 4),
                      Text('$_stepCount 걸음', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Attendance UI
        GestureDetector(
          onTap: _performAttendanceCheck,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: _hasCheckedInToday
                  ? LinearGradient(colors: [const Color(0xFF2EA043).withOpacity(0.8), const Color(0xFF2EA043)])
                  : LinearGradient(colors: [textColor.withOpacity(0.05), textColor.withOpacity(0.1)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _hasCheckedInToday ? Colors.transparent : textColor.withOpacity(0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      _hasCheckedInToday ? LucideIcons.checkCircle2 : LucideIcons.calendarCheck,
                      color: _hasCheckedInToday ? Colors.white : textColor,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _hasCheckedInToday ? '오늘 출석을 완료했어요!' : '오늘의 출석을 체크해주세요',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _hasCheckedInToday ? Colors.white : textColor,
                      ),
                    ),
                  ],
                ),
                if (_hasCheckedInToday)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                    child: Text('$_attendanceStreak일 연속', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  )
                else
                  Icon(LucideIcons.chevronRight, size: 16, color: textColor.withOpacity(0.5)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentStepContent(Color textColor, bool isDark) {
    switch (_currentStep) {
      case 0: return _buildStartStep(textColor, isDark);
      case 1: return _buildMoodStep(textColor, isDark);
      case 2: return _buildRouteStep(textColor, isDark);
      case 3: return _buildResultStep(textColor, isDark);
      default: return _buildStartStep(textColor, isDark);
    }
  }

  Widget _buildStartStep(Color textColor, bool isDark) {
    return FutureBuilder<List<LatLng>>(
      future: _getDesignatedRoute(),
      builder: (context, snapshot) {
        final hasRoute = snapshot.hasData && snapshot.data!.isNotEmpty && snapshot.data!.length >= 2;
        final routePoints = hasRoute ? snapshot.data! : <LatLng>[];

        return Center(
          child: Column(
            children: [
              const SizedBox(height: 20),
              Showcase(
                key: TutorialKeys.homeRouteKey,
                description: '지정된 산책 루트를 불러오고, AI 분석을 시작하는 공간입니다.',
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: textColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF2EA043).withOpacity(0.3)),
                  ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(LucideIcons.mapPin, size: 20, color: Color(0xFF2EA043)),
                        const SizedBox(width: 8),
                        Text('내 지정 산책 루트', style: TextStyle(fontSize: 14, color: textColor.withOpacity(0.6), fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (hasRoute) ...[
                      Container(
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: routePoints[0],
                              initialZoom: 14.5,
                              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                                subdomains: const ['a', 'b', 'c', 'd'],
                                userAgentPackageName: 'com.ttubuk.ttubuk_ttubuk',
                              ),
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: routePoints,
                                    color: const Color(0xFF2EA043),
                                    strokeWidth: 4,
                                  ),
                                ],
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: routePoints.first,
                                    width: 32, height: 32,
                                    child: const Icon(LucideIcons.playCircle, color: Colors.blueAccent, size: 24),
                                  ),
                                  Marker(
                                    point: routePoints.last,
                                    width: 32, height: 32,
                                    child: const Icon(LucideIcons.mapPin, color: Colors.redAccent, size: 24),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          '나만의 맞춤 코스',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                        ),
                      ),
                    ] else ...[
                      Container(
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: textColor.withOpacity(0.02),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: textColor.withOpacity(0.1)),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.map, size: 40, color: textColor.withOpacity(0.2)),
                              const SizedBox(height: 12),
                              Text(
                                '지정된 산책 루트가 없습니다.\n설정 -> 내 루트 설정에서 루트를 지정해 주세요.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: textColor.withOpacity(0.4), fontSize: 13, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
              SizedBox(
                width: double.infinity, height: 64,
                child: ElevatedButton(
                  onPressed: hasRoute
                      ? () {
                          setState(() {
                            _useDesignatedRoute = true;
                            _currentStep = 1; // 기분 선택 단계로 이동
                          });
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2EA043),
                    disabledBackgroundColor: Colors.grey.withOpacity(0.3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('지정된 루트로 분석 시작', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMoodStep(Color textColor, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepIndicator(1, '지금 기분은 어떠신가요?', textColor),
        const SizedBox(height: 24),
        _buildMoodGrid(textColor, isDark),
        const SizedBox(height: 40),
        _buildNavigationButtons(onNext: selectedMood == null ? null : _handleRecommend),
      ],
    );
  }

  Widget _buildRouteStep(Color textColor, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepIndicator(2, '어디를 배경으로 분석할까요?', textColor),
        const SizedBox(height: 24),
        _buildRouteSelector(textColor, isDark),
        const SizedBox(height: 40),
        _buildNavigationButtons(onNext: _selectedRecord == null ? null : _handleRecommend),
      ],
    );
  }

  Widget _buildResultStep(Color textColor, bool isDark) {
    if (isLoading) {
      return Center(
        child: Column(
          children: [
            const SizedBox(height: 100),
            const CircularProgressIndicator(color: Color(0xFF2EA043)),
            const SizedBox(height: 24),
            Text('AI가 최적의 장소를 분석 중입니다...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 8),
            Text('기분과 날씨, 경로 데이터를 대조하고 있어요.', style: TextStyle(color: textColor.withOpacity(0.5))),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildResultHeader(textColor, isDark),
        if (_aiRecommendationText != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF2EA043).withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2EA043).withOpacity(0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(LucideIcons.sparkles, color: Color(0xFF2EA043), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AI 맞춤 추천 코스 가이드',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF2EA043)),
                      ),
                      const SizedBox(height: 8),
                      _buildFormattedText(_aiRecommendationText!, textColor),
                      RecommendationFeedbackBar(
                        parkName: _recommendedParks.isNotEmpty
                            ? _recommendedParks.first.name
                            : null,
                        moodId: selectedMood,
                        onFeedbackRecorded: _handleRecommend,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (_recommendedParks.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(40), child: Text('주변에 추천할 만한 공원을 찾지 못했어요 😢', style: TextStyle(color: textColor))))
        else ...[
          // 지도 미리보기 추가
          Container(
            height: 240,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentRouteForMap.isNotEmpty ? _currentRouteForMap[0] : const LatLng(37.5665, 126.9780),
                  initialZoom: 14,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.ttubuk.ttubuk_ttubuk',
                  ),
                  if (_currentRouteForMap.length >= 2)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _currentRouteForMap,
                          color: const Color(0xFF2EA043),
                          strokeWidth: 4,
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: _recommendedParks.map<Marker>((p) {
                      final distM = p.distanceFromRoute;
                      final distKm = distM / 1000.0;
                      // 도보 속도 4km/h 기준 소요 시간(분)
                      final walkMin = (distM / (4000 / 60)).ceil();
                      final distLabel = distKm >= 1.0
                          ? '${distKm.toStringAsFixed(1)}km'
                          : '${distM.toInt()}m';
                      return Marker(
                        point: p.location,
                        width: 120,
                        height: 72,
                        alignment: Alignment.bottomCenter,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 말풍선 라벨
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.green.shade800,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    p.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$distLabel · 도보 $walkMin분',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.85),
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 말풍선 꼬리
                            CustomPaint(
                              size: const Size(10, 5),
                              painter: _BubbleTailPainter(Colors.green.shade800),
                            ),
                            // 아이콘 마커
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.green.shade700,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.park, color: Colors.white, size: 16),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const Text('주변 산책 장소', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ..._recommendedParks.map((p) => _buildParkCard(p, textColor, isDark)),
        ],
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity, height: 56,
          child: OutlinedButton(
            onPressed: () => setState(() { _currentStep = 0; selectedMood = null; _selectedRecord = null; _recommendedParks = []; }),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF2EA043)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            child: const Text('다시 추천 받기', style: TextStyle(color: Color(0xFF2EA043), fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Future<void> _designateParkRoute(ParkRoute route, String parkName) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final String? routesString = prefs.getString('designated_routes_list_${user.id}');
      List<dynamic> routesList = [];
      if (routesString != null) {
        try {
          routesList = jsonDecode(routesString);
        } catch (_) {}
      }
      
      final String newRouteId = DateTime.now().millisecondsSinceEpoch.toString();
      
      final routeData = route.points.map((p) => {
        'lat': p.latitude,
        'lng': p.longitude,
      }).toList();
      
      final newRouteItem = {
        'id': newRouteId,
        'name': '$parkName - ${route.name}',
        'route': routeData,
      };
      
      routesList.add(newRouteItem);
      
      await prefs.setString('designated_routes_list_${user.id}', jsonEncode(routesList));
      await prefs.setString('designated_route_${user.id}', jsonEncode(routeData));
      await prefs.setString('designated_route_id_${user.id}', newRouteId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${route.name} 코스가 내 맞춤 산책 루트로 지정되었습니다! 🏃‍♂️'),
            backgroundColor: const Color(0xFF2EA043),
            behavior: SnackBarBehavior.floating,
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

  void _showRouteSelectionSheet(Park park, Color textColor, bool isDark) {
    final routes = park.routes;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.85,
              expand: false,
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40, height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: textColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2EA043).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.park, color: Color(0xFF2EA043)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  park.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: textColor,
                                  ),
                                ),
                                Text(
                                  park.typeLabel,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: textColor.withOpacity(0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '🌳 추천 코스 가이드',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (routes.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: Text('이 공원의 추천 루트가 아직 없습니다.')),
                        )
                      else
                        ...routes.map((route) {
                          Color diffColor = Colors.green;
                          if (route.difficulty == '보통') diffColor = Colors.orange;
                          if (route.difficulty == '어려움') diffColor = Colors.redAccent;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: textColor.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: textColor.withOpacity(0.08)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          route.name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: textColor,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: diffColor.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          route.difficulty,
                                          style: TextStyle(
                                            color: diffColor,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.directions_walk, size: 14, color: textColor.withOpacity(0.4)),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${route.distanceKm}km',
                                        style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.5)),
                                      ),
                                      const SizedBox(width: 14),
                                      Icon(Icons.access_time, size: 14, color: textColor.withOpacity(0.4)),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${route.durationMinutes}분 소요',
                                        style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.5)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    route.description,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.5,
                                      color: textColor.withOpacity(0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 42,
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _designateParkRoute(route, park.name);
                                      },
                                      icon: const Icon(Icons.check_circle_outline, color: Colors.white, size: 16),
                                      label: const Text(
                                        '이 코스로 산책 시작 (대표 지정)',
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF2EA043),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        elevation: 0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildStepIndicator(int step, String title, Color textColor) {
    return Row(
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: const Color(0xFF2EA043), borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Text('$step', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 12),
        Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
      ],
    );
  }

  Widget _buildNavigationButtons({VoidCallback? onNext}) {
    return Row(
      children: [
        Expanded(
          flex: 1,
          child: SizedBox(
            height: 56,
            child: TextButton(
              onPressed: () => setState(() => _currentStep--),
              child: const Text('이전', style: TextStyle(color: Colors.grey)),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2EA043), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: Text(onNext == _handleRecommend ? '분석 시작' : '다음', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMoodGrid(Color textColor, bool isDark) {
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.5),
      itemCount: moods.length,
      itemBuilder: (context, index) {
        final mood = moods[index];
        final isSelected = selectedMood == mood['id'];
        return GestureDetector(
          onTap: () => setState(() => selectedMood = mood['id']),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected ? (mood['color'] as Color).withOpacity(0.2) : textColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20), border: Border.all(color: isSelected ? mood['color'] as Color : textColor.withOpacity(0.1), width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(mood['emoji'], style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 4),
                Text(mood['label'], style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: textColor)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRouteSelector(Color textColor, bool isDark) {
    if (_records.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32), decoration: BoxDecoration(color: textColor.withOpacity(0.05), borderRadius: BorderRadius.circular(24)),
        child: Center(child: Text('기존 산책 경로가 없습니다.\n먼저 산책을 기록해보세요!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
      );
    }
    return Column(
      children: _records.map((record) {
        final isSelected = _selectedRecord == record;
        final date = DateTime.parse(record['created_at']).toLocal();
        final dist = (record['distance_km'] as num?)?.toDouble() ?? 0.0;
        return GestureDetector(
          onTap: () => setState(() => _selectedRecord = record),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF2EA043).withOpacity(0.1) : textColor.withOpacity(0.03),
              borderRadius: BorderRadius.circular(20), border: Border.all(color: isSelected ? const Color(0xFF2EA043) : textColor.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.mapPin, size: 20, color: textColor),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(record['title'] ?? '${date.month}월 ${date.day}일 기록', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                  const Text('산책로', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ])),
                if (isSelected) const Icon(Icons.check_circle, color: Color(0xFF2EA043)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildResultHeader(Color textColor, bool isDark) {
    final moodMap = moods.firstWhere((m) => m['id'] == selectedMood, orElse: () => moods.first);
    final moodLabel = moodMap['label'];
    final score = _weatherContext.walkingScore;
    final heatIdx = _weatherContext.heatIndex;
    final humidity = _weatherContext.humidity;

    // 산책 지수 색상
    Color scoreColor;
    if (score >= 75) scoreColor = const Color(0xFF2EA043);
    else if (score >= 50) scoreColor = Colors.amber;
    else scoreColor = Colors.redAccent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(LucideIcons.sparkles, color: Color(0xFF2EA043), size: 28),
          const SizedBox(width: 12),
          Text('추천 분석 결과', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
        ]),
        const SizedBox(height: 12),
        RichText(text: TextSpan(
          style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 14),
          children: [
            const TextSpan(text: '현재 '),
            TextSpan(text: '$_weatherDesc', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
            const TextSpan(text: ' 날씨와 '),
            TextSpan(text: '$moodLabel', style: const TextStyle(color: Color(0xFF2EA043), fontWeight: FontWeight.bold)),
            const TextSpan(text: ' 기분을 고려한 맞춤 분석입니다.'),
          ],
        )),
        const SizedBox(height: 12),
        // 산책 지수 & 체감온도 뱃지 행
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // 산책 지수
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: scoreColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scoreColor.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.footprints, size: 13, color: scoreColor),
                  const SizedBox(width: 5),
                  Text(
                    '산책 지수 $score점',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: scoreColor),
                  ),
                ],
              ),
            ),
            // 체감온도 (Heat Index)
            if (heatIdx != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (heatIdx >= 32 ? Colors.orange : Colors.blue).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (heatIdx >= 32 ? Colors.orange : Colors.blue).withOpacity(0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      heatIdx >= 32 ? LucideIcons.thermometerSun : LucideIcons.thermometer,
                      size: 13,
                      color: heatIdx >= 32 ? Colors.orange : Colors.blue,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '체감 ${heatIdx.toStringAsFixed(1)}°C',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: heatIdx >= 32 ? Colors.orange : Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            // 습도
            if (humidity != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.lightBlue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.lightBlue.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.droplets, size: 13, color: Colors.lightBlue),
                    const SizedBox(width: 5),
                    Text(
                      '습도 ${humidity.toInt()}%',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.lightBlue),
                    ),
                  ],
                ),
              ),
            // 폭염 경보 뱃지
            if (_weatherContext.heatDangerLevel >= 1)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.red.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.flame, size: 13, color: Colors.redAccent),
                    const SizedBox(width: 5),
                    Text(
                      _weatherContext.heatWarningTitle.replaceAll(RegExp(r'^[🔴🟠🟡]\s*'), ''),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.redAccent),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildParkCard(Park park, Color textColor, bool isDark) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: textColor.withOpacity(0.02),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: textColor.withOpacity(0.06)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (_isExperimentalEnabled) {
            _showRouteSelectionSheet(park, textColor, isDark);
          } else {
            try {
              _mapController.move(park.location, 16.0);
            } catch (_) {}
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2EA043).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.park, color: Color(0xFF2EA043), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      park.name,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(park.typeLabel, style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.6))),
                        const SizedBox(width: 8),
                        Text('· ${park.distanceFromRoute.toInt()}m', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (park.hasToilet) _buildFacilityIcon('🚽', true, '화장실'),
                        if (park.hasBench) ...[const SizedBox(width: 6), _buildFacilityIcon('🪑', true, '벤치')],
                        if (park.hasLighting) ...[const SizedBox(width: 6), _buildFacilityIcon('💡', true, '조명')],
                        if (park.hasExerciseEquipment) ...[const SizedBox(width: 6), _buildFacilityIcon('💪', true, '운동기구')],
                      ],
                    ),
                  ],
                ),
              ),
              // 평점 버튼
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
        ),
      ),
    );
  }

  Widget _buildFacilityIcon(String icon, bool isAvailable, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isAvailable ? const Color(0xFF2EA043).withOpacity(0.08) : Colors.grey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isAvailable ? const Color(0xFF2EA043).withOpacity(0.2) : Colors.grey.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: isAvailable ? const Color(0xFF2EA043) : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormattedText(String text, Color textColor) {
    final List<TextSpan> spans = [];
    // 볼드 패턴 (**텍스트**)
    final regExp = RegExp(r'\*\*(.*?)\*\*');
    int start = 0;
    
    for (final match in regExp.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2EA043)),
      ));
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 13, height: 1.5, color: textColor),
        children: spans,
      ),
    );
  }
}

/// 말풍선 꼬리(삼각형) Painter
class _BubbleTailPainter extends CustomPainter {
  final Color color;
  const _BubbleTailPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    // latlong2의 Path와 충돌 방지: dart:ui의 Path를 직접 인스턴스화
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BubbleTailPainter oldDelegate) => oldDelegate.color != color;
}
