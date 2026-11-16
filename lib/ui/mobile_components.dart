import 'package:material_ui/material_ui.dart';

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
