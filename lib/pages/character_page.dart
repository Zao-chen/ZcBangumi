import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/character.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

/// 角色详情页
class CharacterPage extends StatefulWidget {
  final Character? character;
  final int? characterId;

  const CharacterPage({
    super.key,
    this.character,
    this.characterId,
  });

  @override
  State<CharacterPage> createState() => _CharacterPageState();
}

class _CharacterPageState extends State<CharacterPage> {
  Character? _character;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.character != null) {
      _character = widget.character;
      _loading = false;
    } else if (widget.characterId != null) {
      _loadCharacter(widget.characterId!);
    }
  }

  String get _cacheKey => 'character_${_character?.id ?? widget.characterId}';

  Future<void> _loadCharacter(int characterId) async {
    final storage = context.read<StorageService>();

    // 先从缓存恢复
    if (_character == null) {
      final cached = storage.getCache(_cacheKey);
      if (cached is Map<String, dynamic>) {
        try {
          _character = Character.fromJson(cached);
        } catch (_) {}
      }
    }

    setState(() {
      _loading = _character == null;
      _error = null;
    });

    // 请求最新数据
    final api = context.read<ApiClient>();
    try {
      final character = await api.getCharacter(characterId);
      setState(() {
        _character = character;
        _error = null;
      });
      storage.setCache(_cacheKey, character.toJson());
    } catch (e) {
      if (_character == null) {
        setState(() => _error = '加载失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_loading && _character == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _character == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('角色')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => _loadCharacter(widget.characterId ?? 0),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_character == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('角色不存在')),
      );
    }

    final character = _character!;
    final imageUrl = character.images.isNotEmpty
        ? (character.images[0].large.isNotEmpty
            ? character.images[0].large
            : (character.images[0].medium.isNotEmpty
                ? character.images[0].medium
                : character.images[0].grid))
        : '';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // AppBar with image
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: imageUrl.isNotEmpty
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: colorScheme.surfaceContainerHighest,
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.person, size: 64),
                          ),
                        ),
                        // 渐变遮罩
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.2),
                                Colors.black.withValues(alpha: 0.6),
                              ],
                              stops: const [0.5, 1.0],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.person, size: 64),
                    ),
            ),
          ),
          // 内容
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 名字
                  Text(
                    character.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 类型和关系
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (character.type.isNotEmpty)
                        Chip(
                          label: Text(character.type),
                          backgroundColor: colorScheme.surfaceContainerHighest,
                        ),
                      if (character.relation.isNotEmpty)
                        Chip(
                          label: Text(character.relation),
                          backgroundColor:
                              colorScheme.primary.withValues(alpha: 0.2),
                          labelStyle: TextStyle(color: colorScheme.primary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // 简介
                  if (character.comment.isNotEmpty) ...[
                    Text(
                      '简介',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      character.comment,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  // 详细描述
                  if (character.summary.isNotEmpty) ...[
                    Text(
                      '详细描述',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      character.summary,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  // 详细信息
                  if (character.infobox.isNotEmpty) ...[
                    Text(
                      '详细信息',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      elevation: 0,
                      color: colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: character.infobox.entries
                              .map((entry) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 80,
                                        child: Text(
                                          entry.key,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          entry.value,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              })
                              .toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  // 收藏数
                  if (character.collects > 0) ...[
                    Text(
                      '人气',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.favorite_outline,
                            size: 18, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          '${character.collects} 次收藏',
                          style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
