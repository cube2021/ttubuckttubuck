import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_preferences.dart';
import '../services/user_preferences_service.dart';
import '../main.dart';

class WalkPersonalityScreen extends StatefulWidget {
  final bool isOnboarding;
  final VoidCallback? onCompleted;
  const WalkPersonalityScreen({super.key, this.isOnboarding = false, this.onCompleted});

  @override
  State<WalkPersonalityScreen> createState() => _WalkPersonalityScreenState();
}

class _WalkPersonalityScreenState extends State<WalkPersonalityScreen> {
  int _step = 0;
  bool _isSaving = false;

  // 선택값
  String? _purpose;
  String? _intensity;
  String? _companion;
  String? _atmosphere;
  String? _naturalStyle;
  String? _visitTime;
  String? _transportType;
  final Set<String> _staticActivities = {};
  final Set<String> _dynamicActivities = {};
  final Set<String> _facilities = {};
  final Set<String> _culturalFacilities = {};
  final Set<String> _accessibility = {};
  bool _prefersToilet = true;
  bool _prefersBench = true;
  bool _prefersLighting = false;

  final List<Map<String, String>> _purposes = [
    {'value': 'walking', 'label': '🌿 힐링 산책', 'desc': '여유롭게 자연을 즐기고 싶어요'},
    {'value': 'exercise', 'label': '🏃 운동', 'desc': '체력 관리 및 활동적인 움직임'},
  ];

  final List<Map<String, String>> _intensities = [
    {'value': 'low', 'label': '🐢 여유롭게', 'desc': '천천히 걸으며 쉬엄쉬엄'},
    {'value': 'medium', 'label': '🚶 적당하게', 'desc': '가볍게 땀 나는 정도'},
    {'value': 'high', 'label': '🔥 활발하게', 'desc': '빠르게 걷거나 달리기 포함'},
  ];

  final List<Map<String, String>> _companions = [
    {'value': 'alone', 'label': '🧍 혼자'},
    {'value': 'couple', 'label': '👫 연인'},
    {'value': 'friends', 'label': '👥 친구'},
    {'value': 'family_parents', 'label': '👨‍👩‍👦 가족 (부모님)'},
    {'value': 'family_kids', 'label': '🧒 가족 (아이 동반)'},
    {'value': 'pet', 'label': '🐶 반려동물'},
  ];

  final List<Map<String, String>> _atmospheres = [
    {'value': 'quiet', 'label': '🌲 한적하고 조용한 곳'},
    {'value': 'lively', 'label': '🎉 활기차고 사람 많은 곳'},
    {'value': 'local', 'label': '🏘 로컬 느낌의 동네 공원'},
    {'value': 'landmark', 'label': '🏙 랜드마크형 대형 공원'},
  ];

  final List<Map<String, String>> _naturalStyles = [
    {'value': 'forest', 'label': '🌳 나무가 우거진 숲길'},
    {'value': 'riverside', 'label': '🌊 탁 트인 강변·호수뷰'},
    {'value': 'garden', 'label': '🌸 잘 가꿔진 평지 정원'},
    {'value': 'scenic_trail', 'label': '⛰ 경치 좋은 산책로'},
  ];

  final List<Map<String, String>> _visitTimes = [
    {'value': 'early_morning', 'label': '🌅 이른 아침'},
    {'value': 'afternoon', 'label': '☀️ 낮·오후'},
    {'value': 'sunset', 'label': '🌇 일몰·노을 시간대'},
    {'value': 'night', 'label': '🌙 밤 (야경·조명)'},
  ];

  final List<Map<String, String>> _transports = [
    {'value': 'walk', 'label': '🚶 도보 가능 거리'},
    {'value': 'transit', 'label': '🚌 대중교통 30분 이내'},
    {'value': 'car', 'label': '🚗 자차 이동 (주차장 필수)'},
  ];

  final List<Map<String, String>> _staticActivitiesList = [
    {'value': 'rest', 'label': '💤 휴식'},
    {'value': 'picnic', 'label': '🧺 피크닉'},
    {'value': 'reading', 'label': '📚 독서'},
    {'value': 'watergazing', 'label': '💧 물멍'},
    {'value': 'meditation', 'label': '🧘 사색·명상'},
    {'value': 'sunbathing', 'label': '☀️ 일광욕'},
  ];

