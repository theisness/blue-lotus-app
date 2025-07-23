# 群组消息查询功能

## 功能概述

群组消息查询功能允许用户在群组聊天中搜索历史消息，支持多种搜索条件组合。

## 功能特性

### 1. 文本搜索
- 支持关键词搜索消息内容
- 实时输入提示
- 支持清空搜索条件

### 2. 时间范围过滤
- 支持选择日期范围
- 可选择从2020年至今的任意时间段
- 显示选择的时间范围

### 3. 消息类型过滤
- 支持多种消息类型：
  - 文本消息
  - 图片消息
  - 视频消息
  - 语音消息
  - 文件消息
  - 位置消息
  - 引用消息
  - 名片消息
- 支持多选过滤

### 4. 搜索结果展示
- 分页加载（每页20条消息）
- 显示消息发送者头像和昵称
- 显示消息发送时间
- 显示消息类型标签
- 显示消息内容预览
- 支持点击跳转到原消息位置

### 5. 用户体验
- 加载状态提示
- 空结果状态提示
- 错误处理
- 支持加载更多结果

## 使用方法

### 1. 进入消息查询页面
在群组设置页面点击"消息查询"按钮

### 2. 设置搜索条件
- 在搜索框中输入关键词
- 点击"时间范围"选择日期
- 点击消息类型标签进行多选

### 3. 执行搜索
点击"搜索"按钮开始搜索

### 4. 查看结果
- 浏览搜索结果列表
- 点击消息可跳转到原位置
- 滚动到底部加载更多结果

### 5. 清除条件
点击"清除"按钮重置所有搜索条件

## 技术实现

### 文件结构
```
lib/pages/chat/message_search/
├── message_search_binding.dart    # 依赖注入绑定
├── message_search_logic.dart      # 业务逻辑控制器
├── message_search_view.dart       # UI视图
└── README.md                      # 说明文档
```

### 核心类

#### MessageSearchLogic
- 管理搜索条件和状态
- 处理搜索逻辑
- 管理搜索结果数据
- 提供消息预览和格式化功能

#### MessageSearchPage
- 提供搜索界面
- 展示搜索结果
- 处理用户交互

### API调用
使用 OpenIM SDK 的 `searchLocalMessages` 方法进行本地消息搜索：

```dart
final result = await OpenIM.iMManager.messageManager.searchLocalMessages(
  conversationID: conversationInfo.conversationID,
  keywordList: searchText.value.isNotEmpty ? [searchText.value] : null,
  messageTypeList: selectedMessageTypes.isNotEmpty ? selectedMessageTypes : null,
  startTime: selectedDateRange.value?.start.millisecondsSinceEpoch,
  endTime: selectedDateRange.value?.end.add(Duration(days: 1)).millisecondsSinceEpoch,
  count: _pageSize,
  startClientMsgID: loadMore && searchResults.isNotEmpty 
      ? searchResults.last.clientMsgID 
      : '',
);
```

## 注意事项

1. 搜索功能基于本地消息数据库，需要确保消息已同步到本地
2. 时间范围选择会影响搜索性能，建议选择合理的时间范围
3. 消息类型过滤可以组合使用，提高搜索精度
4. 搜索结果按时间倒序排列（最新的消息在前）
5. 点击消息跳转功能需要配合聊天页面的消息定位功能使用

## 扩展功能

可以考虑添加以下扩展功能：
- 搜索结果高亮显示关键词
- 支持正则表达式搜索
- 搜索结果导出功能
- 搜索历史记录
- 高级搜索选项（如按发送者过滤） 