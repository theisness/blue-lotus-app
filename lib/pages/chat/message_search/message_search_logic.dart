import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:common_utils/common_utils.dart';
import '../../../routes/app_pages.dart';
import '../../../routes/app_navigator.dart';

class MessageSearchLogic extends GetxController {
  final searchController = TextEditingController();
  final focusNode = FocusNode();
  
  // 搜索条件
  final searchText = ''.obs;
  final selectedDateRange = Rx<DateTimeRange?>(null);
  final selectedMessageTypes = <int>[].obs;
  final selectedSenderID = ''.obs; // 选中的发言人ID
  final isSearching = false.obs;
  
  // 成员缓存
  final conversationMembers = <PublicUserInfo>[].obs;
  
  // 搜索结果
  final searchResults = <Message>[].obs;
  final hasMoreResults = true.obs;
  
  // 分页参数
  int _currentPage = 1;
  final int _pageSize = 20;
  String? _lastClientMsgID; // 用于分页的最后一个消息ID
  
  // 获取当前页码（用于显示）
  int get currentPage => _currentPage;
  
  // 消息类型选项
  final messageTypeOptions = [
    {'type': MessageType.text, 'name': '文本消息'},
    {'type': MessageType.picture, 'name': '图片消息'},
    {'type': MessageType.video, 'name': '视频消息'},
    {'type': MessageType.voice, 'name': '语音消息'},
    {'type': MessageType.file, 'name': '文件消息'},
    {'type': MessageType.location, 'name': '位置消息'},
    {'type': MessageType.quote, 'name': '引用消息'},
    {'type': MessageType.card, 'name': '名片消息'},
  ];
  
  late ConversationInfo conversationInfo;
  
  @override
  void onInit() {
    super.onInit();
    conversationInfo = Get.arguments['conversationInfo'];
    
    // 监听搜索文本变化
    searchController.addListener(() {
      searchText.value = searchController.text;
    });
    
    // 初始化成员列表
    _loadConversationMembers();
  }
  
  @override
  void onClose() {
    searchController.dispose();
    focusNode.dispose();
    super.onClose();
  }
  
