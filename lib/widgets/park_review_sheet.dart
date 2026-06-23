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
            content: Text('?„ê¸°ê°€ ?±ë¡?˜ì—ˆ?µë‹ˆ??'),
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
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 22),
                    const SizedBox(width: 6),
                    Text(
                      _summary.count > 0 || _summary.isGoogleRating
                          ? '${_summary.averageRating.toStringAsFixed(1)} (${_summary.count}ê°??„ê¸°${_summary.isGoogleRating ? ' - êµ¬ê? ë§?ê¸°ì?' : ''})'
                          : '?„ì§ ?„ê¸°ê°€ ?†ì–´??,
                      style: TextStyle(fontSize: 14, color: textColor.withOpacity(0.7)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('ë³„ì  ?¨ê¸°ê¸?, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
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
                    hintText: '?°ì±… ?„ê¸°ë¥??¨ê²¨ì£¼ì„¸??(? íƒ)',
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
                    ),
                    child: Text(_submitting ? '?±ë¡ ì¤?..' : '?„ê¸° ?±ë¡'),
                  ),
                ),
                const SizedBox(height: 24),
                Text('ìµœê·¼ ?„ê¸°', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                const SizedBox(height: 10),
                if (_reviews.isEmpty)
                  Text('ì²??„ê¸°ë¥??¨ê²¨ë³´ì„¸??', style: TextStyle(color: textColor.withOpacity(0.5)))
                else
                  ..._reviews.map((r) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: textColor.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(12),
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
                                const Spacer(),
                                Text(
                                  r.userName ?? '?µëª…',
                                  style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.4)),
                                ),
                              ],
                            ),
                            if (r.content != null && r.content!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(r.content!, style: TextStyle(fontSize: 13, color: textColor)),
                            ],
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
