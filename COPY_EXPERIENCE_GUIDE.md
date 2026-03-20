# 复制体验改进指南

## 概述
为应用添加了智能复制体验，在不同场景下提供最佳的文本复制和选取方式。

## 核心组件

### 1. CopyableText - 智能可复制文本
用于各种长度的内容文本。根据文本长度智能切换行为：

```dart
// 长文本（>50字符）或多行文本：支持鼠标选取和触屏选取
CopyableText(
  subjectSummary,
  style: TextStyle(...),
  enableLongPressCopy: false, // 长文本不启用长按复制
)

// 短文本（<50字符）或标题：长按复制，不支持选取
CopyableText(
  shortTitle,
  style: TextStyle(...),
  enableLongPressCopy: true, // 启用长按复制
)
```

**特征：**
- 自动区分短/长文本
- 长文本使用 SelectableText（支持鼠标选取）
- 短文本支持长按复制
- 跨平台支持（iOS、Android、Web、Windows等）

### 2. ShortCopyableText - 短文本长按复制
专门用于标题、标签等短文本内容。

```dart
ShortCopyableText(
  displayName,
  maxLines: 2,
  overflow: TextOverflow.ellipsis,
  style: TextStyle(...),
)
```

**特征：**
- 长按显示"已复制"吐司提示
- 纯长按复制，不支持文本选取
- 简洁高效

### 3. CopyableChip - 可复制的标签
用于单个标签或标签组。

```dart
// 单个标签
CopyableChip(
  label: tagName,
  labelStyle: TextStyle(fontSize: 12),
  backgroundColor: surfaceColor,
)

// 标签组
Wrap(
  children: tags.map((tag) => CopyableChip(label: tag)).toList(),
)
```

**特征：**
- 长按复制标签内容
- Tooltip提示"长按复制"
- 集成到Chip UI中

## 用户交互

### 触屏设备
- **短内容**（标题、标签）：长按 → 复制 → 吐司提示
- **长文本**：手指选取 → 系统菜单复制

### 鼠标设备  
- **短内容**：长按 → 复制 → 吐司提示
- **长文本**：鼠标拖选 → 系统菜单复制

## 已应用的页面

### SubjectPage（番剧详情页）
- ✅ 标题和原始名称（displayName, name）
- ✅ 简介（summary）
- ✅ 标签（tags）
- ✅ 详情框的键值对

### CharacterPage（角色详情页）
- ✅ 角色名称（name）
- ✅ 简介（comment）
- ✅ 详细描述（summary）
- ✅ 详情框的键值对

### ProfilePage（用户信息页）
- ✅ 用户昵称（nickname）
- ✅ 用户名（username）

## 实现细节

### SelectableText的使用
CopyableText 使用 Flutter 内置的 SelectableText widget 来:
- 在桌面平台（Web、Windows、macOS）上支持鼠标选取
- 在移动平台（iOS、Android）上支持触屏文字选取
- 自动处理系统级别的复制菜单

### 复制反馈
- 使用 Clipboard 类处理系统剪贴板
- SnackBar 显示"已复制"提示（800ms自自动隐藏）
- Floating 行为，不遮挡主要内容

## 文件结构
```
lib/
├── widgets/
│   ├── copyable_text.dart       # CopyableText 和 ShortCopyableText
│   └── copyable_chip.dart       # CopyableChip
├── pages/
│   ├── subject_page.dart        # ✅ 已更新
│   ├── character_page.dart      # ✅ 已更新
│   └── profile_page.dart        # ✅ 已更新
```

## 扩展到其他页面

要在其他页面添加复制体验，只需：

1. 导入组件：
```dart
import '../widgets/copyable_text.dart';
import '../widgets/copyable_chip.dart';
```

2. 替换 Text widget：
```dart
// 替换前
Text(title)

// 替换后（短标题）
ShortCopyableText(title)

// 替换后（长文本）
CopyableText(description, enableLongPressCopy: false)
```

3. 替换 Chip widget：
```dart
// 替换前
Chip(label: Text(tag))

// 替换后
CopyableChip(label: tag)
```

## 浏览器/平台支持
- ✅ iOS（触屏选取）
- ✅ Android（触屏选取）
- ✅ Web（鼠标选取）
- ✅ Windows（鼠标选取）
- ✅ macOS（鼠标选取）
- ✅ Linux（鼠标选取）
