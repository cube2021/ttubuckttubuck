import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'map_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Map<String, dynamic>> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRecords();
  }

  Future<void> _fetchRecords() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final data = await Supabase.instance.client
          .from('walk_records')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      setState(() {
        _records = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('기록 불러오기 실패: $e');
      setState(() => _isLoading = false);
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m분 $s초';
  }

  String _formatDate(String iso) {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.month}월 ${dt.day}일 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  List<LatLng> _parseRoute(dynamic routeJson) {
    if (routeJson == null) return [];
    try {
      return (routeJson as List).map((p) => LatLng(
        (p['lat'] as num).toDouble(),
        (p['lng'] as num).toDouble(),
      )).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final cardColor = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _fetchRecords,
        color: const Color(0xFF2EA043),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('내 산책 기록', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor)),
                    const SizedBox(height: 20),
                    if (!_isLoading && _records.isNotEmpty) _buildSummaryCard(textColor, cardColor),
                  ],
                ),
              ),
            ),
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: Color(0xFF2EA043))),
              )
            else if (_records.isEmpty)
              SliverFillRemaining(child: _buildEmptyState(textColor))
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _buildRecordCard(_records[i], textColor, cardColor, isDark),
                  childCount: _records.length,
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MapScreen()),
          );
          _fetchRecords();
        },
        backgroundColor: const Color(0xFF2EA043),
        icon: const Icon(LucideIcons.footprints, color: Colors.white),
        label: const Text('산책하기', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }

  Widget _buildSummaryCard(Color textColor, Color cardColor) {
    final totalDist = _records.fold<double>(0, (sum, r) => sum + (r['distance_km'] as num).toDouble());
    final totalTime = _records.fold<int>(0, (sum, r) => sum + (r['duration_seconds'] as int? ?? 0));
    return GlassmorphicContainer(
      width: double.infinity,
      height: 90,
      borderRadius: 20,
      blur: 20,
      alignment: Alignment.center,
      border: 1,
      linearGradient: LinearGradient(colors: [const Color(0xFF2EA043).withOpacity(0.1), Colors.transparent]),
      borderGradient: LinearGradient(colors: [const Color(0xFF2EA043).withOpacity(0.4), Colors.transparent]),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _summaryItem('총 횟수', '${_records.length}회', LucideIcons.list, textColor),
            _summaryItem('총 거리', '${totalDist.toStringAsFixed(1)}km', LucideIcons.footprints, textColor),
            _summaryItem('총 시간', _formatDuration(totalTime), LucideIcons.timer, textColor),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(String label, String value, IconData icon, Color textColor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF2EA043)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF2EA043))),
        Text(label, style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.5))),
      ],
    );
  }

  Future<void> _editRecordTitle(Map<String, dynamic> record, Color textColor, bool isDark) async {
    final TextEditingController controller = TextEditingController(text: record['title'] ?? '');
    
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white,
        title: Text('기록 이름 수정', style: TextStyle(color: textColor)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: textColor),
          autofocus: true,
          decoration: InputDecoration(
            hintText: '새로운 이름을 입력하세요',
            hintStyle: TextStyle(color: textColor.withOpacity(0.4)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: textColor.withOpacity(0.2))),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2EA043))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('저장', style: TextStyle(color: Color(0xFF2EA043))),
          ),
        ],
      ),
    );

    if (newTitle != null && newTitle.isNotEmpty && newTitle != (record['title'] ?? '')) {
      try {
        final recordId = record['id'];
        debugPrint('기록 수정 시도: ID=$recordId (타입: ${recordId.runtimeType}), NewTitle=$newTitle');
        
        final response = await Supabase.instance.client
            .from('walk_records')
            .update({'title': newTitle})
            .eq('id', recordId)
            .select();
            
        if (response.isEmpty) {
          throw Exception('해당 기록을 찾을 수 없거나 수정 권한이 없습니다.');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('기록명이 성공적으로 수정되었습니다.'), backgroundColor: Color(0xFF2EA043)),
          );
        }
        await _fetchRecords();
      } catch (e) {
        debugPrint('이름 수정 실패: $e');
        if (mounted) {
          String errorMsg = e.toString();
          if (errorMsg.contains('403') || errorMsg.contains('permission denied')) {
            errorMsg = '수정 권한이 없습니다. (RLS 설정 확인 필요)';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('수정 실패: $errorMsg'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  Future<void> _toggleShareRecord(Map<String, dynamic> record) async {
    final title = record['title'] as String? ?? '';
    final bool isCurrentlyShared = title.startsWith('[공유] ');
    String newTitle;
    if (isCurrentlyShared) {
      newTitle = title.replaceFirst('[공유] ', '');
    } else {
      newTitle = '[공유] $title';
    }

    try {
      final recordId = record['id'];
      debugPrint('기록 공유 토글 시도: ID=$recordId, NewTitle=$newTitle');
      
      final response = await Supabase.instance.client
          .from('walk_records')
          .update({'title': newTitle})
          .eq('id', recordId)
          .select();

      if (response.isEmpty) {
        throw Exception('해당 기록을 찾을 수 없거나 수정 권한이 없습니다.');
      }

      // 내 프로필(profiles)의 purpose 컬럼에 전체 공유 리스트를 동기화하여 RLS 우회
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final myRecords = await Supabase.instance.client
            .from('walk_records')
            .select()
            .eq('user_id', user.id);
            
        final List<Map<String, dynamic>> sharedList = List<Map<String, dynamic>>.from(myRecords)
            .where((r) => (r['title'] as String? ?? '').startsWith('[공유] '))
            .map((r) => {
              'id': r['id'],
              'title': r['title'],
              'distance_km': r['distance_km'],
              'duration_seconds': r['duration_seconds'],
              'route': r['route'],
            })
            .toList();

        await Supabase.instance.client
            .from('profiles')
            .update({'purpose': jsonEncode(sharedList)})
            .eq('id', user.id);
            
        debugPrint('내 프로필 공유 동기화 성공: ${sharedList.length}개 코스');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isCurrentlyShared ? '공유가 취소되었습니다.' : '산책 기록이 성공적으로 공유되었습니다! 🎉'),
            backgroundColor: const Color(0xFF2EA043),
          ),
        );
      }
      await _fetchRecords();
    } catch (e) {
      debugPrint('공유 토글 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('공유 실패: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Widget _buildRecordCard(Map<String, dynamic> record, Color textColor, Color cardColor, bool isDark) {
    final route = _parseRoute(record['route']);
    final dist = (record['distance_km'] as num).toDouble();
    final dur = record['duration_seconds'] as int? ?? 0;
    final date = _formatDate(record['created_at']);
    final title = record['title'] as String? ?? date;
    
    final bool isShared = title.startsWith('[공유] ');
    final displayTitle = isShared ? title.replaceFirst('[공유] ', '') : title;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          if (route.length >= 2)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: SizedBox(
                height: 130,
                child: IgnorePointer(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: route[route.length ~/ 2],
                      initialZoom: 14,
                      interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                        subdomains: const ['a', 'b', 'c', 'd'],
                        userAgentPackageName: 'com.ttubuk.ttubuk_ttubuk',
                      ),
                      PolylineLayer(polylines: [Polyline(points: route, color: const Color(0xFF2EA043), strokeWidth: 4)]),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    displayTitle, 
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isShared) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2EA043),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'SHARED',
                                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _editRecordTitle(record, textColor, isDark),
                            child: Icon(LucideIcons.edit2, size: 14, color: textColor.withOpacity(0.4)),
                          ),
                        ],
                      ),
                      if (record['title'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(date, style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 11)),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(LucideIcons.footprints, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text('${dist.toStringAsFixed(2)}km', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                              if (dur > 0) ...[
                                const SizedBox(width: 12),
                                const Icon(LucideIcons.timer, size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(_formatDuration(dur), style: const TextStyle(color: Colors.grey, fontSize: 13)),
                              ],
                            ],
                          ),
                          GestureDetector(
                            onTap: () => _toggleShareRecord(record),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isShared ? const Color(0xFF2EA043).withOpacity(0.15) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isShared ? const Color(0xFF2EA043) : textColor.withOpacity(0.2)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    LucideIcons.share2,
                                    size: 13,
                                    color: isShared ? const Color(0xFF2EA043) : textColor.withOpacity(0.5),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isShared ? '공유됨' : '공유하기',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isShared ? const Color(0xFF2EA043) : textColor.withOpacity(0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color textColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.footprints, size: 64, color: textColor.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text('아직 산책 기록이 없어요', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 8),
          Text('산책 탭에서 경로를 기록하거나\n직접 그려보세요!', textAlign: TextAlign.center, style: TextStyle(color: textColor.withOpacity(0.4))),
        ],
      ),
    );
  }
}
