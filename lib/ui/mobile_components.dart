import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';

/// Native horizontal scrolling keeps category controls out of the reading axis.
class HorizontalChoices extends StatelessWidget {
  const HorizontalChoices({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.spacing = 8,
  });
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double spacing;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: padding,
    physics: const BouncingScrollPhysics(),
    child: Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: spacing),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: children[i],
          ),
        ],
      ],
    ),
  );
}

enum StatusTone { neutral, primary, success, warning, danger, info }

/// Semantic badge matching Web FAMS tinted pill badges with crisp hairline border.
class StatusBadge extends StatelessWidget {
  const StatusBadge(
    this.label, {
    super.key,
    this.tone = StatusTone.neutral,
    this.icon,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;

  static StatusTone toneForStatus(String? raw) => switch (raw?.toUpperCase()) {
    'DONE' ||
    'COMPLETED' ||
    'ACTIVE' ||
    'ACCEPTED' ||
    'APPROVED' ||
    'PUBLISHED' ||
    'HEALTHY' ||
    'GREEN' ||
    'READY' ||
    'REVIEWED' => StatusTone.success,
    'IN_PROGRESS' ||
    'IN_REVIEW' ||
    'SUBMITTED' ||
    'SCHEDULED' ||
    'OPEN' => StatusTone.info,
    'BLOCKED' ||
    'OVERDUE' ||
    'REJECTED' ||
    'DECLINED' ||
    'CRITICAL' ||
    'HIGH' ||
    'RED' ||
    'AT_RISK' => StatusTone.danger,
    'PENDING' ||
    'INVITED' ||
    'TENTATIVE' ||
    'DRAFT' ||
    'MEDIUM' ||
    'YELLOW' ||
    'WATCH' ||
    'WARNING' => StatusTone.warning,
    _ => StatusTone.neutral,
  };

  @override
  Widget build(BuildContext context) {
    final (fg, bg, border) = switch (tone) {
      StatusTone.primary => (
        AppColors.primary,
        AppColors.primarySoft,
        AppColors.attentionBorder,
      ),
      StatusTone.success => (
        AppColors.success,
        AppColors.successBg,
        AppColors.successBorder,
      ),
      StatusTone.warning => (
        AppColors.warning,
        AppColors.warningBg,
        AppColors.warningBorder,
      ),
      StatusTone.danger => (
        AppColors.danger,
        AppColors.dangerSoft,
        AppColors.dangerBorder,
      ),
      StatusTone.info => (
        AppColors.info,
        AppColors.infoBg,
        AppColors.infoBorder,
      ),
      StatusTone.neutral => (
        AppColors.textSoft,
        AppColors.surfaceMuted,
        AppColors.border,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Multidisciplinary tag aligned with Web FAMS major colors (SE / UIUX / AI / QA / IS).
class MajorTag extends StatelessWidget {
  const MajorTag(this.label, {super.key, this.code, this.colorHex});

  final String label;
  final String? code;
  final String? colorHex;

  @override
  Widget build(BuildContext context) {
    final custom = _parseHex(colorHex);
    final key = (code ?? label).toUpperCase();
    final (fg, bg) = custom != null
        ? (custom, custom.withAlpha(24))
        : key.contains('SE') || key.contains('IT') || key.contains('BACK')
        ? (const Color(0xFF1D4ED8), const Color(0xFFEFF6FF))
        : key.contains('UI') || key.contains('UX') || key.contains('DESIGN')
        ? (const Color(0xFF6D28D9), const Color(0xFFFAF5FF))
        : key.contains('AI') || key.contains('MKT')
        ? (const Color(0xFFA94808), const Color(0xFFFFF8F1))
        : key.contains('QA') || key.contains('TEST')
        ? (const Color(0xFF0B7B52), const Color(0xFFE8F9F1))
        : (const Color(0xFF475569), const Color(0xFFF1F5F9));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: fg.withAlpha(65)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  static Color? _parseHex(String? raw) {
    if (raw == null) return null;
    final clean = raw.trim().replaceFirst('#', '');
    if (clean.length != 6) return null;
    final parsed = int.tryParse(clean, radix: 16);
    return parsed == null ? null : Color(0xFF000000 | parsed);
  }
}

/// FAMS Brand Navy authority hero panel with subtle burnt-orange accent stripe.
class NavyHeroCard extends StatelessWidget {
  const NavyHeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.navy,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.navyRaised),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A222836),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 3.5, color: AppColors.attentionBorder),
        Padding(padding: padding, child: child),
      ],
    ),
  );
}

/// Warm FAMS attention banner (`--color-attention-bg` + `--color-attention-border`).
class AttentionBanner extends StatelessWidget {
  const AttentionBanner({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.info_outline,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.attentionBg,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.attentionBorder.withAlpha(140)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textSoft,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 10), action!],
            ],
          ),
        ),
      ],
    ),
  );
}

/// Compact section header row with optional trailing count/action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Semantics(
          header: true,
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              height: 1.35,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: AppColors.navy,
            ),
          ),
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
    ],
  );
}

/// Small live status dot for realtime SignalR connection visibility.
class LiveStatusPill extends StatelessWidget {
  const LiveStatusPill({
    super.key,
    required this.connected,
    this.reconnecting = false,
  });

  final bool connected;
  final bool reconnecting;

  @override
  Widget build(BuildContext context) {
    final color = connected
        ? AppColors.success
        : reconnecting
        ? AppColors.warning
        : AppColors.textMuted;
    final bg = connected
        ? AppColors.successBg
        : reconnecting
        ? AppColors.warningBg
        : AppColors.surfaceMuted;
    final label = connected
        ? 'Trực tiếp'
        : reconnecting
        ? 'Đang nối lại…'
        : 'Đồng bộ định kỳ';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
