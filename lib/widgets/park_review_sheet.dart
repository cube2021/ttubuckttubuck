import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/park_review_service.dart';

class ParkReviewSheet extends StatefulWidget {
  final String parkName;

  const ParkReviewSheet({super.key, required this.parkName});

  @override
  State<ParkReviewSheet> createState() => _ParkReviewSheetState();
}

class _ParkReviewSheetState extends State<ParkReviewSheet> {
  ParkReviewSummary _summary = const ParkReviewSummary();
  List<ParkReview> _reviews = [];
  int _myRating = 5;
  final _contentController = TextEditingController();
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final summary = await ParkReviewService.getSummary(widget.parkName);
    final reviews = await ParkReviewService.getReviews(widget.parkName);
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _reviews = reviews;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await ParkReviewService.submitReview(
        parkName: widget.parkName,
        rating: _myRating,
        content: _contentController.text,
      );
      _contentController.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('후기가 등록되었습니다!'),
            backgroundColor: Color(0xFF2EA043),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF242424) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.parkName,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator(color: Color(0xFF2EA043))),
                )
              else ...[
                // 평점 요약
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 22),
                    const SizedBox(width: 6),
                    Text(
                      _summary.count > 0 || _summary.isGoogleRating
                          ? '${_summary.averageRating.toStringAsFixed(1)} (${_summary.count}개 후기${_summary.isGoogleRating ? ' · 구글 평점' : ''})'
                          : '아직 후기가 없어요',
                      style: TextStyle(fontSize: 14, color: textColor.withOpacity(0.7)),
                    ),
                    if (_summary.isGoogleRating) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.blue.withOpacity(0.3)),
                        ),
                        child: const Text(
                          'Google',
                          style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                Text('별점 남기기', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(5, (i) {
                    final star = i + 1;
                    return IconButton(
                      onPressed: () => setState(() => _myRating = star),
                      icon: Icon(
                        star <= _myRating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                      ),
                    );
                  }),
                ),
                TextField(
                  controller: _contentController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: '산책 후기를 남겨주세요 (선택)',
                    filled: true,
                    fillColor: textColor.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2EA043),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(_submitting ? '등록 중...' : '후기 등록'),
                  ),
                ),
                const SizedBox(height: 24),
                Text('최근 후기', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                const SizedBox(height: 10),
                if (_reviews.isEmpty)
                  Text('첫 후기를 남겨보세요!', style: TextStyle(color: textColor.withOpacity(0.5)))
                else
                  ..._reviews.map((r) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: textColor.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: textColor.withOpacity(0.06)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ...List.generate(
                                  r.rating,
                                  (_) => const Icon(Icons.star, size: 14, color: Colors.amber),
                                ),
                                ...List.generate(
                                  5 - r.rating,
                                  (_) => Icon(Icons.star_border, size: 14, color: Colors.grey.withOpacity(0.4)),
                                ),
                                const Spacer(),
                                Text(
                                  r.userName ?? '익명',
                                  style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.4)),
                                ),
                              ],
                            ),
                            if (r.content != null && r.content!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(r.content!, style: TextStyle(fontSize: 13, color: textColor)),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              '${r.createdAt.year}.${r.createdAt.month.toString().padLeft(2, '0')}.${r.createdAt.day.toString().padLeft(2, '0')}',
                              style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.3)),
                            ),
                          ],
                        ),
                      )),
              ],
            ],
          ),
        );
      },
    );
  }
}
