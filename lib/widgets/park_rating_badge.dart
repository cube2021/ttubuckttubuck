import 'package:flutter/material.dart';
import '../services/park_review_service.dart';

/// 공원 카드 우측 평점 뱃지 (비동기 로드)
class ParkRatingBadge extends StatefulWidget {
  final String parkName;
  final Color textColor;
  
  const ParkRatingBadge({super.key, required this.parkName, required this.textColor});

  @override
  State<ParkRatingBadge> createState() => _ParkRatingBadgeState();
}

class _ParkRatingBadgeState extends State<ParkRatingBadge> {
  ParkReviewSummary? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await ParkReviewService.getSummary(widget.parkName);
    if (mounted) setState(() => _summary = s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    final hasRating = s != null && (s.count > 0 || s.isGoogleRating);
    final rating = s?.averageRating ?? 0.0;
    final isGoogle = s?.isGoogleRating ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: hasRating
            ? Colors.amber.withOpacity(0.12)
            : widget.textColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasRating ? Colors.amber.withOpacity(0.4) : widget.textColor.withOpacity(0.1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star_rounded,
            size: 16,
            color: hasRating ? Colors.amber : widget.textColor.withOpacity(0.3),
          ),
          const SizedBox(height: 2),
          if (s == null)
            SizedBox(
              width: 12, height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: widget.textColor.withOpacity(0.3),
              ),
            )
          else if (hasRating)
            Column(
              children: [
                Text(
                  rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
                if (isGoogle)
                  const Text(
                    'G',
                    style: TextStyle(fontSize: 8, color: Colors.amber),
                  ),
              ],
            )
          else
            Text(
              '평가',
              style: TextStyle(fontSize: 9, color: widget.textColor.withOpacity(0.4)),
            ),
        ],
      ),
    );
  }
}
