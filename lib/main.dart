import 'package:flutter/material.dart';
import 'services/config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'screens/recommendation_screen.dart';
import 'screens/history_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/onboarding_screen.dart';
import 'package:lucide_icons/lucide_icons.dart';
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
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          
          final session = snapshot.data?.session;
          if (session != null) {
            return const AuthWrapper();
          } else {
            return const ProfileScreen();
          }
        },
      ),
      routes: {
        '/home': (context) => const MainLayout(),
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  Future<bool> _checkOnboarding() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;

    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboarding_completed_${user.id}') == true;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _checkOnboarding(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        
        if (snapshot.data == true) {
          return const MainLayout();
        } else {
          return const OnboardingScreen();
        }
      },
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
  
  final List<Widget> _screens = [
    const HomeScreen(),
    const RecommendationScreen(),
    const HistoryScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
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
            BottomNavigationBarItem(icon: Icon(LucideIcons.thumbsUp), activeIcon: Icon(LucideIcons.thumbsUp), label: '추천'),
            BottomNavigationBarItem(icon: Icon(LucideIcons.history), activeIcon: Icon(LucideIcons.history), label: '기록'),
            BottomNavigationBarItem(icon: Icon(LucideIcons.settings), activeIcon: Icon(LucideIcons.settings), label: '설정'),
          ],
        ),
      ),
    );
  }
}
