import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/update_provider.dart';

/// 更新检查对话框
class UpdateDialog extends StatelessWidget {
  final bool forceUpdate;

  const UpdateDialog({super.key, this.forceUpdate = false});

  @override
  Widget build(BuildContext context) {
    return Consumer<UpdateProvider>(
      builder: (context, updateProvider, child) {
        final updateInfo = updateProvider.updateInfo;
        if (updateInfo == null) {
          return const SizedBox.shrink();
        }

        return PopScope(
          canPop: !forceUpdate && !updateProvider.isDownloading,
          child: AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.system_update, color: Colors.blue),
                const SizedBox(width: 8),
                Text(forceUpdate ? '发现强制更新' : '发现新版本'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 版本信息
                  _buildInfoRow('新版本', updateInfo.version),
                  _buildInfoRow('文件大小', updateInfo.formattedFileSize),
                  const SizedBox(height: 16),

                  // 更新日志
                  const Text(
                    '更新内容：',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      updateInfo.changelog.isEmpty
                          ? '暂无更新说明'
                          : updateInfo.changelog,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),

                  // 下载进度
                  if (updateProvider.isDownloading) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: updateProvider.downloadProgress,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        '${(updateProvider.downloadProgress * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],

                  // 错误信息
                  if (updateProvider.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              updateProvider.errorMessage!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: _buildActions(context, updateProvider),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }

  List<Widget> _buildActions(
    BuildContext context,
    UpdateProvider updateProvider,
  ) {
    // 下载中时显示取消按钮
    if (updateProvider.isDownloading) {
      return [
        TextButton(
          onPressed: updateProvider.cancelDownload,
          child: const Text('取消下载'),
        ),
      ];
    }

    // 已下载完成时显示安装按钮
    if (updateProvider.state == UpdateState.downloaded) {
      return [
        if (!forceUpdate)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后安装'),
          ),
        FilledButton.icon(
          onPressed: () => updateProvider.installUpdate(),
          icon: const Icon(Icons.install_mobile),
          label: const Text('立即安装'),
        ),
      ];
    }

    // 默认显示更新/取消按钮
    return [
      if (!forceUpdate)
        TextButton(
          onPressed: () {
            updateProvider.ignoreThisUpdate();
            Navigator.of(context).pop();
          },
          child: const Text('忽略'),
        ),
      if (!forceUpdate)
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('稍后提醒'),
        ),
      FilledButton.icon(
        onPressed: updateProvider.errorMessage != null
            ? () => updateProvider.downloadUpdate()
            : updateProvider.downloadUpdate,
        icon: const Icon(Icons.download),
        label: Text(updateProvider.errorMessage != null ? '重试' : '立即更新'),
      ),
    ];
  }

  /// 显示更新对话框
  static Future<void> show(
    BuildContext context, {
    bool forceUpdate = false,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (context) => UpdateDialog(forceUpdate: forceUpdate),
    );
  }
}

/// 检查更新按钮
class CheckUpdateButton extends StatefulWidget {
  const CheckUpdateButton({super.key});

  @override
  State<CheckUpdateButton> createState() => _CheckUpdateButtonState();
}

class _CheckUpdateButtonState extends State<CheckUpdateButton> {
  @override
  Widget build(BuildContext context) {
    return Consumer<UpdateProvider>(
      builder: (context, updateProvider, child) {
        final isChecking = updateProvider.state == UpdateState.checking;

        return ListTile(
          leading: const Icon(Icons.system_update),
          title: const Text('检查更新'),
          subtitle: updateProvider.errorMessage != null
              ? Text(
                  updateProvider.errorMessage!,
                  style: const TextStyle(color: Colors.red),
                )
              : null,
          trailing: isChecking
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right),
          onTap: isChecking
              ? null
              : () async {
                  await updateProvider.checkForUpdate();

                  if (!context.mounted) return;

                  if (updateProvider.state == UpdateState.available) {
                    UpdateDialog.show(
                      context,
                      forceUpdate:
                          updateProvider.updateInfo?.forceUpdate ?? false,
                    );
                  } else if (updateProvider.state == UpdateState.idle) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('已是最新版本')));
                  }
                },
        );
      },
    );
  }
}
