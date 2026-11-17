import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';

import '../core/api_client.dart';
import '../features/workspace/workspace_models.dart';
import 'app_theme.dart';

/// Shared loading/retry behavior for the student workspace's remote screens.
class RemotePage<T> extends StatefulWidget {
  const RemotePage({
    super.key,
    required this.title,
    required this.load,
    required this.content,
    this.revision = 0,
    this.actions = const [],
    this.leading = const [],
    this.errorActions = const [],
    this.showHeading = true,
  });
  final String title;
  final Future<T> Function() load;
  final List<Widget> Function(BuildContext, T, Future<void> Function()) content;
  final int revision;
  final List<Widget> actions;
  final List<Widget> leading;
  final List<Widget> errorActions;
  final bool showHeading;

  @override
  RemotePageState<T> createState() => RemotePageState<T>();
}

class RemotePageState<T> extends State<RemotePage<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;
  int _version = 0;
  Future<void> refresh() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RemotePage<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      _data = null;
      _load();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    final version = ++_version;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.load();
      if (!mounted || version != _version) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || version != _version) return;
      setState(() {
        _error = error;
        _loading = false;
        // A revoked/deleted resource must not leave its stale content visible.
        if (error is ApiException &&
            [401, 403, 404].contains(error.statusCode)) {
          _data = null;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: Semantics(
        customSemanticsActions: {
          CustomSemanticsAction(label: 'Làm mới ${widget.title.toLowerCase()}'):
              _load,
        },
        child: RefreshIndicator(
          onRefresh: _load,
          child: Stack(
            children: [
              ListView(
                key: PageStorageKey((widget.title, widget.key)),
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  if (widget.showHeading)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(
                              widget.title,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                          ),
                        ),
                        ...widget.actions,
                        IconButton(
                          tooltip: 'Làm mới ${widget.title.toLowerCase()}',
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          onPressed: _loading ? null : _load,
                          icon: _loading
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    semanticsLabel: 'Đang tải dữ liệu',
                                  ),
                                )
                              : const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  if (widget.showHeading)
                    const SizedBox(height: 18)
                  else if (widget.actions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        children: widget.actions,
                      ),
                    ),
                  ...widget.leading,
                  if (_error != null) ...[
                    Notice(
                      errorText(_error!),
                      retry: _loading ? null : _load,
                      detail: _data == null ? null : 'Đang hiển thị dữ liệu từ lần tải thành công gần nhất.',
                    ),
                    ...widget.errorActions,
                    const SizedBox(height: 16),
                  ],
                  if (_data != null)
                    ExcludeFocus(
                      excluding: _loading,
                      child: AbsorbPointer(
                        absorbing: _loading,
                        child: Semantics(
                          container: true,
                          explicitChildNodes: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: widget.content(
                              context,
                              _data as T,
                              _load,
                            ),
                          ),
                        ),
                      ),
                    )
                  else if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(height: 16),
                          Text('Đang tải dữ liệu…'),
                        ],
                      ),
                    ),
                ],
              ),
              if (_loading && _data != null && !widget.showHeading)
                const Positioned(
                  top: 0,
                  left: 20,
                  right: 20,
                  child: IgnorePointer(
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      semanticsLabel: 'Đang cập nhật dữ liệu',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class Notice extends StatelessWidget {
  const Notice(this.message, {super.key, this.detail, this.retry});
  final String message;
  final String? detail;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(color: AppColors.danger, height: 1.5),
          ),
          if (detail != null) ...[const SizedBox(height: 8), Text(detail!)],
          if (retry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ],
      ),
    ),
  );
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: AppColors.border),
      borderRadius: BorderRadius.circular(20),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class ContentSection extends StatelessWidget {
  const ContentSection(this.title, this.content, {super.key});
  final String title;
  final String? content;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (content != null) ...[
          const SizedBox(height: 8),
          SelectableBody(
            content!.trim().isEmpty ? 'Chưa có thông tin.' : content!,
          ),
        ],
      ],
    ),
  );
}

class SelectableBody extends StatelessWidget {
  const SelectableBody(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: text,
    excludeSemantics: true,
    child: SelectionArea(
      child: Text(text, style: style ?? Theme.of(context).textTheme.bodyLarge),
    ),
  );
}

class RecordTile extends StatelessWidget {
  const RecordTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.article_outlined,
    this.onTap,
    this.urgent = false,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool urgent;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: onTap != null,
    label: '$title\n$subtitle',
    onTap: onTap,
    child: ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: urgent
                            ? AppColors.dangerSoft
                            : AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        icon,
                        size: 20,
                        color: urgent ? AppColors.danger : AppColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: onTap == null ? null : 2,
                          overflow: onTap == null
                              ? null
                              : TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          maxLines: onTap == null ? null : 3,
                          overflow: onTap == null
                              ? null
                              : TextOverflow.ellipsis,
                          style: TextStyle(
                            height: 1.5,
                            color: urgent
                                ? AppColors.danger
                                : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, color: AppColors.textMuted),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class Pagination extends StatelessWidget {
  const Pagination({super.key, required this.data, required this.change});
  final PageData data;
  final ValueChanged<int> change;
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12,
    runSpacing: 8,
    children: [
      IconButton(
        tooltip: 'Trang trước',
        onPressed: data.page > 1 ? () => change(data.page - 1) : null,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: const Icon(Icons.chevron_left),
      ),
      Text(
        'Trang ${data.page}/${data.totalPages == 0 ? 1 : data.totalPages} · ${data.totalCount} mục',
      ),
      IconButton(
        tooltip: 'Trang sau',
        onPressed: data.page < data.totalPages
            ? () => change(data.page + 1)
            : null,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
}
