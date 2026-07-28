import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/subject_search.dart';
import '../models/unified_search.dart';

class SearchFilterSelection {
  final SubjectSearchSort sort;
  final UnifiedSearchOptions options;

  const SearchFilterSelection({required this.sort, required this.options});
}

class SearchFilterDrawer extends StatefulWidget {
  final SearchScope scope;
  final SubjectSearchSort initialSort;
  final UnifiedSearchOptions initialOptions;

  const SearchFilterDrawer({
    super.key,
    required this.scope,
    required this.initialSort,
    required this.initialOptions,
  });

  @override
  State<SearchFilterDrawer> createState() => _SearchFilterDrawerState();
}

class _SearchFilterDrawerState extends State<SearchFilterDrawer> {
  static const _careers = [
    'producer',
    'mangaka',
    'artist',
    'seiyu',
    'writer',
    'illustrator',
    'actor',
  ];

  late final TextEditingController _metaTagsController;
  late final TextEditingController _tagsController;
  late final TextEditingController _ratingMinController;
  late final TextEditingController _ratingMaxController;
  late final TextEditingController _ratingCountMinController;
  late final TextEditingController _ratingCountMaxController;
  late final TextEditingController _rankMinController;
  late final TextEditingController _rankMaxController;
  DateTime? _airDateFrom;
  DateTime? _airDateTo;
  late SubjectSearchSort _sort;
  late SearchNsfwMode _nsfwMode;
  late Set<String> _personCareers;
  String? _validationError;

  bool get _showSubjectFilters =>
      widget.scope == SearchScope.all || widget.scope == SearchScope.subjects;
  bool get _showNsfw => widget.scope != SearchScope.persons;
  bool get _showPersonFilters =>
      widget.scope == SearchScope.all || widget.scope == SearchScope.persons;

  @override
  void initState() {
    super.initState();
    final options = widget.initialOptions;
    _metaTagsController = TextEditingController(
      text: options.metaTags.join(', '),
    );
    _tagsController = TextEditingController(text: options.tags.join(', '));
    _ratingMinController = TextEditingController(
      text: options.ratingMin == null
          ? ''
          : formatSearchNumber(options.ratingMin!),
    );
    _ratingMaxController = TextEditingController(
      text: options.ratingMax == null
          ? ''
          : formatSearchNumber(options.ratingMax!),
    );
    _ratingCountMinController = TextEditingController(
      text: options.ratingCountMin?.toString() ?? '',
    );
    _ratingCountMaxController = TextEditingController(
      text: options.ratingCountMax?.toString() ?? '',
    );
    _rankMinController = TextEditingController(
      text: options.rankMin?.toString() ?? '',
    );
    _rankMaxController = TextEditingController(
      text: options.rankMax?.toString() ?? '',
    );
    _airDateFrom = options.airDateFrom;
    _airDateTo = options.airDateTo;
    _sort = widget.initialSort;
    _nsfwMode = options.nsfwMode;
    _personCareers = options.personCareers.toSet();
  }

