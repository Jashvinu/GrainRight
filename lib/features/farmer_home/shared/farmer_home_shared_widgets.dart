part of '../../../screens/farmer_home_screen.dart';

class _PageScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback? onBack;
  final Future<void> Function()? onRefresh;
  final bool safeArea;

  const _PageScaffold({
    required this.title,
    required this.child,
    this.onBack,
    this.onRefresh,
    this.safeArea = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasHeader = title.trim().isNotEmpty || onBack != null;
    final content = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 160),
      children: [
        if (hasHeader) ...[
          Row(
            children: [
              if (onBack != null) ...[
                AppBackButton(onPressed: onBack),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  UiStrings.fromEnglish(title),
                  style: const TextStyle(
                    color: AppTheme.greenDark,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        child,
      ],
    );
    final pageContent = safeArea ? SafeArea(child: content) : content;
    return Material(
      color: AppTheme.surface,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFCF5), AppTheme.surface],
          ),
        ),
        child: onRefresh == null
            ? pageContent
            : RefreshIndicator(onRefresh: onRefresh!, child: pageContent),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final Color? tint;

  const _Panel({required this.child, this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tint ?? Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE3EADD)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.greenDark.withValues(alpha: 0.07),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(color: Colors.transparent, child: child),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatusPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final maxWidth = math.max(72.0, MediaQuery.sizeOf(context).width - 48);
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.greenPale,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.green),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              UiStrings.fromEnglish(label),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.greenDark,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