  // 选择日期范围
  void selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: Get.context!,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: selectedDateRange.value,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Styles.c_0089FF,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      selectedDateRange.value = picked;
    }
  }
  
  // 切换消息类型选择
  void toggleMessageType(int type) {
    if (selectedMessageTypes.contains(type)) {
      selectedMessageTypes.remove(type);
    } else {
      selectedMessageTypes.add(type);
    }
  }
  
  // 选择发言人
  void selectSender(String senderID) {
    selectedSenderID.value = senderID;
  }
  
  // 清除发言人选择
  void clearSenderSelection() {
    selectedSenderID.value = '';
  }
  
  // 加载会话成员列表
  Future<void> _loadConversationMembers() async {
    try {
      final members = await getConversationMembers();
      conversationMembers.assignAll(members);
    } catch (e) {
      Logger.print('加载会话成员失败: $e');
    }
  }
  
  // 获取会话成员列表
  Future<List<PublicUserInfo>> getConversationMembers() async {
    try {
      if (conversationInfo.conversationType == ConversationType.single) {
        // 单聊，返回对方用户信息
        final userInfo = await OpenIM.iMManager.userManager.getUsersInfo(userIDList: [conversationInfo.userID!]);
        return userInfo;
      } else {
        // 群聊，获取群成员
        final members = await OpenIM.iMManager.groupManager.getGroupMemberList(
          groupID: conversationInfo.groupID!,
          offset: 0,
          count: 1000, // 获取所有成员
        );
        final userIdList = members.map((member) => member.userID).toList();
        return await OpenIM.iMManager.userManager.getUsersInfo(userIDList: userIdList.whereType<String>().toList());
      }
    } catch (e) {
      Logger.print('获取会话成员失败: $e');
      return [];
    }
  }
  
  // 显示发言人选择对话框
  void showSenderSelectionDialog() async {
    if (conversationMembers.isEmpty) {
      await _loadConversationMembers();
    }
    
    if (conversationMembers.isEmpty) {
      IMViews.showToast('获取成员列表失败');
      return;
    }
    
    final result = await Get.dialog(
      AlertDialog(
        title: Text('选择发言人'),
        content: Container(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: conversationMembers.length,
            itemBuilder: (context, index) {
              final member = conversationMembers[index];
              return ListTile(
                leading: AvatarView(
                  width: 40,
                  height: 40,
                  url: member.faceURL,
                  text: member.nickname,
                  textStyle: Styles.ts_FFFFFF_12sp,
                ),
                title: Text(member.nickname ?? member.userID ?? ''),
                subtitle: Text(member.userID ?? ''),
                onTap: () {
                  selectSender(member.userID ?? '');
                  Get.back();
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () {
              clearSenderSelection();
              Get.back();
            },
            child: Text('清除选择'),
          ),
        ],
      ),
    );
  }
  
  // 清除所有搜索条件
  void clearSearchConditions() {
    searchController.clear();
    selectedDateRange.value = null;
    selectedMessageTypes.clear();
    selectedSenderID.value = '';
    searchResults.clear();
    _currentPage = 1;
    _lastClientMsgID = null;
    hasMoreResults.value = true;
  }
  
  // 重置搜索状态
  void resetSearchState() {
    searchResults.clear();
    _currentPage = 1;
    _lastClientMsgID = null;
    hasMoreResults.value = true;
    isSearching.value = false;
  }
  
  // 执行搜索
  void performSearch({bool loadMore = false}) async {
    if (!loadMore) {
      resetSearchState();
    } else {
      isSearching.value = true;
    }
    
    if (!hasMoreResults.value && loadMore) return;
    
    // 检查是否有搜索条件
    if (searchText.value.isEmpty && selectedMessageTypes.isEmpty) {
      IMViews.showToast('消息内容和消息类型至少需要选一个');
      return;
    }
    

    
    // 处理日期范围，如果没有选择则使用默认值
    int startTime = 0;
    int peroid = 0;
    if (selectedDateRange.value != null) {
      startTime = (selectedDateRange.value!.end.millisecondsSinceEpoch / 1000).round();
      peroid = (selectedDateRange.value!.end.millisecondsSinceEpoch / 1000).round() - startTime;
      Logger.print('开始时间：${startTime}，周期：${peroid}');
    }
    
    final keywordList = searchText.value.isNotEmpty ? [searchText.value] : [''];

    try {
      Logger.print('开始搜索，页码：$currentPage，开始消息ID：$_lastClientMsgID');
      // 执行搜索
      final result = await OpenIM.iMManager.messageManager.searchLocalMessages(
        conversationID: conversationInfo.conversationID,
        keywordList: keywordList,
        messageTypeList: selectedMessageTypes,
        searchTimePosition: startTime,
        searchTimePeriod: peroid,
        count: _pageSize,
        pageIndex: currentPage,
      );
      Logger.print('搜索结果：$result');
      var messages = result.searchResultItems?.first.messageList ?? [];
      
      // 按发言人筛选
      if (selectedSenderID.value.isNotEmpty) {
        messages = messages.where((message) => message.sendID == selectedSenderID.value).toList();
      }
      
      if (loadMore) {
        searchResults.addAll(messages);
      } else {
        searchResults.assignAll(messages);
      }
      
      // 更新分页信息
      if (messages.isNotEmpty) {
        _lastClientMsgID = messages.last.clientMsgID;
        hasMoreResults.value = messages.length >= _pageSize;
      } else {
        hasMoreResults.value = false;
      }

      if(searchResults.isEmpty){
        IMViews.showToast('未找到匹配结果');
      }
      // 如果不是加载更多，则导航到搜索结果页面
      if (!loadMore && searchResults.isNotEmpty) {
        try {
          Logger.print('准备跳转到搜索结果页面，结果数量: ${searchResults.length}');
          final result = await Get.toNamed(AppRoutes.messageSearchResults);
          Logger.print('从搜索结果页面返回: $result');
          // 如果从搜索结果页面返回了消息，则跳转到聊天页面
          if (result != null && result is Message) {
            Logger.print('准备跳转到聊天页面，消息ID: ${result.clientMsgID}');
            // 使用AppNavigator.startChat跳转到对应消息
            AppNavigator.startChat(
              conversationInfo: conversationInfo,
              searchMessage: result,
              offUntilHome: true,
            );
          }
        } catch (e) {
          Logger.print('跳转到搜索结果页面失败: $e');
        }
      }
      
    } catch (e) {
      Logger.print('搜索失败: $e');
      IMViews.showToast('搜索失败: $e');
    } finally {
      isSearching.value = false;
    }
  }
  
  // 加载更多搜索结果
  void loadMoreResults() {
    // 确保只有在未在搜索中且有更多结果时才加载
    if (!isSearching.value && hasMoreResults.value) {
      Logger.print('开始加载更多搜索结果，当前页码: $_currentPage');
      _currentPage++;
      performSearch(loadMore: true);
    } else {
      Logger.print('跳过加载更多 - 正在搜索: ${isSearching.value}, 有更多结果: ${hasMoreResults.value}');
    }
  }
  
  // 跳转到指定消息
  void jumpToMessage(Message message) {
    Logger.print('跳转到消息: ${message.clientMsgID}');
    // 先返回到聊天页面，然后传递搜索消息参数
    Get.back(result: message);
  }
  
  // 不重复栈导航到聊天页面
  void _navigateToChatWithoutDuplicates(Message searchMessage) {
    Logger.print('使用不重复栈导航到聊天页面');
    final arguments = {
      'conversationInfo': conversationInfo,
      'searchMessage': searchMessage,
    };
    
    // 检查当前是否已经在聊天页面
    if (Get.currentRoute == AppRoutes.chat) {
      // 如果当前已经是聊天页面，则替换参数
      Get.offNamed(
        AppRoutes.chat,
        arguments: arguments,
      );
    } else {
      // 否则使用preventDuplicates参数来防止重复页面
      Get.toNamed(
        AppRoutes.chat,
        arguments: arguments,
        preventDuplicates: true,
      );
    }
  }
  
  // 获取消息类型显示名称
  String getMessageTypeName(int type) {
    final option = messageTypeOptions.firstWhereOrNull((option) => option['type'] == type);
    return option?['name'] as String ?? '未知类型';
  }
  
  // 获取消息内容预览
  String getMessagePreview(Message message) {
    final contentType = message.contentType;
    switch (contentType) {
      case MessageType.text:
        return message.textElem?.content ?? '';
      case MessageType.picture:
        return '[图片]';
      case MessageType.video:
        return '[视频]';
      case MessageType.voice:
        return '[语音]';
      case MessageType.file:
        return '[文件] ${message.fileElem?.fileName ?? ''}';
      case MessageType.location:
        return '[位置]';
      case MessageType.quote:
        return '[引用消息]';
      case MessageType.card:
        return '[名片]';
      default:
        return '[未知消息类型]';
    }
  }
  
  // 格式化时间
  String formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateUtil.formatDate(date, format: 'yyyy-MM-dd HH:mm');
  }
  
  // 获取选中发言人的显示名称
  String getSelectedSenderName() {
    if (selectedSenderID.value.isEmpty) return '';
    
    // 从缓存中查找成员信息
    final member = conversationMembers.firstWhereOrNull((member) => member.userID == selectedSenderID.value);
    return member?.nickname ?? member?.userID ?? selectedSenderID.value;
  }
} 