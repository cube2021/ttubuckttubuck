import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'map_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  String? _purpose;
  String? _intensity;
  String? _preferredRegion;
  bool _pushEnabled = false;

  final List<Map<String, dynamic>> _steps = [
    {
      'title': '어떤 목적으로\n사용하실 건가요?',
      'subtitle': '사용자님의 라이프스타일에 맞춘 기능을 제공해 드려요.',
      'options': [
        {'label': '산책', 'icon': LucideIcons.footprints, 'value': 'walking'},
        {'label': '운동', 'icon': LucideIcons.dumbbell, 'value': 'exercise'},
      ],
    },
    {
      'title': '선호하는 운동 강도는\n어느 정도인가요?',
      'subtitle': '강도에 따라 추천 코스와 목표가 달라집니다.',
      'options': [
        {'label': '여유롭게 (저강도)', 'icon': LucideIcons.leaf, 'value': 'low'},
        {'label': '적당하게 (중강도)', 'icon': LucideIcons.flame, 'value': 'medium'},
        {'label': '활발하게 (고강도)', 'icon': LucideIcons.zap, 'value': 'high'},
      ],
    },
    {
      'title': '내 지정 산책 루트를\n알려주세요',
      'subtitle': '지도를 탭해서 산책할 경로를 그리거나 저장해 주세요.',
      'action': 'map',
    },
    {
      'title': '푸시 알림을\n허용하시겠어요?',
      'subtitle': '중요한 활동 기록과 맞춤 알림을 보내드릴게요.',
      'isToggle': true,
    }
  ];

  void _nextPage() {
    if (_currentPage < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  Future<void> _completeOnboarding() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('onboarding_completed_${user.id}', true);
        
        await Supabase.instance.client.from('profiles').update({
          'purpose': _purpose,
          'intensity': _intensity,
          'push_enabled': _pushEnabled,
        }).eq('id', user.id);
        
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      } catch (e) {
        debugPrint("온보딩 저장 오류: $e");
        // Even if DB update fails, we should let the user proceed or show error
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = const Color(0xFF2EA043);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark 
              ? [const Color(0xFF1A1A1A), const Color(0xFF242424)]
              : [const Color(0xFFFAF9F6), Colors.white],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              _buildProgressIndicator(),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (int page) {
                    setState(() {
                      _currentPage = page;
                    });
                  },
                  itemCount: _steps.length,
                  itemBuilder: (context, index) {
                    return _buildPage(_steps[index]);
                  },
                ),
              ),
              _buildBottomBar(primaryColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: List.generate(_steps.length, (index) {
          bool isActive = index <= _currentPage;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFF2EA043) : Colors.grey.withOpacity(0.2),
                borderRadius: BorderRadius.circular(3),
                boxShadow: isActive ? [
                  BoxShadow(
                    color: const Color(0xFF2EA043).withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ] : [],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPage(Map<String, dynamic> step) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step['title'],
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: textColor,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            step['subtitle'],
            style: TextStyle(
              fontSize: 16,
              color: textColor.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 48),
          if (step['options'] != null)
            ...step['options'].map<Widget>((option) {
              bool isSelected = (_currentPage == 0 && _purpose == option['value']) ||
                               (_currentPage == 1 && _intensity == option['value']) ||
                               (_currentPage == 2 && _preferredRegion == option['value']);
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      if (_currentPage == 0) _purpose = option['value'];
                      if (_currentPage == 1) _intensity = option['value'];
                      if (_currentPage == 2) _preferredRegion = option['value'];
                    });
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isSelected 
                        ? const Color(0xFF2EA043).withOpacity(0.1) 
                        : (isDark ? Colors.white.withOpacity(0.05) : Colors.white),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected 
                          ? const Color(0xFF2EA043) 
                          : Colors.grey.withOpacity(0.2),
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          option['icon'],
                          color: isSelected ? const Color(0xFF2EA043) : textColor.withOpacity(0.5),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          option['label'],
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? const Color(0xFF2EA043) : textColor,
                          ),
                        ),
                        const Spacer(),
                        if (isSelected)
                          const Icon(LucideIcons.checkCircle2, color: Color(0xFF2EA043)),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          if (step['action'] == 'map')
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const MapScreen(isDesignatingRoute: true)),
                        );
                        setState(() => _preferredRegion = 'designated');
                      },
                      icon: const Icon(LucideIcons.pencil, color: Colors.white),
                      label: Text(
                        _preferredRegion != null ? '지정 루트 수정하기' : '루트 지정하러 가기',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2EA043),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ),
                  if (_preferredRegion != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text('✅ 루트 지정이 완료되었습니다.', style: TextStyle(color: Color(0xFF2EA043), fontWeight: FontWeight.bold)),
                    )
                ],
              ),
            ),
          if (step['isToggle'] == true)
            Center(
              child: Column(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2EA043).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.bell,
                      size: 60,
                      color: Color(0xFF2EA043),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Switch.adaptive(
                    value: _pushEnabled,
                    activeColor: const Color(0xFF2EA043),
                    onChanged: (val) => setState(() => _pushEnabled = val),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _pushEnabled ? '허용됨' : '허용 안 함',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _pushEnabled ? const Color(0xFF2EA043) : textColor.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(Color primaryColor) {
    bool canProceed = false;
    if (_currentPage == 0) canProceed = _purpose != null;
    if (_currentPage == 1) canProceed = _intensity != null;
    if (_currentPage == 2) canProceed = _preferredRegion != null;
    if (_currentPage == 3) canProceed = true;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: ElevatedButton(
          onPressed: canProceed ? _nextPage : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            disabledBackgroundColor: primaryColor.withOpacity(0.3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0,
          ),
          child: Text(
            _currentPage == _steps.length - 1 ? '시작하기' : '다음',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
