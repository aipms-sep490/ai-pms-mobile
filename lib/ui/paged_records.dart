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
    this.showHeading = true,
  });
  final AuthController auth;
  final String path;
  final String title;
  final String emptyText;
  final Widget Function(BuildContext, Json, Future<void> Function()) item;
  final int revision;
  final List<Widget> leading;
  final bool showHeading;
  @override
  State<PagedRecords> createState() => _PagedRecordsState();
}

class _PagedRecordsState extends State<PagedRecords> {
  int _page = 1;
  int _loadVersion = 0;
  @override
  void didUpdateWidget(covariant PagedRecords oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path) {
      _page = 1;
      _loadVersion++;
    }
  }

  Future<PageData> _load(String path, int page) async {
    final version = ++_loadVersion;
    final separator = path.contains('?') ? '&' : '?';
    final data = PageData.fromJson(
      await widget.auth.request('$path${separator}page=$page&pageSize=20'),
    );
    // Move the actual page state too: later refreshes must not revisit a page
    // that disappeared after a mutation. A superseded request cannot move it.
    if (mounted &&
        version == _loadVersion &&
        widget.path == path &&
        _page == page &&
        data.items.isEmpty &&
        page > 1 &&
        data.totalPages < page) {
      setState(() => _page = data.totalPages < 1 ? 1 : data.totalPages);
    }
    return data;
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.path;
    final page = _page;
    return RemotePage<PageData>(
      key: ValueKey('$path/$page'),
      title: widget.title,
      showHeading: widget.showHeading,
      revision: widget.revision,
      leading: widget.leading,
      load: () => _load(path, page),
      content: (context, data, refresh) => [
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
}
