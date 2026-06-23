import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/recommendation_feedback_service.dart';

/// AI 異붿쿇???�???쇰뱶諛??섏쭛 (援ъ꽦?? Model Training 猷⑦봽)
class RecommendationFeedbackBar extends StatefulWidget {
  final String? parkName;
  final String? moodId;
  final String? routeName;
  final VoidCallback? onFeedbackRecorded;

  const RecommendationFeedbackBar({
    super.key,
    this.parkName,
    this.moodId,
    this.routeName,
    this.onFeedbackRecorded,
  });

  @override
  State<RecommendationFeedbackBar> createState() =>
      _RecommendationFeedbackBarState();
}

class _RecommendationFeedbackBarState extends State<RecommendationFeedbackBar> {
  bool _submitted = false;

  Future<void> _submit(bool positive) async {
    final name = widget.parkName;
    if (name == null || name.isEmpty || _submitted) return;

    await RecommendationFeedbackService.recordFeedback(
      parkName: name,
      isPositive: positive,
      moodId: widget.moodId,
      routeName: widget.routeName,
    );

    if (!mounted) return;
    setState(() => _submitted = true);
    widget.onFeedbackRecorded?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          positive ? '?꾩????먮떎??湲곕퍙?? ?ㅼ쓬 異붿쿇??諛섏쁺?좉쾶??' : '?쇰뱶諛?媛먯궗?댁슂. ???섏? 肄붿뒪瑜?李얠븘蹂쇨쾶??',
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2EA043),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.parkName == null) return const SizedBox.shrink();

    if (_submitted) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          '?쇰뱶諛깆씠 諛섏쁺?섏뿀?듬땲?? 媛먯궗?⑸땲??',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white54
                : Colors.black45,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Text(
            '??異붿쿇???꾩????먮굹??',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(LucideIcons.thumbsUp, size: 18, color: Color(0xFF2EA043)),
            onPressed: () => _submit(true),
            tooltip: '좋아요',
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(LucideIcons.thumbsDown, size: 18, color: Colors.grey.shade500),
            onPressed: () => _submit(false),
            tooltip: '?꾩돩?뚯슂',
          ),
        ],
      ),
    );
  }
}