  final List<Map<String, String>> _dynamicActivitiesList = [
    {'value': 'light_walk', 'label': '🚶 가벼운 산책'},
    {'value': 'jogging', 'label': '🏃 조깅'},
    {'value': 'running', 'label': '💨 러닝'},
    {'value': 'cycling', 'label': '🚴 자전거'},
    {'value': 'hiking', 'label': '⛰ 등산'},
    {'value': 'inline', 'label': '🛼 인라인·보드'},
    {'value': 'exercise_equipment', 'label': '🏋 야외 운동기구'},
  ];

  final List<Map<String, String>> _facilitiesList = [
    {'value': 'lawn', 'label': '🌿 잔디광장'},
    {'value': 'pond', 'label': '⛲ 연못·분수대'},
    {'value': 'playground', 'label': '🛝 어린이 놀이터'},
    {'value': 'floor_fountain', 'label': '💦 바닥분수'},
    {'value': 'dog_park', 'label': '🐕 반려견 놀이터'},
    {'value': 'outdoor_stage', 'label': '🎭 야외 무대'},
    {'value': 'sports_court', 'label': '🏅 운동장·테니스장'},
  ];

  final List<Map<String, String>> _culturalList = [
    {'value': 'museum', 'label': '🏛 미술관·박물관'},
    {'value': 'botanical_garden', 'label': '🌺 식물원·온실'},
    {'value': 'zoo', 'label': '🦁 동물원'},
    {'value': 'heritage', 'label': '🏯 유적지'},
    {'value': 'camping', 'label': '⛺ 캠핑·취사'},
    {'value': 'water_leisure', 'label': '🚣 수상 레저'},
  ];

  final List<Map<String, String>> _accessibilityList = [
    {'value': 'flat_ground', 'label': '♿ 계단 없는 평지'},
    {'value': 'shade_area', 'label': '🌂 그늘막 구역'},
    {'value': 'clean_restroom', 'label': '🚻 화장실 위생'},
    {'value': 'nearby_cafe', 'label': '☕ 주변 맛집·카페'},
  ];

