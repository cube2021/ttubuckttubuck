import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import '../services/theme_provider.dart';
import 'display_settings_screen.dart';
import 'my_route_settings_screen.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'walk_personality_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  String _selectedGender = '남성';
  
  String? _userName;
  int? _userAge;
  String? _userGender;
  String? _userPersonality;
  String _appVersion = '불러오는 중...';
  String _shorebirdPatchInfo = 'Shorebird 패치 확인 중...';
  final _shorebirdUpdater = ShorebirdUpdater();
  
  bool _isLoading = false;
  bool _isSignUp = false;
  User? _user;
  bool _experimentalEnabled = false;

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
    _initShorebirdInfo();
    _loadExperimentalSetting();
    _user = Supabase.instance.client.auth.currentUser;
    if (_user != null) {
      _fetchProfile();
      _loadPersonality();
    }
  }

  Future<void> _loadPersonality() async {
    if (_user == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _userPersonality = prefs.getString('pref_${_user!.id}_personality');
      });
    } catch (e) {
      debugPrint('성향 로드 실패: $e');
    }
  }

  Future<void> _loadExperimentalSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _experimentalEnabled = prefs.getBool('experimental_park_recommendation') ?? false;
      });
    } catch (e) {
      debugPrint('실험적 기능 설정 로드 실패: $e');
    }
  }

  Future<void> _initShorebirdInfo() async {
    try {
      final isAvailable = _shorebirdUpdater.isAvailable;
      if (!isAvailable) {
        setState(() {
          _shorebirdPatchInfo = 'Shorebird 미지원 또는 디버그 빌드';
        });
        return;
      }
      
      final patch = await _shorebirdUpdater.readCurrentPatch();
      if (patch != null) {
        setState(() {
          _shorebirdPatchInfo = 'Shorebird Patch ${patch.number} 적용됨';
        });
      } else {
        setState(() {
          _shorebirdPatchInfo = 'Shorebird 적용됨 (패치 없음)';
        });
      }
    } catch (e) {
      setState(() {
        _shorebirdPatchInfo = 'Shorebird 정보 로드 실패';
      });
    }
  }

  Future<void> _initPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = 'v${info.version}+${info.buildNumber}';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _appVersion = '버전 정보 알 수 없음');
    }
  }

  Future<void> _fetchProfile() async {
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', _user!.id)
          .single();
      
      if (mounted) {
        setState(() {
          _userName = data['full_name'];
          _userAge = data['age'];
          _userGender = data['gender'];
        });
      }
    } catch (e) {
      debugPrint("프로필 조회 에러: $e");
    }
  }

  Future<void> _handleAuth() async {
    setState(() => _isLoading = true);
    try {
      if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
        throw Exception('이메일과 비밀번호를 입력해 주세요.');
      }

      if (_isSignUp) {
        if (_nameController.text.isEmpty || _ageController.text.isEmpty) {
          throw Exception('이름과 나이를 모두 입력해 주세요.');
        }

        final res = await Supabase.instance.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        if (res.user != null) {
          await Supabase.instance.client.from('profiles').insert({
            'id': res.user!.id,
            'full_name': _nameController.text.trim(),
            'age': int.tryParse(_ageController.text) ?? 0,
            'gender': _selectedGender,
          });
          
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('회원가입 성공! 로그인해 주세요.')));
          setState(() => _isSignUp = false);
        }
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }
    } catch (e) {
      debugPrint("인증 오류 상세: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('실패: ${e.toString().replaceAll('Exception:', '')}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    _user = Supabase.instance.client.auth.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final cardColor = isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05);

    if (_user != null) {
      return Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('설정', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor)),
              const SizedBox(height: 32),
              
              // --- 1. 내 정보 섹션 ---
              _buildSectionTitle('내 정보', textColor: textColor),
              const SizedBox(height: 12),
              GlassmorphicContainer(
                width: double.infinity,
                height: 160,
                borderRadius: 20,
                blur: 20,
                alignment: Alignment.center,
                border: 1,
                linearGradient: LinearGradient(colors: [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.05)]),
                borderGradient: LinearGradient(colors: [Colors.white.withOpacity(0.2), Colors.white.withOpacity(0.05)]),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 60, height: 60,
                        decoration: const BoxDecoration(color: Color(0xFF2EA043), shape: BoxShape.circle),
                        child: const Icon(LucideIcons.user, color: Colors.white, size: 30),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_userName ?? '회원님', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                            Text(_user!.email ?? '', style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 13)),
                            const SizedBox(height: 4),
                            if (_userAge != null)
                              Text('$_userAge세 / $_userGender', style: const TextStyle(color: Color(0xFF2EA043), fontSize: 12, fontWeight: FontWeight.w600)),
                            if (_userPersonality != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2EA043).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF2EA043).withOpacity(0.3)),
                                  ),
                                  child: Text(_userPersonality!, style: const TextStyle(color: Color(0xFF2EA043), fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _signOut,
                        icon: const Icon(LucideIcons.logOut, color: Colors.redAccent, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // --- 1.5 앱 설정 섹션 ---
              _buildSectionTitle('앱 설정', textColor: textColor),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: textColor.withOpacity(0.1)),
                ),
                child: Column(
                  children: [
                    ListTile(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DisplaySettingsScreen())),
                      leading: const Icon(LucideIcons.monitor, color: Color(0xFF2EA043)),
                      title: Text('화면 설정', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                      trailing: Icon(LucideIcons.chevronRight, size: 20, color: textColor.withOpacity(0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    Divider(color: textColor.withOpacity(0.05), height: 1),
                    ListTile(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MyRouteSettingsScreen()),
                      ),
                      leading: const Icon(LucideIcons.map, color: Color(0xFF2EA043)),
                      title: Text('내 루트 설정', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                      trailing: Icon(LucideIcons.chevronRight, size: 20, color: textColor.withOpacity(0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    Divider(color: textColor.withOpacity(0.05), height: 1),
                    Divider(color: textColor.withOpacity(0.05), height: 1),
                    ListTile(
                      onTap: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const WalkPersonalityScreen()),
                        );
                        if (result == true) {
                          _loadPersonality();
                        }
                      },
                      leading: const Icon(LucideIcons.footprints, color: Color(0xFF2EA043)),
                      title: Text('산책 성향 분석 테스트', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                      trailing: Icon(LucideIcons.chevronRight, size: 20, color: textColor.withOpacity(0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    Divider(color: textColor.withOpacity(0.05), height: 1),
                    ListTile(
                      onTap: () => Navigator.pushNamed(context, '/logs'),
                      leading: const Icon(LucideIcons.fileText, color: Color(0xFF2EA043)),
                      title: Text('앱 로그 보기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                      trailing: Icon(LucideIcons.chevronRight, size: 20, color: textColor.withOpacity(0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    Divider(color: textColor.withOpacity(0.05), height: 1),
                    SwitchListTile(
                      value: _experimentalEnabled,
                      onChanged: (bool value) async {
                        try {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('experimental_park_recommendation', value);
                          setState(() {
                            _experimentalEnabled = value;
                          });
                        } catch (e) {
                          debugPrint('실험적 기능 설정 저장 실패: $e');
                        }
                      },
                      secondary: const Icon(LucideIcons.beaker, color: Color(0xFF2EA043)),
                      title: Text('실험적 기능: 공원 내 추천', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                      subtitle: Text('활성화 시 대형 공원에 한해 추천 산책 코스를 제공합니다.', style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.5))),
                      activeColor: const Color(0xFF2EA043),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // --- 2. 앱 정보 섹션 ---
              _buildSectionTitle('앱 정보', textColor: textColor),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: textColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: textColor.withOpacity(0.1)),
                ),
                child: Column(
                  children: [
                    _buildSettingsItem(LucideIcons.info, '버전 정보', _appVersion, textColor: textColor, isLast: false),
                    _buildSettingsItem(LucideIcons.heart, '만든 이들', 'Team Asterisk', textColor: textColor, isLast: true),
                  ],
                ),
              ),
              
              const SizedBox(height: 40),
              Center(
                child: Text(
                  '$_shorebirdPatchInfo ($_appVersion)',
                  style: TextStyle(color: textColor.withOpacity(0.3), fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🏃 뚜벅뚜벅', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Color(0xFF2EA043))),
            const SizedBox(height: 8),
            Text(_isSignUp ? '새로운 시작을 환영합니다!' : '다시 오신 것을 환영합니다.', style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.7))),
            const SizedBox(height: 40),
            
            GlassmorphicContainer(
              width: double.infinity,
              height: _isSignUp ? 620 : 380,
              borderRadius: 30,
              blur: 20,
              alignment: Alignment.center,
              border: 1,
              linearGradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.05)]),
              borderGradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withOpacity(0.2), Colors.white.withOpacity(0.05)]),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    _buildTextField(_emailController, '이메일', LucideIcons.mail, false),
                    const SizedBox(height: 16),
                    _buildTextField(_passwordController, '비밀번호', LucideIcons.lock, true),
                    
                    if (_isSignUp) ...[
                      const SizedBox(height: 16),
                      _buildTextField(_nameController, '이름', LucideIcons.user, false),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _buildTextField(_ageController, '나이', LucideIcons.calendar, false, isNumber: true)),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: Container(
                              height: 56,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withOpacity(0.1)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedGender,
                                  dropdownColor: const Color(0xFF161B22),
                                  style: const TextStyle(color: Colors.white),
                                  items: ['남성', '여성'].map((String value) {
                                    return DropdownMenuItem<String>(value: value, child: Text(value));
                                  }).toList(),
                                  onChanged: (val) => setState(() => _selectedGender = val!),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleAuth,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2EA043),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _isLoading 
                          ? const CircularProgressIndicator(color: Colors.white) 
                          : Text(_isSignUp ? '가입하고 시작하기' : '로그인', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => setState(() => _isSignUp = !_isSignUp),
                      child: Text(_isSignUp ? '이미 계정이 있으신가요? 로그인' : '처음이신가요? 회원가입', style: const TextStyle(color: Color(0xFF2EA043))),
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, {required Color textColor}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(title, style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildSettingsItem(IconData icon, String title, String trailing, {required Color textColor, required bool isLast}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: textColor.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: textColor.withOpacity(0.7)),
          const SizedBox(width: 16),
          Text(title, style: TextStyle(fontSize: 15, color: textColor)),
          const Spacer(),
          Text(trailing, style: TextStyle(color: textColor.withOpacity(0.4), fontSize: 13)),
          const SizedBox(width: 4),
          Icon(LucideIcons.chevronRight, size: 16, color: textColor.withOpacity(0.2)),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, bool obscure, {bool isNumber = false}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: isNumber ? TextInputType.number : TextInputType.emailAddress,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF2EA043))),
      ),
    );
  }
}
