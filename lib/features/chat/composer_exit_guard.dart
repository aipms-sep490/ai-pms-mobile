import 'package:material_ui/material_ui.dart';

/// Keep an unsent composer in memory until its owner explicitly leaves.
class ComposerExitGuard extends StatefulWidget {
  const ComposerExitGuard({
    super.key,
    required this.controller,
    required this.sending,
    required this.hasContext,
    required this.child,
  });
  final TextEditingController controller;
  final bool sending;
  final bool hasContext;
  final Widget child;

  @override
  State<ComposerExitGuard> createState() => _ComposerExitGuardState();
}

class _ComposerExitGuardState extends State<ComposerExitGuard> {
  bool _confirming = false;

  Future<void> _leave(bool didPop) async {
    if (didPop || _confirming) return;
    if (widget.sending) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Đang gửi. Vui lòng chờ kết quả trước khi rời hội thoại.',
          ),
        ),
      );
      return;
    }
    _confirming = true;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          scrollable: true,
          title: const Text('Bỏ tin đang soạn?'),
          content: const Text('Nội dung và tệp đang soạn chưa được gửi.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Tiếp tục soạn'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Bỏ bản soạn'),
            ),
          ],
        ),
      );
      if (discard == true && mounted) Navigator.pop(context);
    } finally {
      _confirming = false;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    child: widget.child,
    builder: (context, child) => PopScope(
      canPop:
          !widget.sending &&
          !widget.hasContext &&
          widget.controller.text.trim().isEmpty,
      onPopInvokedWithResult: (didPop, _) => _leave(didPop),
      child: child!,
    ),
  );
}