  // 전체 스텝 수
  int get _totalSteps => 9;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildProgressBar(),
            Expanded(child: _buildStepContent()),
            _buildNavButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    const titles = [
      '산책 목적이 뭔가요?',
      '활동 강도를 알려주세요',
      '정적 활동을 선택해요',
      '동적 활동을 선택해요',
      '누구와 함께 걷나요?',
      '어떤 분위기를 좋아해요?',
      '선호하는 자연 환경은?',
      '주로 언제 방문해요?',
      '마지막으로 편의 조건을!',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          if (_step > 0)
            IconButton(
              onPressed: () => setState(() => _step--),
              icon: const Icon(LucideIcons.arrowLeft, color: Colors.white70),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: _step == 0 ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                Text(
                  titles[_step],
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                  textAlign: _step == 0 ? TextAlign.center : TextAlign.start,
                ),
              ],
            ),
          ),
          if (_step == 0)
            TextButton(
              onPressed: _skip,
              child: const Text('건너뛰기', style: TextStyle(color: Colors.white38, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: (_step + 1) / _totalSteps,
          backgroundColor: Colors.white12,
          color: const Color(0xFF2EA043),
          minHeight: 5,
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: switch (_step) {
        0 => _buildSingleChoice('purpose', _purposes, _purpose, (v) => setState(() => _purpose = v)),
        1 => _buildSingleChoice('intensity', _intensities, _intensity, (v) => setState(() => _intensity = v)),
        2 => _buildMultiChoice('static', _staticActivitiesList, _staticActivities),
        3 => _buildMultiChoice('dynamic', _dynamicActivitiesList, _dynamicActivities),
        4 => _buildSingleChoice('companion', _companions, _companion, (v) => setState(() => _companion = v)),
        5 => _buildSingleChoice('atmosphere', _atmospheres, _atmosphere, (v) => setState(() => _atmosphere = v)),
        6 => _buildSingleChoice('natural', _naturalStyles, _naturalStyle, (v) => setState(() => _naturalStyle = v)),
        7 => _buildSingleChoice('time', _visitTimes, _visitTime, (v) => setState(() => _visitTime = v)),
        8 => _buildFinalStep(),
        _ => const SizedBox(),
      },
    );
  }

  Widget _buildSingleChoice(String key, List<Map<String, String>> items, String? selected, void Function(String) onSelect) {
    return Column(
      children: items.map((item) {
        final isSelected = selected == item['value'];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: () => onSelect(item['value']!),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF2EA043).withOpacity(0.18) : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? const Color(0xFF2EA043) : Colors.white.withOpacity(0.1),
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['label']!, style: TextStyle(color: isSelected ? const Color(0xFF4CAF50) : Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                        if (item['desc'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(item['desc']!, style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13)),
                          ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    const Icon(LucideIcons.checkCircle, color: Color(0xFF2EA043), size: 22),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMultiChoice(String key, List<Map<String, String>> items, Set<String> selected) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items.map((item) {
        final isSelected = selected.contains(item['value']);
        return GestureDetector(
          onTap: () => setState(() {
            if (isSelected) {
              selected.remove(item['value']);
            } else {
              selected.add(item['value']!);
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF2EA043).withOpacity(0.18) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: isSelected ? const Color(0xFF2EA043) : Colors.white.withOpacity(0.15),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Text(
              item['label']!,
              style: TextStyle(
                color: isSelected ? const Color(0xFF4CAF50) : Colors.white70,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFinalStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 이동 수단
        const Text('🚌 어떻게 이동하나요?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ..._transports.map((item) {
          final isSelected = _transportType == item['value'];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => setState(() => _transportType = item['value']),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF2EA043).withOpacity(0.15) : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isSelected ? const Color(0xFF2EA043) : Colors.white12),
                ),
                child: Text(item['label']!, style: TextStyle(color: isSelected ? const Color(0xFF4CAF50) : Colors.white70, fontSize: 15)),
              ),
            ),
          );
        }),

        const SizedBox(height: 24),

        // 선호 시설
        const Text('🏟 원하는 공원 시설 (복수 선택)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _buildMultiChoice('fac', _facilitiesList, _facilities),

        const SizedBox(height: 24),

        // 문화시설
        const Text('🏛 문화·체험 시설 관심 (복수 선택)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _buildMultiChoice('cult', _culturalList, _culturalFacilities),

        const SizedBox(height: 24),

        // 접근성
        const Text('♿ 필요한 편의 조건 (복수 선택)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _buildMultiChoice('access', _accessibilityList, _accessibility),

        const SizedBox(height: 24),

        // 기본 편의시설 토글
        const Text('🚻 기본 편의 설정', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _buildToggleTile('화장실 선호', _prefersToilet, (v) => setState(() => _prefersToilet = v)),
        _buildToggleTile('벤치 선호', _prefersBench, (v) => setState(() => _prefersBench = v)),
        _buildToggleTile('야간 조명 선호', _prefersLighting, (v) => setState(() => _prefersLighting = v)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildToggleTile(String label, bool value, void Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
            Switch(value: value, onChanged: onChanged, activeColor: const Color(0xFF2EA043)),
          ],
        ),
      ),
    );
  }

  Widget _buildNavButtons() {
    final isLast = _step == _totalSteps - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: _isSaving ? null : (isLast ? _save : _next),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2EA043),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _isSaving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(isLast ? '✅ 저장하기' : '다음 →', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ),
    );
  }

  void _next() {
    if (_step < _totalSteps - 1) setState(() => _step++);
  }

  void _skip() async {
    if (widget.isOnboarding) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final sPrefs = await SharedPreferences.getInstance();
        await sPrefs.setBool('onboarding_completed_${user.id}', true);
      }
      if (mounted) {
        if (widget.onCompleted != null) {
          widget.onCompleted!();
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MainLayout()),
          );
        }
      }
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final prefs = UserPreferences(
      purpose: _purpose,
      intensity: _intensity,
      companion: _companion,
      preferredAtmosphere: _atmosphere,
      naturalStyle: _naturalStyle,
      visitTime: _visitTime,
      transportType: _transportType,
      staticActivities: _staticActivities.toList(),
      dynamicActivities: _dynamicActivities.toList(),
      preferredFacilities: _facilities.toList(),
      culturalFacilities: _culturalFacilities.toList(),
      accessibilityNeeds: _accessibility.toList(),
      prefersToilet: _prefersToilet,
      prefersBench: _prefersBench,
      prefersLighting: _prefersLighting,
      maxWalkDistanceKm: 3.0,
    );
    await UserPreferencesService.saveAll(prefs);
    if (mounted) {
      if (widget.isOnboarding) {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          final sPrefs = await SharedPreferences.getInstance();
          await sPrefs.setBool('onboarding_completed_${user.id}', true);
        }
        if (widget.onCompleted != null) {
          widget.onCompleted!();
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MainLayout()),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ 성향이 저장되었습니다!'), backgroundColor: Color(0xFF2EA043)),
        );
        Navigator.pop(context);
      }
    }
  }
}