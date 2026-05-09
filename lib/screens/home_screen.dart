import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../services/config.dart';
import '../services/park_service.dart';
import '../services/gemini_service.dart';
import '../models/park.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
  List<LatLng> _currentRouteForMap = [];
  
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
    NotificationService().scheduleDailyAttendanceNotification();
  }

  Future<void> _checkAttendanceStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toString().split(' ')[0];
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final lastCheckIn = prefs.getString('last_check_in_date_${user.id}');
    
    if (mounted) {
      setState(() {
        _hasCheckedInToday = lastCheckIn == today;
        _attendanceStreak = prefs.getInt('attendance_streak_${user.id}') ?? 0;
      });
    }
  }

  Future<void> _performAttendanceCheck() async {
    if (_hasCheckedInToday) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toString().split(' ')[0];
    final yesterday = DateTime.now().subtract(const Duration(days: 1)).toString().split(' ')[0];
    
    final lastCheckIn = prefs.getString('last_check_in_date_${user.id}');
    
    int newStreak = 1;
    if (lastCheckIn == yesterday) {
      newStreak = (prefs.getInt('attendance_streak_${user.id}') ?? 0) + 1;
    }
    
    await prefs.setString('last_check_in_date_${user.id}', today);
    await prefs.setInt('attendance_streak_${user.id}', newStreak);
    
    if (mounted) {
      setState(() {
        _hasCheckedInToday = true;
        _attendanceStreak = newStreak;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 출석 완료! 연속 $_attendanceStreak일 출석했습니다.'),
          backgroundColor: const Color(0xFF2EA043),
          behavior: SnackBarBehavior.floating,
        ),
      );
      
      try {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          await Supabase.instance.client.from('attendance_records').insert({
            'user_id': user.id,
            'check_in_date': today,
            'streak': newStreak,
          });
        }
      } catch (e) {
        debugPrint('Supabase 출석 기록 실패: $e');
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
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final lat = position.latitude;
      final lon = position.longitude;
      
      // 1. 일반 날씨 및 지명
      final weatherUrl = 'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=${AppConfig.weatherApiKey}&units=metric&lang=kr';
      final weatherRes = await http.get(Uri.parse(weatherUrl));
      
      // 2. 대기 오염 (미세먼지)
      final airUrl = 'https://api.openweathermap.org/data/2.5/air_pollution?lat=$lat&lon=$lon&appid=${AppConfig.weatherApiKey}';
      final airRes = await http.get(Uri.parse(airUrl));

      if (weatherRes.statusCode == 200 && mounted) {
        final data = json.decode(weatherRes.body);
        setState(() {
          _weatherTemp = data['main']['temp'].toStringAsFixed(1);
          _weatherDesc = data['weather'][0]['description'];
          _locationName = data['name'];
          _setWeatherIcon(data['weather'][0]['main']);
        });
      }
      
      if (airRes.statusCode == 200 && mounted) {
        final data = json.decode(airRes.body);
        if (data['list'] != null && data['list'].isNotEmpty) {
          final components = data['list'][0]['components'];
          setState(() {
            _pm10 = (components['pm10'] as num?)?.toDouble();
            _pm25 = (components['pm2_5'] as num?)?.toDouble();
          });
        }
      }
    } catch (e) { debugPrint("날씨/미세먼지 불러오기 실패: $e"); }
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
    if (routeJson == null) return [];
    try {
      return (routeJson as List).map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())).toList();
    } catch (_) { return []; }
  }

  Future<List<LatLng>> _getDesignatedRoute() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        final routeString = prefs.getString('designated_route_${user.id}');
        if (routeString != null) {
          final List<dynamic> decoded = jsonDecode(routeString);
          return decoded.map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())).toList();
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
        dist = (_selectedRecord!['distance_km'] as num).toDouble();
      } else {
        route = await _getDesignatedRoute();
        if (route.isEmpty) {
          try {
            final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
            route = [LatLng(position.latitude, position.longitude)];
          } catch (_) {
            route = [const LatLng(37.5665, 126.9780)];
          }
        }
        dist = 1.0;
      }
      
      final parks = await ParkService.findParksNearRoute(route, dist, moodId: selectedMood);
      
      final moodLabel = moods.firstWhere((m) => m['id'] == selectedMood, orElse: () => moods.first)['label'];
      String aiText;
      
      if (parks.isNotEmpty) {
        aiText = await GeminiService.getParkRecommendation(
          parks: parks.take(3).toList(),
          mood: moodLabel,
          weather: _weatherDesc,
        );
      } else {
        aiText = await GeminiService.getNoParkRecommendation(moodLabel, _weatherDesc);
      }

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
    return GlassmorphicContainer(
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
              Container(
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
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity, height: 64,
                child: ElevatedButton(
                  onPressed: hasRoute
                      ? () => setState(() {
                            _useDesignatedRoute = true;
                            _currentStep = 1;
                          })
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2EA043).withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2EA043).withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(LucideIcons.sparkles, color: Color(0xFF2EA043), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _aiRecommendationText!,
                    style: TextStyle(fontSize: 14, height: 1.5, color: textColor),
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
                    markers: _recommendedParks.map<Marker>((p) => Marker(
                      point: p.location,
                      width: 40, height: 40,
                      child: Container(
                        decoration: BoxDecoration(color: Colors.green.shade700, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                        child: const Icon(Icons.park, color: Colors.white, size: 20),
                      ),
                    )).toList(),
                  ),
                ],
              ),
            ),
          ),
          const Text('추천 공원', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
        final dist = (record['distance_km'] as num).toDouble();
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
    final moodLabel = moods.firstWhere((m) => m['id'] == selectedMood)['label'];
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
      ],
    );
  }

  Widget _buildParkCard(Park park, Color textColor, bool isDark) {
    final moodKeyword = moods.firstWhere((m) => m['id'] == selectedMood)['keyword'];
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: textColor.withOpacity(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.green.withOpacity(0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.park, color: Color(0xFF2EA043))),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(park.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
            Text('${park.typeLabel} · 경로에서 ${park.distanceFromRoute.toInt()}m', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ])),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: textColor.withOpacity(0.03), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(LucideIcons.info, size: 14, color: Color(0xFF2EA043)),
            const SizedBox(width: 8),
            Expanded(child: Text('현재 $moodKeyword 분위기의 산책을 즐기기에 딱 좋아요.', style: const TextStyle(fontSize: 12, color: Colors.white70))),
          ]),
        ),
      ]),
    );
  }
}
