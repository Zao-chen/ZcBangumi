import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';

import '../services/app_log_service.dart';

class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  late Future<List<AppLogEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = _loadEntries();
  }

  Future<List<AppLogEntry>> _loadEntries() {
    return context.read<AppLogService>().readEntries();
  }

  void _refresh() {
    setState(() {
      _entriesFuture = _loadEntries();
    });
  }

  Future<void> _copyAll() async {
    final logService = context.read<AppLogService>();
    final text = await logService.readText();
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('日志已复制')));
  }

  Future<void> _export() async {
    final logService = context.read<AppLogService>();
    final file = await logService.exportLogFile();
    await logService.info('log', '日志已导出: ${file.path}');
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('日志已导出到 ${file.path}')));
    await OpenFile.open(file.path);
    _refresh();
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空日志'),
        content: const Text('将删除当前本地诊断日志，后续问题会继续记录新日志。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<AppLogService>().clear();
    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('日志已清空')));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('诊断日志'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<_LogAction>(
            onSelected: (action) {
              switch (action) {
                case _LogAction.copy:
                  _copyAll();
                case _LogAction.export:
                  _export();
                case _LogAction.clear:
                  _clear();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _LogAction.copy,
                child: ListTile(
                  leading: Icon(Icons.copy_rounded),
                  title: Text('复制全部'),
                ),
              ),
              PopupMenuItem(
                value: _LogAction.export,
                child: ListTile(
                  leading: Icon(Icons.ios_share_rounded),
                  title: Text('导出日志文件'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _LogAction.clear,
                child: ListTile(
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('清空日志'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<AppLogEntry>>(
        future: _entriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '日志读取失败: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final entries = snapshot.data ?? const [];
          if (entries.isEmpty) {
            return Center(
              child: Text(
                '暂无日志',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              return _LogEntryTile(entry: entries[index]);
            },
          );
        },
      ),
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final AppLogEntry entry;

  const _LogEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final levelColor = switch (entry.level) {
      'ERROR' => colorScheme.error,
      'WARN' => colorScheme.tertiary,
      _ => colorScheme.primary,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: levelColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    entry.level,
                    style: TextStyle(
                      color: levelColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  entry.category,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Spacer(),
                Text(
                  _formatTime(entry.time),
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(entry.message),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}

enum _LogAction { copy, export, clear }
