import 'package:material_ui/material_ui.dart';

import '../features/auth/auth_controller.dart';
import '../features/workspace/workspace_models.dart';
import 'remote_page.dart';

class PagedRecords extends StatefulWidget {
  const PagedRecords({
    super.key,
    required this.auth,
    required this.path,
    required this.title,
    required this.item,
    required this.emptyText,
    this.revision = 0,
    this.leading = const [],
  });
  final AuthController auth;
  final String path;
  final String title;
  final String emptyText;
  final Widget Function(BuildContext, Json, Future<void> Function()) item;
  final int revision;
  final List<Widget> leading;
  @override
  State<PagedRecords> createState() => _PagedRecordsState();
}

class _PagedRecordsState extends State<PagedRecords> {
  int _page = 1;
  @override
  void didUpdateWidget(covariant PagedRecords oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path) _page = 1;
  }

  @override
  Widget build(BuildContext context) => RemotePage<PageData>(
    key: ValueKey('${widget.path}/$_page'),
    title: widget.title,
    revision: widget.revision,
    load: () async {
      final separator = widget.path.contains('?') ? '&' : '?';
      final data = PageData.fromJson(
        await widget.auth.request(
          '${widget.path}${separator}page=$_page&pageSize=20',
        ),
      );
      // The last item on a page can disappear after a mutation.
      if (data.items.isEmpty && _page > 1 && data.totalPages < _page) {
        final page = data.totalPages < 1 ? 1 : data.totalPages;
        return PageData.fromJson(
          await widget.auth.request(
            '${widget.path}${separator}page=$page&pageSize=20',
          ),
        );
      }
      return data;
    },
    content: (context, data, refresh) => [
      ...widget.leading,
      if (data.items.isEmpty) Surface(child: Text(widget.emptyText)),
      for (final row in data.items) widget.item(context, row, refresh),
      const SizedBox(height: 8),
      Pagination(
        data: data,
        change: (page) => setState(() {
          _page = page;
        }),
      ),
    ],
  );
}
