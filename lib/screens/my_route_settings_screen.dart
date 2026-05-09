import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'map_screen.dart';

class MyRouteSettingsScreen extends StatefulWidget {
  const MyRouteSettingsScreen({super.key});

  @override
  State<MyRouteSettingsScreen> createState() => _MyRouteSettingsScreenState();
}

class _MyRouteSettingsScreenState extends State<MyRouteSettingsScreen> {
  List<Map<String, dynamic>> _designatedRoutes = [];
  String? _activeRouteId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDesignatedRoutes();
  }

  Future<void> _loadDesignatedRoutes() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final String? routesString = prefs.getString('designated_routes_list_${user.id}');
      final String? activeId = prefs.getString('designated_route_id_${user.id}');
      
      List<Map<String, dynamic>> loadedRoutes = [];
      if (routesString != null) {
        try {
          final List<dynamic> decoded = jsonDecode(routesString);
          loadedRoutes = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        } catch (_) {}
      }
      
      final String? oldRouteString = prefs.getString('designated_route_${user.id}');
      if (loadedRoutes.isEmpty && oldRouteString != null) {
        final newRouteId = DateTime.now().millisecondsSinceEpoch.toString();
        try {
          final migratedRoute = {
            'id': newRouteId,
            'name': '기존 지정 루트',
            'route': jsonDecode(oldRouteString),
          };
          loadedRoutes.add(migratedRoute);
          await prefs.setString('designated_routes_list_${user.id}', jsonEncode(loadedRoutes));
          await prefs.setString('designated_route_id_${user.id}', newRouteId);
          if (mounted) {
            setState(() {
              _designatedRoutes = loadedRoutes;
              _activeRouteId = newRouteId;
              _isLoading = false;
            });
          }
        } catch (_) {}
        return;
      }
      
      if (mounted) {
        setState(() {
          _designatedRoutes = loadedRoutes;
          _activeRouteId = activeId;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("지정 루트 목록 로드 실패: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectRoute(Map<String, dynamic> route) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('designated_route_${user.id}', jsonEncode(route['route']));
      await prefs.setString('designated_route_id_${user.id}', route['id']);

      setState(() {
        _activeRouteId = route['id'];
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("'${route['name']}'(이)가 현재 활성 루트로 설정되었습니다."),
            backgroundColor: const Color(0xFF2EA043),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint("루트 선택 에러: $e");
    }
  }

  Future<void> _deleteRoute(Map<String, dynamic> route) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();
      
      final updatedRoutes = List<Map<String, dynamic>>.from(_designatedRoutes);
      updatedRoutes.removeWhere((element) => element['id'] == route['id']);
      
      await prefs.setString('designated_routes_list_${user.id}', jsonEncode(updatedRoutes));

      if (_activeRouteId == route['id']) {
        if (updatedRoutes.isNotEmpty) {
          final nextRoute = updatedRoutes.first;
          await prefs.setString('designated_route_${user.id}', jsonEncode(nextRoute['route']));
          await prefs.setString('designated_route_id_${user.id}', nextRoute['id']);
          _activeRouteId = nextRoute['id'];
        } else {
          await prefs.remove('designated_route_${user.id}');
          await prefs.remove('designated_route_id_${user.id}');
          _activeRouteId = null;
        }
      }

      setState(() {
        _designatedRoutes = updatedRoutes;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("'${route['name']}' 루트가 삭제되었습니다."),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint("루트 삭제 에러: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final cardColor = isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04);
    final scaffoldBgColor = isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA);

    return Scaffold(
      backgroundColor: scaffoldBgColor,
      appBar: AppBar(
        title: const Text('내 루트 설정', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2EA043)))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  
                  // --- 1. 루트 추가 버튼 ---
                  GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MapScreen(isDesignatingRoute: true)),
                      );
                      _loadDesignatedRoutes();
                    },
                    child: GlassmorphicContainer(
                      width: double.infinity,
                      height: 100,
                      borderRadius: 24,
                      blur: 20,
                      alignment: Alignment.center,
                      border: 1,
                      linearGradient: LinearGradient(
                        colors: [
                          const Color(0xFF2EA043).withOpacity(0.15),
                          const Color(0xFF2EA043).withOpacity(0.05),
                        ],
                      ),
                      borderGradient: LinearGradient(
                        colors: [
                          const Color(0xFF2EA043).withOpacity(0.3),
                          const Color(0xFF2EA043).withOpacity(0.1),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2EA043).withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(LucideIcons.plus, color: Color(0xFF2EA043), size: 24),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('새 산책 루트 지정하기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                              const SizedBox(height: 4),
                              Text('지도로 직접 산책 코스를 추가합니다', style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.5))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // --- 2. 내 지정 루트 목록 타이틀 ---
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text('내 지정 루트 목록', style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  
                  _designatedRoutes.isEmpty
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: textColor.withOpacity(0.08)),
                          ),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(LucideIcons.map, size: 40, color: textColor.withOpacity(0.2)),
                                const SizedBox(height: 16),
                                Text(
                                  '저장된 지정 루트가 없습니다.\n위의 [새 산책 루트 지정하기]를 통해\n나만의 코스를 만들어 보세요!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: textColor.withOpacity(0.4), fontSize: 13, height: 1.6),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: textColor.withOpacity(0.08)),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            itemCount: _designatedRoutes.length,
                            separatorBuilder: (_, __) => Divider(color: textColor.withOpacity(0.05), height: 1),
                            itemBuilder: (context, index) {
                              final route = _designatedRoutes[index];
                              final isActive = route['id'] == _activeRouteId;
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                onTap: () => _selectRoute(route),
                                leading: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isActive ? const Color(0xFF2EA043).withOpacity(0.15) : textColor.withOpacity(0.05),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isActive ? LucideIcons.check : LucideIcons.mapPin,
                                    color: isActive ? const Color(0xFF2EA043) : textColor.withOpacity(0.4),
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  route['name'],
                                  style: TextStyle(
                                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                    color: isActive ? const Color(0xFF2EA043) : textColor,
                                    fontSize: 15,
                                  ),
                                ),
                                subtitle: Text(
                                  isActive ? '현재 사용 중인 대표 코스' : '지정된 산책 경로',
                                  style: TextStyle(
                                    color: isActive ? const Color(0xFF2EA043).withOpacity(0.8) : textColor.withOpacity(0.4),
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: Icon(LucideIcons.trash2, size: 18, color: Colors.redAccent.withOpacity(0.8)),
                                  onPressed: () => _deleteRoute(route),
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              );
                            },
                          ),
                        ),
                ],
              ),
            ),
    );
  }
}