  @override
  void dispose() {
    _metaTagsController.dispose();
    _tagsController.dispose();
    _ratingMinController.dispose();
    _ratingMaxController.dispose();
    _ratingCountMinController.dispose();
    _ratingCountMaxController.dispose();
    _rankMinController.dispose();
    _rankMaxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return AnimatedPadding(
      key: const Key('search_filter_drawer'),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Row(
              children: [
                Text('筛选与排序', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                TextButton(onPressed: _reset, child: const Text('重置')),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: '关闭',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_validationError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_validationError!),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_showSubjectFilters) ...[
                    _sectionTitle('条目筛选'),
                    DropdownButtonFormField<SubjectSearchSort>(
                      initialValue: _sort,
                      decoration: const InputDecoration(
                        labelText: '排序',
                        border: OutlineInputBorder(),
                      ),
                      items: SubjectSearchSort.values
                          .map(
                            (sort) => DropdownMenuItem(
                              value: sort,
                              child: Text(_sortLabel(sort)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _sort = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('search_meta_tags_field'),
                      controller: _metaTagsController,
                      decoration: const InputDecoration(
                        labelText: '公共标签（维基标签）',
                        hintText: '例如：原创, 童年；使用 -科幻 排除标签',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('search_tags_field'),
                      controller: _tagsController,
                      decoration: const InputDecoration(
                        labelText: '用户标签',
                        hintText: '多个标签用逗号分隔，标签之间为且关系',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '播出／发售日期',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _buildDateButton(
                          label: '起始日期',
                          value: _airDateFrom,
                          onPressed: () => _pickDate(isStart: true),
                          onClear: _airDateFrom == null
                              ? null
                              : () => setState(() => _airDateFrom = null),
                        ),
                        _buildDateButton(
                          label: '结束日期',
                          value: _airDateTo,
                          onPressed: () => _pickDate(isStart: false),
                          onClear: _airDateTo == null
                              ? null
                              : () => setState(() => _airDateTo = null),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildRangeFields(
                      label: '评分范围（0–10）',
                      minController: _ratingMinController,
                      maxController: _ratingMaxController,
                      decimal: true,
                    ),
                    const SizedBox(height: 16),
                    _buildRangeFields(
                      label: '评分人数',
                      minController: _ratingCountMinController,
                      maxController: _ratingCountMaxController,
                    ),
                    const SizedBox(height: 16),
                    _buildRangeFields(
                      label: '排名范围',
                      minController: _rankMinController,
                      maxController: _rankMaxController,
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (_showNsfw) ...[
                    if (!_showSubjectFilters) _sectionTitle('角色筛选'),
                    DropdownButtonFormField<SearchNsfwMode>(
                      initialValue: _nsfwMode,
                      decoration: const InputDecoration(
                        labelText: 'NSFW',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: SearchNsfwMode.any,
                          child: Text('不限'),
                        ),
                        DropdownMenuItem(
                          value: SearchNsfwMode.safeOnly,
                          child: Text('仅非成人内容'),
                        ),
                        DropdownMenuItem(
                          value: SearchNsfwMode.adultOnly,
                          child: Text('仅成人内容'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _nsfwMode = value);
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (_showPersonFilters) ...[
                    _sectionTitle('人物职业'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _careers
                          .map(
                            (career) => FilterChip(
                              key: Key('search_person_career_$career'),
                              label: Text(personCareerLabel(career)),
                              selected: _personCareers.contains(career),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _personCareers.add(career);
                                  } else {
                                    _personCareers.remove(career);
                                  }
                                });
                              },
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '选择多个职业时，官方接口会按“且”关系筛选。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  key: const Key('search_apply_filters_button'),
                  onPressed: _apply,
                  child: const Text('应用筛选'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(label, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _buildDateButton({
    required String label,
    required DateTime? value,
    required VoidCallback onPressed,
    required VoidCallback? onClear,
  }) {
    return InputChip(
      avatar: const Icon(Icons.calendar_today_outlined, size: 18),
      label: Text(
        value == null ? label : '$label：${formatSearchApiDate(value)}',
      ),
      onPressed: onPressed,
      onDeleted: onClear,
    );
  }

  Widget _buildRangeFields({
    required String label,
    required TextEditingController minController,
    required TextEditingController maxController,
    bool decimal = false,
  }) {
    final keyboardType = TextInputType.numberWithOptions(decimal: decimal);
    Widget field(TextEditingController controller, String fieldLabel) {
      return TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: fieldLabel,
          border: const OutlineInputBorder(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: field(minController, '最小值')),
            const SizedBox(width: 12),
            Expanded(child: field(maxController, '最大值')),
          ],
        ),
      ],
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initialDate = isStart
        ? (_airDateFrom ?? _airDateTo ?? DateTime.now())
        : (_airDateTo ?? _airDateFrom ?? DateTime.now());
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(DateTime.now().year + 10, 12, 31),
    );
    if (date == null || !mounted) return;
    setState(() {
      if (isStart) {
        _airDateFrom = date;
      } else {
        _airDateTo = date;
      }
    });
  }

  void _reset() {
    setState(() {
      _metaTagsController.clear();
      _tagsController.clear();
      _ratingMinController.clear();
      _ratingMaxController.clear();
      _ratingCountMinController.clear();
      _ratingCountMaxController.clear();
      _rankMinController.clear();
      _rankMaxController.clear();
      _airDateFrom = null;
      _airDateTo = null;
      _sort = SubjectSearchSort.match;
      _nsfwMode = SearchNsfwMode.any;
      _personCareers.clear();
      _validationError = null;
    });
  }

  void _apply() {
    try {
      final ratingMin = _parseDouble(_ratingMinController, '最低评分');
      final ratingMax = _parseDouble(_ratingMaxController, '最高评分');
      final ratingCountMin = _parseInt(_ratingCountMinController, '最少评分人数');
      final ratingCountMax = _parseInt(_ratingCountMaxController, '最多评分人数');
      final rankMin = _parseInt(_rankMinController, '最小排名');
      final rankMax = _parseInt(_rankMaxController, '最大排名');

      if ((ratingMin != null && (ratingMin < 0 || ratingMin > 10)) ||
          (ratingMax != null && (ratingMax < 0 || ratingMax > 10))) {
        throw const FormatException('评分必须在 0 到 10 之间');
      }
      _validateRange(ratingMin, ratingMax, '评分');
      _validateRange(ratingCountMin, ratingCountMax, '评分人数');
      _validateRange(rankMin, rankMax, '排名');
      if (_airDateFrom != null &&
          _airDateTo != null &&
          _airDateFrom!.isAfter(_airDateTo!)) {
        throw const FormatException('起始日期不能晚于结束日期');
      }

      Navigator.pop(
        context,
        SearchFilterSelection(
          sort: _sort,
          options: UnifiedSearchOptions(
            metaTags: _parseTags(_metaTagsController.text),
            tags: _parseTags(_tagsController.text),
            airDateFrom: _airDateFrom,
            airDateTo: _airDateTo,
            ratingMin: ratingMin,
            ratingMax: ratingMax,
            ratingCountMin: ratingCountMin,
            ratingCountMax: ratingCountMax,
            rankMin: rankMin,
            rankMax: rankMax,
            nsfwMode: _nsfwMode,
            personCareers: _careers
                .where(_personCareers.contains)
                .toList(growable: false),
          ),
        ),
      );
    } on FormatException catch (error) {
      setState(() => _validationError = error.message);
    }
  }

  double? _parseDouble(TextEditingController controller, String label) {
    final value = controller.text.trim();
    if (value.isEmpty) return null;
    final parsed = double.tryParse(value);
    if (parsed == null) throw FormatException('$label 必须是数字');
    return parsed;
  }

  int? _parseInt(TextEditingController controller, String label) {
    final value = controller.text.trim();
    if (value.isEmpty) return null;
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 0) {
      throw FormatException('$label 必须是非负整数');
    }
    return parsed;
  }

  void _validateRange(num? min, num? max, String label) {
    if (min != null && max != null && min > max) {
      throw FormatException('$label 的最小值不能大于最大值');
    }
  }

  List<String> _parseTags(String value) {
    final seen = <String>{};
    return value
        .split(RegExp(r'[,，\n]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && seen.add(item))
        .toList(growable: false);
  }
}

String _sortLabel(SubjectSearchSort sort) => switch (sort) {
  SubjectSearchSort.match => '匹配程度',
  SubjectSearchSort.heat => '收藏热度',
  SubjectSearchSort.rank => '排名',
  SubjectSearchSort.score => '评分',
};
