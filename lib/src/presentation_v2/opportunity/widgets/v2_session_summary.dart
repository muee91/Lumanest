part of '../v2_opportunity_page.dart';

class _V2SessionSummary extends StatelessWidget {
  const _V2SessionSummary({
    required this.stableId,
    required this.eyebrow,
    required this.title,
    required this.detail,
    required this.timeLabel,
    required this.accent,
  });

  final String stableId;
  final String eyebrow;
  final String title;
  final String detail;
  final String timeLabel;
  final Color accent;

  @override
  Widget build(BuildContext context) => Hero(
    tag: 'v2-opportunity:$stableId',
    transitionOnUserGestures: true,
    child: Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        decoration: BoxDecoration(
          color: V2Palette.paper,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: V2Palette.line.withValues(alpha: .72)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 5,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  eyebrow,
                  style: const TextStyle(
                    color: V2Palette.mutedInk,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: V2Palette.ink,
                fontSize: 30,
                height: 1.08,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              detail,
              style: const TextStyle(
                color: V2Palette.mutedInk,
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(CupertinoIcons.clock, color: accent, size: 18),
                const SizedBox(width: 8),
                Text(
                  timeLabel,
                  style: const TextStyle(
                    color: V2Palette.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
