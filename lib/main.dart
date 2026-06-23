import 'dart:async';
import 'package:flutter/material.dart';
import 'services/config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'screens/recommendation_screen.dart';
import 'screens/history_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/walk_personality_screen.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'services/theme_provider.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await dotenv.load(fileName: ".env");
    // Initialize Supabase using hardcoded config
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  } catch (e) {
    debugPrint("Supabase 초기화 오류: $e");
  }

  // Initialize Notification Service
  try {
    await NotificationService().init();
  } catch (e) {
    debugPrint("Notification 초기화 오류: $e");
  }

  // Initialize Sync Service for offline support
  SyncService().initialize();

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const TtubukApp(),
    ),
  );
}

class TtubukApp extends StatelessWidget {
  const TtubukApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: '뚜벅뚜벅',
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFFAF9F6),
        primaryColor: const Color(0xFF2EA043),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF2EA043),
          secondary: Color(0xFF7EE787),
          surface: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
        primaryColor: const Color(0xFF2EA043),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2EA043),
          secondary: Color(0xFF7EE787),
          surface: Color(0xFF242424),
        ),
      ),
      builder: (context, child) {
        final double scale = themeProvider.textScaleFactor;
        
        Widget appChild = child!;
        
        if (themeProvider.isColorBlindMode) {
          appChild = ColorFiltered(
            colorFilter: const ColorFilter.matrix([
              0.8, 0.2, 0, 0, 0,
              0.2, 0.8, 0, 0, 0,
              0, 0.2, 0.8, 0, 0,
              0, 0, 0, 1, 0,
            ]),
            child: appChild,
          );
        }

        return MediaQuery(
          // Use the existing media query data or create a default one
          data: (MediaQuery.maybeOf(context) ?? MediaQueryData.fromView(View.of(context))).copyWith(
            textScaleFactor: scale,
          ),
          child: appChild,
        );
      },
      home: const AuthWrapper(),
      routes: {
        '/home': (context) => const MainLayout(),
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool? _onboardingDone;
  bool _hasSession = false;
  late final StreamSubscription<AuthState> _authSub;

  @override
  void initState() {
    super.initState();
    _hasSession = Supabase.instance.client.auth.currentSession != null;
    if (_hasSession) _checkOnboarding();

    // 로그인/로그아웃 이벤트만 반응 (TOKEN_REFRESHED 등 무시)
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;

      final event = data.event;
      
      if (event == AuthChangeEvent.signedIn) {
        // 이미 온보딩 완료 상태면 재확인 불필요
        if (_onboardingDone == true) return;
        setState(() {
          _hasSession = true;
          _onboardingDone = null;
        });
        _checkOnboarding();
      } else if (event == AuthChangeEvent.signedOut) {
        setState(() {
          _hasSession = false;
          _onboardingDone = null;
        });
      }
      // TOKEN_REFRESHED, USER_UPDATED 등은 무시
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  Future<void> _checkOnboarding() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _onboardingDone = false);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('onboarding_completed_${user.id}') == true) {
      if (mounted) setState(() => _onboardingDone = true);
      return;
    }

    // 로컬 기록이 없으면 서버(Supabase)에 성향 데이터가 있는지 확인
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('purpose')
          .eq('id', user.id)
          .maybeSingle();

      if (row != null && row['purpose'] != null && row['purpose'].toString().isNotEmpty) {
        await prefs.setBool('onboarding_completed_${user.id}', true);
        if (mounted) setState(() => _onboardingDone = true);
        return;
      }
    } catch (e) {
      debugPrint('온보딩 상태 확인 중 오류: $e');
    }

    if (mounted) setState(() => _onboardingDone = false);
  }

  void _onSurveyCompleted() {
    if (mounted) setState(() => _onboardingDone = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasSession) return const ProfileScreen();
    if (_onboardingDone == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_onboardingDone == true) return const MainLayout();
    return WalkPersonalityScreen(
      isOnboarding: true,
      onCompleted: _onSurveyCompleted,
    );
  }
}



class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;
  late final PageController _pageController;
  
  final List<Widget> _screens = [
    const HomeScreen(),
    const RecommendationScreen(),
    const HistoryScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() => _selectedIndex = index);
            _pageController.jumpToPage(index);
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1A1A1A).withOpacity(0.8)
              : const Color(0xFFFAF9F6).withOpacity(0.8),
          selectedItemColor: const Color(0xFF2EA043),
          unselectedItemColor: Colors.grey,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          items: const [
            BottomNavigationBarItem(icon: Icon(LucideIcons.home), activeIcon: Icon(LucideIcons.home), label: '홈'),
            BottomNavigationBarItem(icon: Icon(LucideIcons.compass), activeIcon: Icon(LucideIcons.compass), label: '탐색'),
            BottomNavigationBarItem(icon: Icon(LucideIcons.history), activeIcon: Icon(LucideIcons.history), label: '기록'),
            BottomNavigationBarItem(icon: Icon(LucideIcons.settings), activeIcon: Icon(LucideIcons.settings), label: '설정'),
          ],
        ),
      ),
    );
  }
}
