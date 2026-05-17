import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:common_utils/common_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mime/mime.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sprintf/sprintf.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_compress/video_compress.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';
import 'package:openim_live/openim_live.dart';
// import 'package:flutter_openim_live_alert/flutter_openim_live_alert.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/controller/app_controller.dart';
import '../../core/controller/im_controller.dart';
import '../../core/im_callback.dart';
import '../../routes/app_navigator.dart';
import '../contacts/select_contacts/select_contacts_logic.dart';
import '../conversation/conversation_logic.dart';
import 'group_setup/group_member_list/group_member_list_logic.dart';

class ChatLogic extends SuperController {
  final imLogic = Get.find<IMController>();
  final appLogic = Get.find<AppController>();
  final conversationLogic = Get.find<ConversationLogic>();
  final cacheLogic = Get.find<CacheController>();
  final downloadLogic = Get.find<DownloadController>();

  final inputCtrl = TextEditingController();
  final focusNode = FocusNode();
  final scrollController = ScrollController();
  final refreshController = RefreshController();
  bool playOnce = false; // 点击的当前视频只能播放一次

  final forceCloseToolbox = PublishSubject<bool>();
  final forceCloseMenuSub = PublishSubject<bool>();
  final sendStatusSub = PublishSubject<MsgStreamEv<bool>>();

  late ConversationInfo conversationInfo;
  Message? searchMessage;
  final nickname = ''.obs;
  final faceUrl = ''.obs;
  Timer? typingTimer;
  final typing = false.obs;
  Timer? _debounce;
  Message? quoteMsg;
  final messageList = <Message>[].obs;
  final tempMessages = <Message>[]; // 临时存放消息体，例如图片消息
  var _lastCursorIndex = -1;
  final onlineStatus = false.obs;
  final onlineStatusDesc = ''.obs;
  Timer? onlineStatusTimer;
  final favoriteList = <String>[].obs;
  final scaleFactor = Config.textScaleFactor.obs;
  final background = "".obs;
  final memberUpdateInfoMap = <String, GroupMembersInfo>{};
  final groupMessageReadMembers = <String, List<String>>{};
  final groupMutedStatus = 0.obs;
  final groupMemberRoleLevel = 1.obs;
  final muteEndTime = 0.obs;
  GroupInfo? groupInfo;
  GroupMembersInfo? groupMembersInfo;
  List<GroupMembersInfo> ownerAndAdmin = [];

  final isInGroup = true.obs;
  final memberCount = 0.obs;
  final privateMessageList = <Message>[];
  final isInBlacklist = false.obs;
  final _audioPlayer = AudioPlayer();
  final _currentPlayClientMsgID = "".obs;
  final isShowPopMenu = false.obs;

  final scrollingCacheMessageList = <Message>[];
  final announcement = ''.obs;
  late StreamSubscription conversationSub;
  late StreamSubscription memberAddSub;
  late StreamSubscription memberDelSub;
  late StreamSubscription joinedGroupAddedSub;
  late StreamSubscription joinedGroupDeletedSub;
  late StreamSubscription memberInfoChangedSub;
  late StreamSubscription groupInfoUpdatedSub;
  late StreamSubscription friendInfoChangedSub;
  StreamSubscription? userStatusChangedSub;
  StreamSubscription? selfInfoUpdatedSub;

  late StreamSubscription connectionSub;
  final syncStatus = IMSdkStatus.syncEnded.obs;
  int? lastMinSeq;

  final showCallingMember = false.obs;

  bool _isReceivedMessageWhenSyncing = false;
  bool _isStartSyncing = false;
  bool _isFirstLoad = true;
  bool _isLoadingHistoryForSearch = false; // 防止搜索时重复拉取历史消息

  final copyTextMap = <String?, String?>{};
  final revokedTextMessage = <String, String>{};

  String? groupOwnerID;

  final _pageSize = 40;
  
  // 用于获取消息项实际高度的GlobalKey映射
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};

  RTCBridge? get rtcBridge => PackageBridge.rtcBridge;

  bool get rtcIsBusy => rtcBridge?.hasConnection == true;

  String? get userID => conversationInfo.userID;

  String? get groupID => conversationInfo.groupID;

  bool get isSingleChat => null != userID && userID!.trim().isNotEmpty;

  bool get isGroupChat => null != groupID && groupID!.trim().isNotEmpty;

  String get memberStr => isSingleChat ? "" : "($memberCount)";

  String? get senderName => isSingleChat ? OpenIM.iMManager.userInfo.nickname : groupMembersInfo?.nickname;

  bool get isAdminOrOwner =>
      groupMemberRoleLevel.value == GroupRoleLevel.admin || groupMemberRoleLevel.value == GroupRoleLevel.owner;

  final directionalUsers = <GroupMembersInfo>[].obs;

  bool isCurrentChat(Message message) {
    var senderId = message.sendID;
    var receiverId = message.recvID;
    var groupId = message.groupID;

    var isCurSingleChat = message.isSingleChat &&
        isSingleChat &&
        (senderId == userID || senderId == OpenIM.iMManager.userID && receiverId == userID);
    var isCurGroupChat = message.isGroupChat && isGroupChat && groupID == groupId;
    
    final result = isCurSingleChat || isCurGroupChat;
    Logger.print('检查消息是否属于当前聊天 - 消息ID: ${message.clientMsgID}, 结果: $result');
    Logger.print('消息详情 - 发送者: $senderId, 接收者: $receiverId, 群组: $groupId');
    Logger.print('当前会话 - 用户ID: $userID, 群组ID: $groupID');
    Logger.print('判断结果 - 单聊: $isCurSingleChat, 群聊: $isCurGroupChat');
    
    return result;
  }

  void scrollBottom() {
    Logger.print('滚动到底部');
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      Logger.print('执行滚动到底部操作');
      scrollController.jumpTo(0);
    });
  }
  


  Future<void> _locateToMessage(Message targetMessage) async {
    Logger.print('=== 开始定位到消息 ===');
    Logger.print('目标消息ID: ${targetMessage.clientMsgID}');
    Logger.print('目标消息内容: ${targetMessage.toJson()}');
    
    // 等待消息列表初始化完成
    Logger.print('等待消息列表初始化完成...');
    await _waitForMessageListInitialized();
    Logger.print('消息列表初始化完成，当前长度: ${messageList.length}');
    
    // 如果正在为搜索加载历史消息，等待完成
    if (_isLoadingHistoryForSearch) {
      Logger.print('正在为搜索加载历史消息，等待完成...');
      while (_isLoadingHistoryForSearch) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      Logger.print('搜索加载历史消息完成');
    }
    
    // 首先检查目标消息是否已在当前列表中
    Logger.print('检查目标消息是否在当前列表中...');
    int index = messageList.indexWhere((msg) => msg.clientMsgID == targetMessage.clientMsgID);
    Logger.print('当前消息列表长度: ${messageList.length}, 目标消息索引: $index');

    // 如果消息不在当前列表中，需要加载历史消息
    if (index == -1) {
      Logger.print('目标消息不在当前列表中，开始加载历史消息');
      
      // 设置搜索加载标志
      _isLoadingHistoryForSearch = true;
      
      try {
        // 显示加载提示
        IMViews.showToast('正在加载历史消息...');
        
        // 循环加载历史消息，直到找到目标消息或没有更多消息
        int loadCount = 0;
        const maxLoadAttempts = 20; // 最多尝试加载20次，避免无限循环
        
        while (index == -1 && loadCount < maxLoadAttempts) {
          loadCount++;
          Logger.print('第 $loadCount 次尝试加载历史消息');
          
          // 加载历史消息
          final result = await _fetchHistoryMessages();
          if (result.messageList == null || result.messageList!.isEmpty) {
            Logger.print('没有更多历史消息');
            break;
          }
          
          Logger.print('加载到 ${result.messageList!.length} 条历史消息');
          
          // 添加新消息到列表开头，避免重复
          final newMessages = result.messageList!;
          newMessages.removeWhere((msg) => _isBeDeleteMessage(msg));
          
          // 过滤掉已经存在的消息，避免重复
          final existingMsgIDs = messageList.map((msg) => msg.clientMsgID).toSet();
          final uniqueNewMessages = newMessages.where((msg) => 
            !existingMsgIDs.contains(msg.clientMsgID)
          ).toList();
          
          if (uniqueNewMessages.isNotEmpty) {
            messageList.insertAll(0, uniqueNewMessages);
            Logger.print('添加了 ${uniqueNewMessages.length} 条新消息，过滤掉 ${newMessages.length - uniqueNewMessages.length} 条重复消息');
            _checkMessageDuplicates(); // 检查是否有重复
          } else {
            Logger.print('所有新消息都已存在，跳过添加');
          }
          
          // 消息列表发生变化，需要重新计算高度
          Logger.print('消息列表发生变化，需要重新计算高度');
          
          // 重新查找目标消息
          index = messageList.indexWhere((msg) => msg.clientMsgID == targetMessage.clientMsgID);
          Logger.print('重新查找目标消息，索引: $index');
          
          // 如果到达消息末尾，停止加载
          if (result.isEnd == true) {
            Logger.print('已到达消息末尾');
            break;
          }
        }
        
        if (index == -1) {
          Logger.print('无法找到目标消息，可能已被删除');
          IMViews.showToast('未找到目标消息，可能已被删除');
          return;
        }
      } finally {
        // 清除搜索加载标志
        _isLoadingHistoryForSearch = false;
        Logger.print('清除搜索加载标志');
      }
    }
    
    // 找到目标消息，滚动到对应位置
    Logger.print('=== 找到目标消息，位置: $index ===');
    
    // 使用精确的滚动定位方法
    Logger.print('开始精确滚动定位...');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToMessageAtIndex(index);
    });
    
    // 高亮显示目标消息（可以通过设置一个标记来实现）
    // 这里可以添加高亮逻辑
  }
  
  /// 精确滚动到指定索引的消息
  void _scrollToMessageAtIndex(int targetIndex) async {
    try {
      // 确保索引在有效范围内
      if (targetIndex < 0 || targetIndex >= messageList.length) {
        Logger.print('目标索引超出范围: $targetIndex, 总消息数: ${messageList.length}');
        IMViews.showToast('定位失败：索引超出范围');
        return;
      }
      
      Logger.print('开始精确滚动到索引: $targetIndex');
      
      // 等待消息项渲染完成
      await _waitForMessageRendering();
      
      // 使用GlobalKey来获取实际控件高度
      _scrollToMessageWithActualHeight(targetIndex);
      
    } catch (e) {
      Logger.print('滚动定位出错: $e');
      _scrollToMessageAtIndexFallback(targetIndex);
    }
  }
  
  /// 使用实际控件高度滚动到指定消息（考虑反向ListView）
  void _scrollToMessageWithActualHeight(int targetIndex) {
    if (targetIndex < 0 || targetIndex >= messageList.length) return;
    
    final targetMessage = messageList[targetIndex];
    final clientMsgID = targetMessage.clientMsgID ?? '';
    
    Logger.print('开始使用实际高度滚动到消息 - 目标索引: $targetIndex, 消息ID: $clientMsgID');
    
    // 等待下一帧，确保所有控件都已渲染
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateAndScrollToMessage(targetIndex, clientMsgID);
    });
  }
  
  /// 计算并滚动到消息的实际位置
  void _calculateAndScrollToMessage(int targetIndex, String clientMsgID) {
    Logger.print('开始计算滚动位置 - 目标索引: $targetIndex, 消息ID: $clientMsgID');
    
    try {
      // 获取目标消息的GlobalKey
      final targetKey = _messageKeys[clientMsgID];
      if (targetKey == null) {
        Logger.print('未找到目标消息的GlobalKey: $clientMsgID');
        _scrollToMessageAtIndexFallback(targetIndex);
        return;
      }
      
      Logger.print('成功获取目标消息的GlobalKey: $clientMsgID');
      
      // 获取目标消息的RenderBox
      final RenderBox? targetRenderBox = targetKey.currentContext?.findRenderObject() as RenderBox?;
      if (targetRenderBox == null) {
        Logger.print('无法获取目标消息的RenderBox: $clientMsgID');
        _scrollToMessageAtIndexFallback(targetIndex);
        return;
      }
      
      Logger.print('成功获取目标消息的RenderBox: $clientMsgID, 大小: ${targetRenderBox.size}');
      
      // 获取ListView的RenderBox
      final RenderBox? listViewRenderBox = scrollController.position.context.notificationContext?.findRenderObject() as RenderBox?;
      if (listViewRenderBox == null) {
        Logger.print('无法获取ListView的RenderBox');
        _scrollToMessageAtIndexFallback(targetIndex);
        return;
      }
      
      Logger.print('成功获取ListView的RenderBox, 大小: ${listViewRenderBox.size}');
      
      // 计算目标消息在ListView中的位置
      final targetPosition = targetRenderBox.localToGlobal(Offset.zero, ancestor: listViewRenderBox);
      Logger.print('目标消息在ListView中的位置: $targetPosition');
      
      // 计算需要滚动的距离
      final currentOffset = scrollController.offset;
      final viewportHeight = scrollController.position.viewportDimension;
      final maxScrollExtent = scrollController.position.maxScrollExtent;
      
      Logger.print('滚动状态 - 当前偏移: $currentOffset, 视口高度: $viewportHeight, 最大滚动范围: $maxScrollExtent');
      
      // 由于ListView是reverse的，需要重新计算滚动位置
      // 在reverse ListView中：
      // - 位置0 = 底部（最新消息）
      // - 位置n = 顶部（最早消息）
      // - 滚动到底部 = offset = 0
      // - 滚动到顶部 = offset = maxScrollExtent
      
      // 计算目标位置（考虑reverse ListView的特性）
      // 我们希望目标消息显示在视口的中间位置
      double scrollOffset;
      
      if (targetPosition.dy < 0) {
        // 目标消息在当前视口上方，需要向上滚动
        scrollOffset = currentOffset + targetPosition.dy - (viewportHeight * 0.5);
        Logger.print('目标消息在视口上方，向上滚动 - 计算偏移: $scrollOffset');
      } else if (targetPosition.dy > viewportHeight) {
        // 目标消息在当前视口下方，需要向下滚动
        scrollOffset = currentOffset + targetPosition.dy - (viewportHeight * 0.5);
        Logger.print('目标消息在视口下方，向下滚动 - 计算偏移: $scrollOffset');
      } else {
        // 目标消息在当前视口内，微调位置
        scrollOffset = currentOffset + targetPosition.dy - (viewportHeight * 0.3);
        Logger.print('目标消息在视口内，微调位置 - 计算偏移: $scrollOffset');
      }
      
      // 确保滚动位置在有效范围内
      final clampedScrollOffset = scrollOffset.clamp(0.0, maxScrollExtent);
      Logger.print('滚动位置限制 - 原始: $scrollOffset, 限制后: $clampedScrollOffset');
      
      // 平滑滚动到目标位置
      Logger.print('开始平滑滚动到位置: $clampedScrollOffset');
      scrollController.animateTo(
        clampedScrollOffset,
        duration: Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      ).then((_) {
        Logger.print('滚动动画完成');
        IMViews.showToast('已定位到目标消息');
        _highlightTargetMessage(targetIndex);
      });
      
    } catch (e) {
      Logger.print('使用实际高度计算滚动位置失败: $e');
      _scrollToMessageAtIndexFallback(targetIndex);
    }
  }
  
  /// 获取消息项的实际高度
  double _getActualMessageHeight(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= messageList.length) {
      Logger.print('消息索引超出范围: $messageIndex, 总消息数: ${messageList.length}');
      return 100.0; // 默认高度
    }
    
    final message = messageList[messageIndex];
    final clientMsgID = message.clientMsgID ?? '';
    
    Logger.print('开始获取消息实际高度 - 索引: $messageIndex, 消息ID: $clientMsgID');
    
    // 直接获取实际高度
    final actualHeight = _getMessageActualHeight(clientMsgID);
    if (actualHeight > 0) {
      Logger.print('获取到消息实际高度: $clientMsgID, 高度: $actualHeight');
      return actualHeight;
    }
    
    // 如果无法获取实际高度，使用预估高度作为备用
    final estimatedHeight = _getEstimatedMessageHeight(messageIndex);
    Logger.print('使用预估高度: $clientMsgID, 预估高度: $estimatedHeight');
    return estimatedHeight;
  }
  
  /// 根据消息类型获取预估高度（备用方法）
  double _getEstimatedMessageHeight(int messageIndex) {
    Logger.print('开始获取预估高度 - 消息索引: $messageIndex');
    
    if (messageIndex < 0 || messageIndex >= messageList.length) {
      Logger.print('消息索引超出范围，使用默认高度: 100.0');
      return 100.0; // 默认高度
    }
    
    final message = messageList[messageIndex];
    final contentType = message.contentType;
    final clientMsgID = message.clientMsgID ?? '';
    
    Logger.print('计算预估高度 - 消息ID: $clientMsgID, 消息类型: $contentType');
    
    double estimatedHeight;
    switch (contentType) {
      case MessageType.text:
        final text = message.textElem?.content ?? '';
        // 根据文本长度估算高度
        if (text.length < 20) {
          estimatedHeight = 60.0;
        } else if (text.length < 50) {
          estimatedHeight = 80.0;
        } else if (text.length < 100) {
          estimatedHeight = 100.0;
        } else {
          estimatedHeight = 120.0;
        }
        Logger.print('文本消息预估高度 - 文本长度: ${text.length}, 预估高度: $estimatedHeight');
        return estimatedHeight;
        
      case MessageType.picture:
        estimatedHeight = 200.0; // 图片消息通常较高
        Logger.print('图片消息预估高度: $estimatedHeight');
        return estimatedHeight;
        
      case MessageType.video:
        estimatedHeight = 180.0; // 视频消息
        Logger.print('视频消息预估高度: $estimatedHeight');
        return estimatedHeight;
        
      case MessageType.voice:
        estimatedHeight = 60.0; // 语音消息通常较矮
        Logger.print('语音消息预估高度: $estimatedHeight');
        return estimatedHeight;
        
      case MessageType.file:
        estimatedHeight = 80.0; // 文件消息
        Logger.print('文件消息预估高度: $estimatedHeight');
        return estimatedHeight;
        
      case MessageType.location:
        estimatedHeight = 150.0; // 位置消息
        Logger.print('位置消息预估高度: $estimatedHeight');
        return estimatedHeight;
        
      case MessageType.quote:
        estimatedHeight = 120.0; // 引用消息
        Logger.print('引用消息预估高度: $estimatedHeight');
        return estimatedHeight;
        
      case MessageType.card:
        estimatedHeight = 100.0; // 名片消息
        Logger.print('名片消息预估高度: $estimatedHeight');
        return estimatedHeight;
        
      default:
        estimatedHeight = 100.0; // 默认高度
        Logger.print('未知消息类型预估高度: $estimatedHeight');
        return estimatedHeight;
    }
  }
  
  /// 获取消息项的实际高度
  double _getMessageActualHeight(String clientMsgID) {
    Logger.print('开始获取消息实际高度: $clientMsgID');
    
    try {
      final key = _messageKeys[clientMsgID];
      if (key == null) {
        Logger.print('未找到消息的GlobalKey: $clientMsgID');
        return 0.0;
      }
      
      final context = key.currentContext;
      if (context == null) {
        Logger.print('GlobalKey的context为空: $clientMsgID');
        return 0.0;
      }
      
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) {
        Logger.print('无法获取RenderBox: $clientMsgID');
        return 0.0;
      }
      
      final height = renderBox.size.height;
      Logger.print('获取到消息实际高度: $clientMsgID, 高度: $height');
      
      return height;
      
    } catch (e) {
      Logger.print('获取消息实际高度失败: $clientMsgID, 错误: $e');
      return 0.0;
    }
  }
  
  /// 备用滚动方法（考虑反向ListView）
  void _scrollToMessageAtIndexFallback(int targetIndex) {
    Logger.print('开始使用备用滚动方法 - 目标索引: $targetIndex');
    
    try {
      // 由于ListView是reverse的，需要重新计算目标位置
      // 在reverse ListView中：
      // - messageList[0] = 最早的消息，显示在ListView的顶部（索引最大）
      // - messageList[n] = 最新的消息，显示在ListView的底部（索引0）
      
      final itemCount = messageList.length;
      
      // 计算目标消息在reverse ListView中的显示索引
      // targetIndex是messageList中的索引，需要转换为ListView的显示索引
      final displayIndex = itemCount - targetIndex - 1;
      
      Logger.print('备用方法 - 目标消息索引: $targetIndex, 显示索引: $displayIndex, 总项目数: $itemCount');
      
      // 使用新的反向ListView滚动计算方法
      Logger.print('开始计算反向ListView滚动位置');
      final estimatedPosition = _calculateReverseListViewScrollPosition(targetIndex);
      
      Logger.print('备用方法 - 计算的目标滚动位置: $estimatedPosition');
      
      // 确保滚动位置在有效范围内
      final maxScrollExtent = scrollController.position.maxScrollExtent;
      final finalPosition = estimatedPosition.clamp(0.0, maxScrollExtent);
      
      Logger.print('备用方法 - 滚动位置限制 - 原始: $estimatedPosition, 限制后: $finalPosition, 最大范围: $maxScrollExtent');
      
      // 使用jumpTo进行快速定位
      Logger.print('开始使用jumpTo快速定位到位置: $finalPosition');
      scrollController.jumpTo(finalPosition);
      
      Logger.print('jumpTo定位完成');
      
      // 延迟后显示提示
      Future.delayed(Duration(milliseconds: 100), () {
        IMViews.showToast('已定位到目标消息');
        Logger.print('显示定位成功提示');
      });
    } catch (e) {
      Logger.print('备用滚动方法也失败: $e');
      IMViews.showToast('定位失败，请手动滚动查看');
    }
  }
  
  /// 高亮目标消息
  void _highlightTargetMessage(int targetIndex) {
    Logger.print('=== 开始高亮目标消息 ===');
    Logger.print('目标消息索引: $targetIndex');
    
    if (targetIndex >= 0 && targetIndex < messageList.length) {
      final message = messageList[targetIndex];
      final clientMsgID = message.clientMsgID ?? '';
      Logger.print('目标消息ID: $clientMsgID');
      Logger.print('目标消息类型: ${message.contentType}');
      
      // 这里可以添加高亮逻辑
      // 例如：设置一个标记，让对应的消息项显示高亮效果
      Logger.print('可以在这里实现高亮效果');
      // 比如：设置一个observable变量来标记高亮的消息
      // highlightedMessageIndex.value = targetIndex;
    } else {
      Logger.print('目标索引超出范围，无法高亮');
    }
    
    Logger.print('=== 高亮目标消息完成 ===');
  }

  Future<List<Message>> searchMediaMessage() async {
    final messageList = await OpenIM.iMManager.messageManager.searchLocalMessages(
        conversationID: conversationInfo.conversationID,
        messageTypeList: [MessageType.picture, MessageType.video],
        count: 500);
    return messageList.searchResultItems?.first.messageList?.reversed.toList() ?? [];
  }

  @override
  void onReady() {
    Logger.print('=== 聊天页面准备就绪 ===');
    
    Logger.print('初始化聊天配置...');
    _readDraftText();
    _queryUserOnlineStatus();
    _resetGroupAtType();
    _getInputState();
    _clearUnreadCount();

    Logger.print('设置滚动监听器...');
    // 注释掉可能导致问题的滚动监听器
    // scrollController.addListener(() {
    //   focusNode.unfocus();
    // });
    
    // 延迟检查消息列表是否有重复
    Logger.print('设置延迟检查消息重复...');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(Duration(milliseconds: 1000), () {
        Logger.print('开始延迟检查消息重复');
        _checkMessageDuplicates();
        if (messageList.isNotEmpty) {
          _removeMessageDuplicates();
        }
      });
    });
    
    // 如果有搜索消息，定位到该消息
    if (searchMessage != null) {
      Logger.print('发现搜索消息，准备定位...');
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _locateToMessage(searchMessage!);
      });
    } else {
      Logger.print('无搜索消息需要定位');
    }
    
    Logger.print('=== 聊天页面准备完成 ===');
    super.onReady();
  }

  @override
  void onInit() {
    Logger.print('=== 聊天页面初始化开始 ===');
    
    var arguments = Get.arguments;
    Logger.print('获取页面参数: $arguments');
    
    conversationInfo = arguments['conversationInfo'];
    searchMessage = arguments['searchMessage'];
    Logger.print('会话信息: ${conversationInfo.toJson()}');
    Logger.print('搜索消息: ${searchMessage?.toJson()}');
    
    nickname.value = conversationInfo.showName ?? '';
    faceUrl.value = conversationInfo.faceURL ?? '';
    Logger.print('设置显示名称: ${nickname.value}');
    Logger.print('设置头像URL: ${faceUrl.value}');
    
    Logger.print('初始化聊天配置...');
    _initChatConfig();
    _initPlayListener();
    _setSdkSyncDataListener();

    conversationSub = imLogic.conversationChangedSubject.listen((value) {
      final obj = value.firstWhereOrNull((e) => e.conversationID == conversationInfo.conversationID);

      if (obj != null) {
        conversationInfo = obj;
      }
    });

    Logger.print('设置新消息接收监听器...');
    imLogic.onRecvNewMessage = (Message message) async {
      Logger.print('收到新消息 - ID: ${message.clientMsgID}, 类型: ${message.contentType}');
      
      if (isCurrentChat(message)) {
        Logger.print('消息属于当前聊天');
        
        if (message.contentType == MessageType.typing) {
          Logger.print('收到输入状态消息');
        } else {
          if (!messageList.contains(message) && !scrollingCacheMessageList.contains(message)) {
            Logger.print('消息不在列表中，准备添加');
            _isReceivedMessageWhenSyncing = true;
            
            if (isShowPopMenu.value || scrollController.offset != 0) {
              Logger.print('添加到滚动缓存列表');
              scrollingCacheMessageList.add(message);
            } else {
              Logger.print('直接添加到消息列表并滚动到底部');
              messageList.add(message);
              scrollBottom();
            }
          } else {
            Logger.print('消息已存在于列表中，跳过添加');
          }
        }
      } else {
        Logger.print('消息不属于当前聊天，跳过处理');
      }
    };

    Logger.print('设置消息撤回监听器...');
    imLogic.onRecvMessageRevoked = (RevokedInfo info) {
      Logger.print('收到消息撤回 - 消息ID: ${info.clientMsgID}');
      
      var message = messageList.firstWhereOrNull((e) => e.clientMsgID == info.clientMsgID);
      if (message != null) {
        Logger.print('找到被撤回的消息，更新状态');
        message.notificationElem = NotificationElem(detail: jsonEncode(info));
        message.contentType = MessageType.revokeMessageNotification;
        messageList.refresh();
      } else {
        Logger.print('未找到被撤回的消息');
      }
    };

    Logger.print('设置已读回执监听器...');
    imLogic.onRecvC2CReadReceipt = (List<ReadReceiptInfo> list) {
      Logger.print('收到已读回执 - 数量: ${list.length}');
      
      try {
        for (var readInfo in list) {
          Logger.print('处理已读回执 - 用户ID: ${readInfo.userID}');
          
          if (readInfo.userID == userID) {
            Logger.print('已读回执属于当前用户');
            int updatedCount = 0;
            
            for (var e in messageList) {
              if (readInfo.msgIDList?.contains(e.clientMsgID) == true) {
                e.isRead = true;
                e.hasReadTime = _timestamp;
                updatedCount++;
              }
            }
            
            Logger.print('更新了 $updatedCount 条消息的已读状态');
          } else {
            Logger.print('已读回执不属于当前用户，跳过处理');
          }
        }
        messageList.refresh();
      } catch (e) {
        Logger.print('处理已读回执时出错: $e');
      }
    };

    joinedGroupAddedSub = imLogic.joinedGroupAddedSubject.listen((event) {
      if (event.groupID == groupID) {
        isInGroup.value = true;
        _queryGroupInfo();
      }
    });

    joinedGroupDeletedSub = imLogic.joinedGroupDeletedSubject.listen((event) {
      if (event.groupID == groupID) {
        isInGroup.value = false;
        inputCtrl.clear();
      }
    });

    memberAddSub = imLogic.memberAddedSubject.listen((info) {
      var groupId = info.groupID;
      if (groupId == groupID) {
        _putMemberInfo([info]);
      }
    });

    memberDelSub = imLogic.memberDeletedSubject.listen((info) {
      if (info.groupID == groupID && info.userID == OpenIM.iMManager.userID) {
        isInGroup.value = false;
        inputCtrl.clear();
      }
    });

    memberInfoChangedSub = imLogic.memberInfoChangedSubject.listen((info) {
      if (info.groupID == groupID) {
        if (info.userID == OpenIM.iMManager.userID) {
          muteEndTime.value = info.muteEndTime ?? 0;
          groupMemberRoleLevel.value = info.roleLevel ?? GroupRoleLevel.member;
          groupMembersInfo = info;
          ();
        }
        _putMemberInfo([info]);

        final index = ownerAndAdmin.indexWhere((element) => element.userID == info.userID);
        if (info.roleLevel == GroupRoleLevel.member) {
          if (index > -1) {
            ownerAndAdmin.removeAt(index);
          }
        } else if (info.roleLevel == GroupRoleLevel.admin || info.roleLevel == GroupRoleLevel.owner) {
          if (index == -1) {
            ownerAndAdmin.add(info);
          } else {
            ownerAndAdmin[index] = info;
          }
        }

        for (var msg in messageList) {
          if (msg.sendID == info.userID) {
            if (msg.isNotificationType) {
              final map = json.decode(msg.notificationElem!.detail!);
              final ntf = GroupNotification.fromJson(map);
              ntf.opUser?.nickname = info.nickname;
              ntf.opUser?.faceURL = info.faceURL;
              msg.notificationElem?.detail = jsonEncode(ntf);
            } else {
              msg.senderFaceUrl = info.faceURL;
              msg.senderNickname = info.nickname;
            }
          }
        }

        messageList.refresh();
      }
    });

    groupInfoUpdatedSub = imLogic.groupInfoUpdatedSubject.listen((value) {
      if (groupID == value.groupID) {
        groupInfo = value;
        nickname.value = value.groupName ?? '';
        faceUrl.value = value.faceURL ?? '';
        groupMutedStatus.value = value.status ?? 0;
        memberCount.value = value.memberCount ?? 0;
      }
    });

    friendInfoChangedSub = imLogic.friendInfoChangedSubject.listen((value) {
      if (userID == value.userID) {
        nickname.value = value.getShowName();
        faceUrl.value = value.faceURL ?? '';

        for (var msg in messageList) {
          if (msg.sendID == value.userID) {
            msg.senderFaceUrl = value.faceURL;
            msg.senderNickname = value.nickname;
          }
        }

        messageList.refresh();
      }
    });

    selfInfoUpdatedSub = imLogic.selfInfoUpdatedSubject.listen((value) {
      for (var msg in messageList) {
        if (msg.sendID == value.userID) {
          msg.senderFaceUrl = value.faceURL;
          msg.senderNickname = value.nickname;
        }
      }

      messageList.refresh();
    });

    Logger.print('设置输入框监听器...');
    inputCtrl.addListener(() {
      sendTypingMsg(focus: true);
      if (_debounce?.isActive ?? false) _debounce?.cancel();

      _debounce = Timer(1.seconds, () {
        sendTypingMsg(focus: false);
      });
    });

    Logger.print('设置焦点监听器...');
    focusNode.addListener(() {
      _lastCursorIndex = inputCtrl.selection.start;
      focusNodeChanged(focusNode.hasFocus);
    });

    Logger.print('设置信令消息监听器...');
    imLogic.onSignalingMessage = (value) {
      if (value.userID == userID) {
        messageList.add(value.message);
        scrollBottom();
      }
    };

    Logger.print('设置输入状态监听器...');
    imLogic.inputStateChangedSubject.listen((value) {
      if (value.conversationID == conversationInfo.conversationID && value.userID == userID) {
        typing.value = value.platformIDs?.isNotEmpty == true;
      }
    });
    
    Logger.print('=== 聊天页面初始化完成 ===');
    super.onInit();
  }

  Future chatSetup() => isSingleChat
      ? AppNavigator.startChatSetup(conversationInfo: conversationInfo)
      : AppNavigator.startGroupChatSetup(conversationInfo: conversationInfo);

  void _putMemberInfo(List<GroupMembersInfo>? list) {
    list?.forEach((member) {
      memberUpdateInfoMap[member.userID!] = member;
    });

    messageList.refresh();
  }

  void sendTextMsg() async {
    var content = IMUtils.safeTrim(inputCtrl.text);
    if (content.isEmpty) return;
    Message message = await OpenIM.iMManager.messageManager.createTextMessage(
      text: content,
    );

    _sendMessage(message);
  }

  Future sendPicture({required String path, bool sendNow = true}) async {
    final file = await IMUtils.compressImageAndGetFile(File(path));

    var message = await OpenIM.iMManager.messageManager.createImageMessageFromFullPath(
      imagePath: file!.path,
    );

    if (sendNow) {
      return _sendMessage(message);
    } else {
      messageList.add(message);
      tempMessages.add(message);
    }
  }

  void sendVoice(int duration, String path) async {
    var message = await OpenIM.iMManager.messageManager.createSoundMessageFromFullPath(
      soundPath: path,
      duration: duration,
    );
    _sendMessage(message);
  }

  Future sendVideo(
      {required String videoPath,
      required String mimeType,
      required int duration,
      required String thumbnailPath,
      bool sendNow = true}) async {
    var d = duration > 1000.0 ? duration / 1000.0 : duration;
    var message = await OpenIM.iMManager.messageManager.createVideoMessageFromFullPath(
      videoPath: videoPath,
      videoType: mimeType,
      duration: d.toInt(),
      snapshotPath: thumbnailPath,
    );

    if (sendNow) {
      return _sendMessage(message);
    } else {
      messageList.add(message);
      tempMessages.add(message);
    }
  }

  void sendFile({required String filePath, required String fileName}) async {
    var message = await OpenIM.iMManager.messageManager.createFileMessageFromFullPath(
      filePath: filePath,
      fileName: fileName,
    );
    _sendMessage(message);
  }

  void sendLocation({
    required dynamic location,
  }) async {
    var message = await OpenIM.iMManager.messageManager.createLocationMessage(
      latitude: location['latitude'],
      longitude: location['longitude'],
      description: location['description'],
    );
    _sendMessage(message);
  }

  sendForwardRemarkMsg(
    String content, {
    String? userId,
    String? groupId,
  }) async {
    final message = await OpenIM.iMManager.messageManager.createTextMessage(
      text: content,
    );
    _sendMessage(message, userId: userId, groupId: groupId);
  }

  sendForwardMsg(
    Message originalMessage, {
    String? userId,
    String? groupId,
  }) async {
    var message = await OpenIM.iMManager.messageManager.createForwardMessage(
      message: originalMessage,
    );
    _sendMessage(message, userId: userId, groupId: groupId);
  }

  void sendTypingMsg({bool focus = false}) async {
    if (isSingleChat) {
      OpenIM.iMManager.conversationManager
          .changeInputStates(conversationID: conversationInfo.conversationID, focus: focus);
    }
  }

  void sendCarte({
    required String userID,
    String? nickname,
    String? faceURL,
  }) async {
    var message = await OpenIM.iMManager.messageManager.createCardMessage(
      userID: userID,
      nickname: nickname!,
      faceURL: faceURL,
    );
    _sendMessage(message);
  }

  void sendCustomMsg({
    required String data,
    required String extension,
    required String description,
  }) async {
    var message = await OpenIM.iMManager.messageManager.createCustomMessage(
      data: data,
      extension: extension,
      description: description,
    );
    _sendMessage(message);
  }

  Future _sendMessage(
    Message message, {
    String? userId,
    String? groupId,
    bool addToUI = true,
  }) {
    Logger.print('=== 开始发送消息 ===');
    Logger.print('消息ID: ${message.clientMsgID}');
    Logger.print('消息类型: ${message.contentType}');
    Logger.print('消息内容: ${json.encode(message)}');
    
    userId = IMUtils.emptyStrToNull(userId);
    groupId = IMUtils.emptyStrToNull(groupId);
    
    Logger.print('发送参数 - userId: $userId, groupId: $groupId, addToUI: $addToUI');
    Logger.print('当前会话 - userID: $userID, groupID: $groupID');
    
    if (null == userId && null == groupId ||
        userId == userID && userId != null ||
        groupId == groupID && groupId != null) {
      if (addToUI) {
        Logger.print('添加消息到UI列表');
        messageList.add(message);
        scrollBottom();
        
        // 新消息已添加，需要重新计算高度
        Logger.print('新消息已添加，需要重新计算高度: ${message.clientMsgID}');
      }
    } else {
      Logger.print('消息不添加到当前UI列表');
    }
    
    _reset(message);
    bool useOuterValue = null != userId || null != groupId;
    Logger.print('使用外部值: $useOuterValue');

    final recvUserID = useOuterValue ? userId : userID;
    message.recvID = recvUserID;
    Logger.print('接收者ID: $recvUserID');

    Logger.print('开始调用SDK发送消息...');
    return OpenIM.iMManager.messageManager
        .sendMessage(
          message: message,
          userID: recvUserID,
          groupID: useOuterValue ? groupId : groupID,
          offlinePushInfo: Config.offlinePushInfo,
        )
        .then((value) => _sendSucceeded(message, value))
        .catchError((error, _) => _senFailed(message, groupId, userId, error, _))
        .whenComplete(() => _completed());
  }

  void _sendSucceeded(Message oldMsg, Message newMsg) {
    Logger.print('=== 消息发送成功 ===');
    Logger.print('消息ID: ${oldMsg.clientMsgID}');
    Logger.print('消息类型: ${oldMsg.contentType}');
    Logger.print('更新消息状态');
    oldMsg.update(newMsg);
    sendStatusSub.addSafely(MsgStreamEv<bool>(
      id: oldMsg.clientMsgID!,
      value: true,
    ));
    Logger.print('发送状态已更新');
  }

  void _senFailed(Message message, String? groupId, String? userId, error, stack) async {
    Logger.print('=== 消息发送失败 ===');
    Logger.print('消息ID: ${message.clientMsgID}');
    Logger.print('消息类型: ${message.contentType}');
    Logger.print('发送参数 - userID: $userId, groupId: $groupId');
    Logger.print('错误信息: $error');
    Logger.print('错误堆栈: $stack');
    
    message.status = MessageStatus.failed;
    Logger.print('设置消息状态为失败');
    
    sendStatusSub.addSafely(MsgStreamEv<bool>(
      id: message.clientMsgID!,
      value: false,
    ));
    Logger.print('发送状态已更新为失败');
    if (error is PlatformException) {
      int code = int.tryParse(error.code) ?? 0;
      if (isSingleChat) {
        int? customType;
        if (code == SDKErrorCode.hasBeenBlocked) {
          customType = CustomMessageType.blockedByFriend;
        } else if (code == SDKErrorCode.notFriend) {
          customType = CustomMessageType.deletedByFriend;
        }
        if (null != customType) {
          final hintMessage = (await OpenIM.iMManager.messageManager.createFailedHintMessage(type: customType))
            ..status = 2
            ..isRead = true;
          if (userId != null) {
            if (userId == userID) {
              messageList.add(hintMessage);
            }
          } else {
            messageList.add(hintMessage);
          }
          OpenIM.iMManager.messageManager.insertSingleMessageToLocalStorage(
            message: hintMessage,
            receiverID: userId ?? userID,
            senderID: OpenIM.iMManager.userID,
          );
        }
      } else {
        if ((code == SDKErrorCode.userIsNotInGroup || code == SDKErrorCode.groupDisbanded) && null == groupId) {
          final status = groupInfo?.status;
          final hintMessage = (await OpenIM.iMManager.messageManager.createFailedHintMessage(
              type: status == 2 ? CustomMessageType.groupDisbanded : CustomMessageType.removedFromGroup))
            ..status = 2
            ..isRead = true;
          messageList.add(hintMessage);
          OpenIM.iMManager.messageManager.insertGroupMessageToLocalStorage(
            message: hintMessage,
            groupID: groupID,
            senderID: OpenIM.iMManager.userID,
          );
        }
      }
    }
  }

  void _reset(Message message) {
    Logger.print('重置消息发送状态 - 消息类型: ${message.contentType}');
    if (message.contentType == MessageType.text) {
      Logger.print('清空输入框');
      inputCtrl.clear();
    }
  }

  void _completed() {
    Logger.print('消息发送流程完成，刷新消息列表');
    messageList.refresh();
  }

  void deleteMsg(Message message) async {
    LoadingView.singleton.wrap(asyncFunction: () => _deleteMessage(message));
  }

  _deleteMessage(Message message) async {
    Logger.print('=== 开始删除消息 ===');
    Logger.print('消息ID: ${message.clientMsgID}');
    Logger.print('消息类型: ${message.contentType}');
    
    try {
      Logger.print('尝试从本地和服务器删除消息');
      await OpenIM.iMManager.messageManager
          .deleteMessageFromLocalAndSvr(
            conversationID: conversationInfo.conversationID,
            clientMsgID: message.clientMsgID!,
          )
          .then((value) {
            Logger.print('从私有消息列表移除消息');
            privateMessageList.remove(message);
          })
          .then((value) {
            Logger.print('从消息列表移除消息');
            messageList.remove(message);
          });
      Logger.print('消息删除成功');
    } catch (e) {
      Logger.print('从服务器删除失败，尝试仅从本地删除 - 错误: $e');
      await OpenIM.iMManager.messageManager
          .deleteMessageFromLocalStorage(
            conversationID: conversationInfo.conversationID,
            clientMsgID: message.clientMsgID!,
          )
          .then((value) {
            Logger.print('从私有消息列表移除消息');
            privateMessageList.remove(message);
          })
          .then((value) {
            Logger.print('从消息列表移除消息');
            messageList.remove(message);
          });
      Logger.print('本地删除成功');
    }
    
    Logger.print('=== 消息删除完成 ===');
  }

  void forward(Message? message) async {
    final result = await AppNavigator.startSelectContacts(
      action: SelAction.forward,
      ex: null != message ? IMUtils.parseMsg(message) : null,
    );
    if (null != result) {
      final checkedList = result['checkedList'];
      for (var info in checkedList) {
        final userID = IMUtils.convertCheckedToUserID(info);
        final groupID = IMUtils.convertCheckedToGroupID(info);

        if (null != message) {
          sendForwardMsg(message, userId: userID, groupId: groupID);
        }
      }
    }
  }

  void markMessageAsRead(Message message, bool visible) async {
    Logger.print('markMessageAsRead: ${message.textElem?.content}, $visible');
    if (visible && message.contentType! < 1000 && message.contentType! != MessageType.voice) {
      var data = IMUtils.parseCustomMessage(message);
      if (null != data && data['viewType'] == CustomMessageType.call) {
        Logger.print('markMessageAsRead: call message $data');
        return;
      }
      _markMessageAsRead(message);
    }
  }

  _markMessageAsRead(Message message) async {
    if (!message.isRead! && message.sendID != OpenIM.iMManager.userID) {
      try {
        Logger.print('mark conversation message as read：${message.clientMsgID!} ${message.isRead}');
        await OpenIM.iMManager.conversationManager
            .markConversationMessageAsRead(conversationID: conversationInfo.conversationID);
      } catch (e) {
        Logger.print('failed to send group message read receipt： ${message.clientMsgID} ${message.isRead}');
      } finally {
        message.isRead = true;
        message.hasReadTime = _timestamp;
        messageList.refresh();
      }
    }
  }

  _clearUnreadCount() {
    if (conversationInfo.unreadCount > 0) {
      OpenIM.iMManager.conversationManager
          .markConversationMessageAsRead(conversationID: conversationInfo.conversationID);
    }
  }

  void _getInputState() async {
    if (conversationInfo.isSingleChat) {
      final result =
          await OpenIM.iMManager.conversationManager.getInputStates(conversationInfo.conversationID, userID!);
      typing.value = result?.isNotEmpty == true;
    }
  }

  void _changeInputStatus(bool focus) async {
    if (conversationInfo.isSingleChat) {
      await OpenIM.iMManager.conversationManager
          .changeInputStates(conversationID: conversationInfo.conversationID, focus: focus);
    }
  }

  void closeToolbox() {
    forceCloseToolbox.addSafely(true);
  }

  void onTapLocation() async {
    var location = await Get.to(
      const ChatWebViewMap(host: Config.locationHost, webKey: Config.webKey, webServerKey: Config.webServerKey),
      transition: Transition.cupertino,
      popGesture: true,
    );
    if (null != location) {
      Logger.print(location);
      sendLocation(location: location);
    }
  }

  void onTapAlbum() async {
    final List<AssetEntity>? assets = await AssetPicker.pickAssets(Get.context!,
        pickerConfig: AssetPickerConfig(
            sortPathsByModifiedDate: true,
            filterOptions: PMFilter.defaultValue(containsPathModified: true),
            selectPredicate: (_, entity, isSelected) async {
              if (entity.type == AssetType.image) {
                if (await allowSendImageType(entity)) {
                  return true;
                }

                IMViews.showToast(StrRes.supportsTypeHint);

                return false;
              }

              if (entity.videoDuration > const Duration(seconds: 5 * 60)) {
                IMViews.showToast(sprintf(StrRes.selectVideoLimit, [5]) + StrRes.minute);
                return false;
              }
              return true;
            }));
    if (null != assets) {
      for (var asset in assets) {
        await _handleAssets(asset, sendNow: false);
      }

      for (var msg in tempMessages) {
        await _sendMessage(msg, addToUI: false);
      }

      tempMessages.clear();
    }
  }

  void onTapCamera() async {
    final AssetEntity? entity = await CameraPicker.pickFromCamera(
      Get.context!,
      locale: Get.locale,
      pickerConfig: CameraPickerConfig(
        enableAudio: true,
        enableRecording: true,
        enableScaledPreview: false,
        maximumRecordingDuration: 60.seconds,
        onMinimumRecordDurationNotMet: () {
          IMViews.showToast(StrRes.tapTooShort);
        },
      ),
    );
    _handleAssets(entity);
  }

  void onTapFile() async {
    await FilePicker.platform.clearTemporaryFiles();
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
    );

    if (result != null) {
      for (var file in result.files) {
        String? mimeType = lookupMimeType(file.name);
        if (mimeType != null) {
          if (IMUtils.allowImageType(mimeType)) {
            sendPicture(path: file.path!);
            continue;
          } else if (mimeType.contains('video/')) {
            try {
              final videoPath = file.path!;
              final mediaInfo = await VideoCompress.getMediaInfo(videoPath);
              var thumbnailFile = await VideoCompress.getFileThumbnail(
                videoPath,
                quality: 60,
              );
              sendVideo(
                videoPath: videoPath,
                mimeType: mimeType,
                duration: mediaInfo.duration!.toInt(),
                thumbnailPath: thumbnailFile.path,
              );
              continue;
            } catch (e, s) {
              Logger.print('e :$e  s:$s');
            }
          }
        }
        sendFile(filePath: file.path!, fileName: file.name);
      }
    } else {}
  }

  Future<bool> allowSendImageType(AssetEntity entity) async {
    final mimeType = await entity.mimeTypeAsync;

    return IMUtils.allowImageType(mimeType);
  }

  void onTapCarte() async {
    var result = await AppNavigator.startSelectContacts(
      action: SelAction.carte,
    );
    if (result is UserInfo || result is FriendInfo) {
      sendCarte(
        userID: result.userID!,
        nickname: result.nickname,
        faceURL: result.faceURL,
      );
    }
  }

  Future _handleAssets(AssetEntity? asset, {bool sendNow = true}) async {
    if (null != asset) {
      Logger.print('--------assets type-----${asset.type} create time: ${asset.createDateTime}');
      final originalFile = await asset.file;
      final originalPath = originalFile!.path;
      var path = originalPath.toLowerCase().endsWith('.gif') ? originalPath : originalFile.path;
      Logger.print('--------assets path-----$path');
      switch (asset.type) {
        case AssetType.image:
          await sendPicture(path: path, sendNow: sendNow);
          break;
        case AssetType.video:
          var thumbnailFile = await IMUtils.getVideoThumbnail(File(path));
          LoadingView.singleton.show();
          final file = await IMUtils.compressVideoAndGetFile(File(path));
          LoadingView.singleton.dismiss();

          await sendVideo(
            videoPath: file!.path,
            mimeType: asset.mimeType ?? IMUtils.getMediaType(path) ?? '',
            duration: asset.duration,
            thumbnailPath: thumbnailFile.path,
            sendNow: sendNow,
          );
          break;
        default:
          break;
      }
      if (Platform.isIOS) {
        originalFile.deleteSync();
      }
    }
  }

  void onTapDirectionalMessage() async {
    if (null != groupInfo) {
      final list = await AppNavigator.startGroupMemberList(
        groupInfo: groupInfo!,
        opType: GroupMemberOpType.call,
      );
      if (list is List<GroupMembersInfo>) {
        directionalUsers.assignAll(list);
      }
    }
  }

  TextSpan? directionalText() {
    if (directionalUsers.isNotEmpty) {
      final temp = <TextSpan>[];

      for (var e in directionalUsers) {
        final r = TextSpan(
          text: '${e.nickname ?? ''} ${directionalUsers.last == e ? '' : ','} ',
          style: Styles.ts_0089FF_14sp,
        );

        temp.add(r);
      }

      return TextSpan(
        text: '${StrRes.directedTo}:',
        style: Styles.ts_8E9AB0_14sp,
        children: temp,
      );
    }

    return null;
  }

  void onClearDirectional() {
    directionalUsers.clear();
  }

  void parseClickEvent(Message msg) async {
    log('parseClickEvent:${jsonEncode(msg)}');
    if (msg.contentType == MessageType.custom) {
      var data = msg.customElem!.data;
      var map = json.decode(data!);
      var customType = map['customType'];
      if (CustomMessageType.call == customType && !isInBlacklist.value) {
      } else if (CustomMessageType.meeting == customType) {
        joinMeeting(msg);
      } else if (CustomMessageType.tag == customType) {
        final data = map['data'];
        if (null != data['soundElem']) {
          final soundElem = SoundElem.fromJson(data['soundElem']);
          msg.soundElem = soundElem;
          _playVoiceMessage(msg);
        }
      }
      return;
    }
    if (msg.contentType == MessageType.voice) {
      _playVoiceMessage(msg);
      _markMessageAsRead(msg);
      return;
    }

    IMUtils.parseClickEvent(
      msg,
      onViewUserInfo: (userInfo) {
        viewUserInfo(userInfo, isCard: msg.isCardType);
      },
      meetingItemClick: joinMeeting,
      onForward: () => forward(msg),
    );
  }

  void onLongPressLeftAvatar(Message message) {
    if (isInvalidGroup) return;
    if (isGroupChat) {
      var uid = message.sendID!;

      var cursor = inputCtrl.selection.base.offset;
      if (!focusNode.hasFocus) {
        focusNode.requestFocus();
        cursor = _lastCursorIndex;
      }
      if (cursor < 0) cursor = 0;
      var start = inputCtrl.text.substring(0, cursor);
      var end = inputCtrl.text.substring(cursor);
      var at = '@$uid ';
      inputCtrl.text = '$start$at$end';
      Logger.print('start:$start end:$end  at:$at  content:${inputCtrl.text}');
      inputCtrl.selection = TextSelection.collapsed(offset: '$start$at'.length);
      _lastCursorIndex = inputCtrl.selection.start;
    }
  }

  void onTapLeftAvatar(Message message) {
    viewUserInfo(UserInfo()
      ..userID = message.sendID
      ..nickname = message.senderNickname
      ..faceURL = message.senderFaceUrl);
  }

  void onTapRightAvatar() {
    viewUserInfo(OpenIM.iMManager.userInfo);
  }

  void viewUserInfo(UserInfo userInfo, {bool isCard = false}) {
    if (isGroupChat && !isAdminOrOwner && !isCard) {
      if (groupInfo!.lookMemberInfo != 1) {
        AppNavigator.startUserProfilePane(
          userID: userInfo.userID!,
          nickname: userInfo.nickname,
          faceURL: userInfo.faceURL,
          groupID: groupID,
          offAllWhenDelFriend: isSingleChat,
        );
      }
    } else {
      AppNavigator.startUserProfilePane(
        userID: userInfo.userID!,
        nickname: userInfo.nickname,
        faceURL: userInfo.faceURL,
        groupID: groupID,
        offAllWhenDelFriend: isSingleChat,
        forceCanAdd: isCard,
      );
    }
  }

  void clickLinkText(url, type) async {
    if (await canLaunch(url)) {
      await launch(url);
    }
  }

  void _readDraftText() {
    var draftText = Get.arguments['draftText'];
    Logger.print('readDraftText:$draftText');
    if (null != draftText && "" != draftText) {
      var map = json.decode(draftText!);
      String text = map['text'];
      Map<String, dynamic> atMap = map['at'];
      Logger.print('text:$text  atMap:$atMap');
      inputCtrl.text = text;
      inputCtrl.selection = TextSelection.fromPosition(TextPosition(
        offset: text.length,
      ));
      if (text.isNotEmpty) {
        focusNode.requestFocus();
      }
    }
  }

  exit() async {
    if (isShowPopMenu.value) {
      forceCloseMenuSub.add(true);
      return false;
    }
    Get.back();

    return true;
  }

  void focusNodeChanged(bool hasFocus) {
    _changeInputStatus(hasFocus);
    if (hasFocus) {
      Logger.print('focus:$hasFocus');
      scrollBottom();
    }
  }

  void copy(Message message) {
    final content = copyTextMap[message.clientMsgID] ?? message.textElem?.content;

    if (null != content) {
      IMUtils.copy(text: content.replaceAll('\u200B', ''));
    }
  }

  Message indexOfMessage(int index, {bool calculate = true}) {
    Logger.print('获取消息索引 - 索引: $index, 计算时间间隔: $calculate');
    final result = IMUtils.calChatTimeInterval(
      messageList,
      calculate: calculate,
    ).reversed.elementAt(index);
    Logger.print('获取到消息 - ID: ${result.clientMsgID}, 类型: ${result.contentType}');
    return result;
  }

  ValueKey itemKey(Message message) {
    final key = ValueKey(message.clientMsgID!);
    Logger.print('获取项目键 - 消息ID: ${message.clientMsgID}, 键值: $key');
    return key;
  }

  @override
  void onClose() {
    Logger.print('=== 开始清理聊天页面资源 ===');
    
    sendTypingMsg();
    _clearUnreadCount();
    _unSubscribeUserOnlineStatus();
    
    Logger.print('清理控制器资源...');
    inputCtrl.dispose();
    focusNode.dispose();
    _audioPlayer.dispose();
    
    Logger.print('关闭事件流...');
    forceCloseToolbox.close();
    conversationSub.cancel();
    sendStatusSub.close();
    memberAddSub.cancel();
    memberDelSub.cancel();
    memberInfoChangedSub.cancel();
    groupInfoUpdatedSub.cancel();
    friendInfoChangedSub.cancel();
    userStatusChangedSub?.cancel();
    selfInfoUpdatedSub?.cancel();
    forceCloseMenuSub.close();
    joinedGroupAddedSub.cancel();
    joinedGroupDeletedSub.cancel();
    connectionSub.cancel();

    _debounce?.cancel();
    
    Logger.print('清理消息相关资源...');
    // 清理GlobalKey映射
    final keyCount = _messageKeys.length;
    _messageKeys.clear();
    Logger.print('清理消息GlobalKey映射 - 清理了 $keyCount 个键值对');
    
    // 重置标志
    _isLoadingHistoryForSearch = false;
    _isFirstLoad = true;
    Logger.print('重置标志 - 搜索加载: $_isLoadingHistoryForSearch, 首次加载: $_isFirstLoad');
    
    Logger.print('=== 聊天页面资源清理完成 ===');
    super.onClose();
  }

  String? getShowTime(Message message) {
    final showTime = message.exMap['showTime'] == true;
    if (showTime) {
      final timeline = IMUtils.getChatTimeline(message.sendTime!);
      Logger.print('显示消息时间 - 消息ID: ${message.clientMsgID}, 时间: $timeline');
      return timeline;
    }
    return null;
  }

  void clearAllMessage() {
    Logger.print('=== 清除所有消息 ===');
    final count = messageList.length;
    messageList.clear();
    Logger.print('清除了 $count 条消息');
    Logger.print('=== 清除所有消息完成 ===');
  }

  void onAddEmoji(String emoji) {
    var input = inputCtrl.text;
    if (_lastCursorIndex != -1 && input.isNotEmpty) {
      var part1 = input.substring(0, _lastCursorIndex);
      var part2 = input.substring(_lastCursorIndex);
      inputCtrl.text = '$part1$emoji$part2';
      _lastCursorIndex = _lastCursorIndex + emoji.length;
    } else {
      inputCtrl.text = '$input$emoji';
      _lastCursorIndex = emoji.length;
    }
    inputCtrl.selection = TextSelection.fromPosition(TextPosition(
      offset: _lastCursorIndex,
    ));
  }

  void onDeleteEmoji() {
    final input = inputCtrl.text;
    final regexEmoji = emojiFaces.keys.toList().join('|').replaceAll('[', '\\[').replaceAll(']', '\\]');
    final list = [regexEmoji];
    final pattern = '(${list.toList().join('|')})';
    final emojiReg = RegExp(regexEmoji);
    var reg = RegExp(pattern);
    var cursor = _lastCursorIndex;
    if (cursor == 0) return;
    Match? match;
    if (reg.hasMatch(input)) {
      for (var m in reg.allMatches(input)) {
        var matchText = m.group(0)!;
        var start = m.start;
        var end = start + matchText.length;
        if (end == cursor) {
          match = m;
          break;
        }
      }
    }
    var matchText = match?.group(0);
    if (matchText != null) {
      var start = match!.start;
      var end = start + matchText.length;
      if (emojiReg.hasMatch(matchText)) {
        inputCtrl.text = input.replaceRange(start, end, "");
        cursor = start;
      } else {
        inputCtrl.text = input.replaceRange(cursor - 1, cursor, '');
        --cursor;
      }
    } else {
      inputCtrl.text = input.replaceRange(cursor - 1, cursor, '');
      --cursor;
    }
    _lastCursorIndex = cursor;
  }

  String? get subTile {
    final result = typing.value ? StrRes.typing : onlineStatusDesc.value;
    Logger.print('获取子标题 - 正在输入: ${typing.value}, 在线状态: ${onlineStatusDesc.value}, 结果: $result');
    return result;
  }

  bool showOnlineStatus() {
    final result = !typing.value && onlineStatusDesc.isNotEmpty;
    Logger.print('显示在线状态 - 正在输入: ${typing.value}, 在线状态描述: ${onlineStatusDesc.value}, 结果: $result');
    return result;
  }

  bool enabledReadStatus(Message message) {
    final isNotification = message.isNotificationType;
    final result = !isNotification;
    Logger.print('启用已读状态 - 消息ID: ${message.clientMsgID}, 是否通知类型: $isNotification, 结果: $result');
    return result;
  }

  void favoriteManage() => AppNavigator.startFavoriteMange();

  void addEmoji(Message message) {
    if (message.contentType == MessageType.picture) {
      var url = message.pictureElem?.sourcePicture?.url;
      var width = message.pictureElem?.sourcePicture?.width;
      var height = message.pictureElem?.sourcePicture?.height;
      cacheLogic.addFavoriteFromUrl(url, width, height);
      IMViews.showToast(StrRes.addSuccessfully);
    } else if (message.contentType == MessageType.customFace) {
      var index = message.faceElem?.index;
      var data = message.faceElem?.data;
      if (-1 != index) {
      } else if (null != data) {
        var map = json.decode(data);
        var url = map['url'];
        var width = map['width'];
        var height = map['height'];
        cacheLogic.addFavoriteFromUrl(url, width, height);
        IMViews.showToast(StrRes.addSuccessfully);
      }
    }
  }

  void sendFavoritePic(int index, String url) async {
    var emoji = cacheLogic.favoriteList.elementAt(index);
    var message = await OpenIM.iMManager.messageManager.createFaceMessage(
      data: json.encode({'url': emoji.url, 'width': emoji.width, 'height': emoji.height}),
    );
    _sendMessage(message);
  }

  void _initChatConfig() async {
    scaleFactor.value = DataSp.getChatFontSizeFactor();
    var path = DataSp.getChatBackground(otherId) ?? '';
    if (path.isNotEmpty && (await File(path).exists())) {
      background.value = path;
    }
  }

  String get otherId => isSingleChat ? userID! : groupID!;

  void failedResend(Message message) {
    Logger.print('failedResend: ${message.clientMsgID}');
    if (message.status == MessageStatus.sending) {
      return;
    }
    sendStatusSub.addSafely(MsgStreamEv<bool>(
      id: message.clientMsgID!,
      value: true,
    ));

    Logger.print('failedResending: ${message.clientMsgID}');
    _sendMessage(message..status = MessageStatus.sending, addToUI: false);
  }

  int readTime(Message message) {
    var isPrivate = message.attachedInfoElem?.isPrivateChat ?? false;
    var burnDuration = message.attachedInfoElem?.burnDuration ?? 30;
    burnDuration = burnDuration > 0 ? burnDuration : 30;
    if (isPrivate) {
      var hasReadTime = message.hasReadTime ?? 0;
      if (hasReadTime > 0) {
        var end = hasReadTime + (burnDuration * 1000);

        var diff = (end - _timestamp) ~/ 1000;

        if (diff > 0) {
          privateMessageList.addIf(() => !privateMessageList.contains(message), message);
        }
        return diff < 0 ? 0 : diff;
      }
    }
    return 0;
  }

  static int get _timestamp => DateTime.now().millisecondsSinceEpoch;

  void destroyMsg() {
    for (var message in privateMessageList) {
      OpenIM.iMManager.messageManager.deleteMessageFromLocalAndSvr(
        conversationID: conversationInfo.conversationID,
        clientMsgID: message.clientMsgID!,
      );
    }
  }

  Future _queryMyGroupMemberInfo() async {
    if (!isGroupChat) {
      return;
    }
    var list = await OpenIM.iMManager.groupManager.getGroupMembersInfo(
      groupID: groupID!,
      userIDList: [OpenIM.iMManager.userID],
    );
    groupMembersInfo = list.firstOrNull;
    groupMemberRoleLevel.value = groupMembersInfo?.roleLevel ?? GroupRoleLevel.member;
    muteEndTime.value = groupMembersInfo?.muteEndTime ?? 0;
    if (null != groupMembersInfo) {
      memberUpdateInfoMap[OpenIM.iMManager.userID] = groupMembersInfo!;
    }

    return;
  }

  Future _queryOwnerAndAdmin() async {
    if (isGroupChat) {
      ownerAndAdmin = await OpenIM.iMManager.groupManager.getGroupMemberList(groupID: groupID!, filter: 5, count: 20);
    }
    return;
  }

  void _isJoinedGroup() async {
    if (!isGroupChat) {
      return;
    }
    isInGroup.value = await OpenIM.iMManager.groupManager.isJoinedGroup(
      groupID: groupID!,
    );
    if (!isInGroup.value) {
      return;
    }
    _queryGroupInfo();
    _queryOwnerAndAdmin();
  }

  void _queryGroupInfo() async {
    if (!isGroupChat) {
      return;
    }
    var list = await OpenIM.iMManager.groupManager.getGroupsInfo(
      groupIDList: [groupID!],
    );
    groupInfo = list.firstOrNull;
    groupOwnerID = groupInfo?.ownerUserID;
    groupMutedStatus.value = groupInfo?.status ?? 0;
    if (null != groupInfo?.memberCount) {
      memberCount.value = groupInfo!.memberCount!;
    }
    _queryMyGroupMemberInfo();
  }

  bool get havePermissionMute =>
      isGroupChat &&
      (groupInfo?.ownerUserID == OpenIM.iMManager.userID /*||
          groupMembersInfo?.roleLevel == 2*/
      );

  bool isNotificationType(Message message) {
    final result = message.contentType! >= 1000;
    Logger.print('是否是通知类型 - 消息ID: ${message.clientMsgID}, 消息类型: ${message.contentType}, 结果: $result');
    return result;
  }

  Map<String, String> getAtMapping(Message message) {
    Logger.print('获取@映射 - 消息ID: ${message.clientMsgID}');
    final result = <String, String>{};
    Logger.print('返回空映射');
    return result;
  }

  void _queryUserOnlineStatus() {
    if (isSingleChat) {
      OpenIM.iMManager.userManager.subscribeUsersStatus([userID!]).then((value) {
        final status = value.firstWhereOrNull((element) => element.userID == userID);
        _configUserStatusChanged(status);
      });
      userStatusChangedSub = imLogic.userStatusChangedSubject.listen((value) {
        if (value.userID == userID) {
          _configUserStatusChanged(value);
        }
      });
    }
  }

  void _unSubscribeUserOnlineStatus() {
    if (isSingleChat) {
      OpenIM.iMManager.userManager.unsubscribeUsersStatus([userID!]);
    }
  }

  void _configUserStatusChanged(UserStatusInfo? status) {
    if (status != null) {
      onlineStatus.value = status.status == 1;
      onlineStatusDesc.value =
          status.status == 0 ? StrRes.offline : _onlineStatusDes(status.platformIDs!) + StrRes.online;
    }
  }

  String _onlineStatusDes(List<int> plamtforms) {
    var des = <String>[];
    for (final platform in plamtforms) {
      switch (platform) {
        case 1:
          des.add('iOS');
          break;
        case 2:
          des.add('Android');
          break;
        case 3:
          des.add('Windows');
          break;
        case 4:
          des.add('Mac');
          break;
        case 5:
          des.add('Web');
          break;
        case 6:
          des.add('mini_web');
          break;
        case 7:
          des.add('Linux');
          break;
        case 8:
          des.add('Android_pad');
          break;
        case 9:
          des.add('iPad');
          break;
        default:
      }
    }

    return des.join('/');
  }

  void _checkInBlacklist() async {
    if (userID != null) {
      var list = await OpenIM.iMManager.friendshipManager.getBlacklist();
      var user = list.firstWhereOrNull((e) => e.userID == userID);
      isInBlacklist.value = user != null;
    }
  }

  bool isExceed24H(Message message) {
    int milliseconds = message.sendTime!;
    return !DateUtil.isToday(milliseconds);
  }

  bool isPlaySound(Message message) {
    return _currentPlayClientMsgID.value == message.clientMsgID!;
  }

  void _initPlayListener() {
    _audioPlayer.playerStateStream.listen((state) {
      switch (state.processingState) {
        case ProcessingState.idle:
        case ProcessingState.loading:
        case ProcessingState.buffering:
        case ProcessingState.ready:
          break;
        case ProcessingState.completed:
          _currentPlayClientMsgID.value = "";
          break;
      }
    });
  }

  void _playVoiceMessage(Message message) async {
    var isClickSame = _currentPlayClientMsgID.value == message.clientMsgID;
    if (_audioPlayer.playerState.playing) {
      _currentPlayClientMsgID.value = "";
      _audioPlayer.stop();
    }
    if (!isClickSame) {
      bool isValid = await _initVoiceSource(message);
      if (isValid) {
        _audioPlayer.setVolume(rtcIsBusy ? 0 : 1.0);
        _audioPlayer.seek(Duration.zero);
        _audioPlayer.play();
        _currentPlayClientMsgID.value = message.clientMsgID!;
      }
    }
  }

  void stopVoice() {
    if (_audioPlayer.playerState.playing) {
      _currentPlayClientMsgID.value = '';
      _audioPlayer.stop();
    }
  }

  Future<bool> _initVoiceSource(Message message) async {
    bool isReceived = message.sendID != OpenIM.iMManager.userID;
    String? path = message.soundElem?.soundPath;
    String? url = message.soundElem?.sourceUrl;
    bool isExistSource = false;
    if (isReceived) {
      if (null != url && url.trim().isNotEmpty) {
        isExistSource = true;
        _audioPlayer.setUrl(url);
      }
    } else {
      bool existFile = false;
      if (path != null && path.trim().isNotEmpty) {
        var file = File(path);
        existFile = await file.exists();
      }
      if (existFile) {
        isExistSource = true;
        _audioPlayer.setFilePath(path!);
      } else if (null != url && url.trim().isNotEmpty) {
        isExistSource = true;
        _audioPlayer.setUrl(url);
      }
    }
    return isExistSource;
  }

  void onPopMenuShowChanged(show) {
    isShowPopMenu.value = show;
    if (!show && scrollingCacheMessageList.isNotEmpty) {
      messageList.addAll(scrollingCacheMessageList);
      scrollingCacheMessageList.clear();
    }
  }

  String? getNewestNickname(Message message) {
    if (isSingleChat) null;

    return message.senderNickname;
  }

  String? getNewestFaceURL(Message message) {
    return message.senderFaceUrl;
  }

  bool get isInvalidGroup {
    final result = !isInGroup.value && isGroupChat;
    Logger.print('是否是无效群组 - 在群组中: ${isInGroup.value}, 是群聊: $isGroupChat, 结果: $result');
    return result;
  }

  void _resetGroupAtType() {
    Logger.print('重置群组@类型 - 当前@类型: ${conversationInfo.groupAtType}');
    
    if (conversationInfo.groupAtType != GroupAtType.atNormal) {
      Logger.print('@类型不是正常状态，开始重置');
      OpenIM.iMManager.conversationManager.resetConversationGroupAtType(
        conversationID: conversationInfo.conversationID,
      );
      Logger.print('重置@类型完成');
    } else {
      Logger.print('@类型已经是正常状态，无需重置');
    }
  }

  void revokeMsgV2(Message message) async {
    late bool canRevoke;
    if (isGroupChat) {
      if (message.sendID == OpenIM.iMManager.userID) {
        canRevoke = true;
      } else {
        var list = await LoadingView.singleton
            .wrap(asyncFunction: () => OpenIM.iMManager.groupManager.getGroupOwnerAndAdmin(groupID: groupID!));
        var sender = list.firstWhereOrNull((e) => e.userID == message.sendID);
        var revoker = list.firstWhereOrNull((e) => e.userID == OpenIM.iMManager.userID);

        if (revoker != null && sender == null) {
          canRevoke = true;
        } else if (revoker == null && sender != null) {
          canRevoke = false;
        } else if (revoker != null && sender != null) {
          if (revoker.roleLevel == sender.roleLevel) {
            canRevoke = false;
          } else if (revoker.roleLevel == GroupRoleLevel.owner) {
            canRevoke = true;
          } else {
            canRevoke = false;
          }
        } else {
          canRevoke = false;
        }
      }
    } else {
      if (message.sendID == OpenIM.iMManager.userID) {
        canRevoke = true;
      }
    }
    if (canRevoke) {
      try {
        await LoadingView.singleton.wrap(
          asyncFunction: () => OpenIM.iMManager.messageManager.revokeMessage(
            conversationID: conversationInfo.conversationID,
            clientMsgID: message.clientMsgID!,
          ),
        );
        message.contentType = MessageType.revokeMessageNotification;
        message.notificationElem = NotificationElem(detail: jsonEncode(_buildRevokeInfo(message)));
        messageList.refresh();
      } catch (e) {
        IMViews.showToast(e.toString());
      }
    } else {
      IMViews.showToast('no permission');
    }
  }

  RevokedInfo _buildRevokeInfo(Message message) {
    return RevokedInfo.fromJson({
      'revokerID': OpenIM.iMManager.userInfo.userID,
      'revokerRole': 0,
      'revokerNickname': OpenIM.iMManager.userInfo.nickname,
      'clientMsgID': message.clientMsgID,
      'revokeTime': 0,
      'sourceMessageSendTime': 0,
      'sourceMessageSendID': message.sendID,
      'sourceMessageSenderNickname': message.senderNickname,
      'sessionType': message.sessionType,
    });
  }

  bool showCopyMenu(Message message) {
    return message.isTextType;
  }

  bool showDelMenu(Message message) {
    return true;
  }

  bool showForwardMenu(Message message) {
    if (message.status != MessageStatus.succeeded) {
      return false;
    }
    if (message.isNotificationType) {
      return false;
    }
    return true;
  }

  bool showReplyMenu(Message message) {
    if (message.status != MessageStatus.succeeded) {
      return false;
    }
    return message.isTextType ||
        message.isVideoType ||
        message.isPictureType ||
        message.isLocationType ||
        message.isFileType ||
        message.isCardType ||
        message.isCustomFaceType;
  }

  bool showRevokeMenu(Message message) {
    if (message.status != MessageStatus.succeeded ||
        message.isNotificationType ||
        isExceed24H(message) && isSingleChat) {
      return false;
    }
    if (isGroupChat) {
      if (groupMemberRoleLevel.value == GroupRoleLevel.owner ||
          (groupMemberRoleLevel.value == GroupRoleLevel.admin &&
              ownerAndAdmin.firstWhereOrNull((element) => element.userID == message.sendID) == null)) {
        return true;
      }
    }
    if (message.sendID == OpenIM.iMManager.userID) {
      if (DateTime.now().millisecondsSinceEpoch - (message.sendTime ??= 0) < (1000 * 60 * 5)) {
        return true;
      }
    }
    return false;
  }

  bool showAddEmojiMenu(Message message) {
    if (message.status != MessageStatus.succeeded) {
      return false;
    }
    return message.contentType == MessageType.picture || message.contentType == MessageType.customFace;
  }

  WillPopCallback? willPop() {
    return isShowPopMenu.value ? () async => exit() : null;
  }

  void expandCallingMemberPanel() {
    showCallingMember.value = !showCallingMember.value;
  }

  void call() {
    if (rtcIsBusy) {
      IMViews.showToast(StrRes.callingBusy);
      return;
    }

    IMViews.openIMCallSheet(nickname.value, (index) {
      imLogic.call(
        callObj: CallObj.single,
        callType: index == 0 ? CallType.audio : CallType.video,
        inviteeUserIDList: [if (isSingleChat) userID!],
      );
    });
  }

  void onScrollToTop() {
    if (scrollingCacheMessageList.isNotEmpty) {
      messageList.addAll(scrollingCacheMessageList);
      scrollingCacheMessageList.clear();
    }
  }

  String get markText {
    String? phoneNumber = imLogic.userInfo.value.phoneNumber;
    if (phoneNumber != null) {
      int start = phoneNumber.length > 4 ? phoneNumber.length - 4 : 0;
      final sub = phoneNumber.substring(start);
      return "${OpenIM.iMManager.userInfo.nickname!}$sub";
    }
    return OpenIM.iMManager.userInfo.nickname ?? '';
  }

  bool isFailedHintMessage(Message message) {
    Logger.print('检查是否是失败提示消息 - 消息ID: ${message.clientMsgID}, 消息类型: ${message.contentType}');
    
    if (message.contentType == MessageType.custom) {
      var data = message.customElem!.data;
      var map = json.decode(data!);
      var customType = map['customType'];
      final result = customType == CustomMessageType.deletedByFriend || customType == CustomMessageType.blockedByFriend;
      
      Logger.print('自定义消息类型: $customType, 结果: $result');
      return result;
    }
    
    Logger.print('非自定义消息，返回false');
    return false;
  }

  void sendFriendVerification() => AppNavigator.startSendVerificationApplication(userID: userID);

  void _setSdkSyncDataListener() {
    Logger.print('设置SDK同步数据监听器');
    connectionSub = imLogic.imSdkStatusPublishSubject.listen((value) {
      Logger.print('SDK状态变化 - 状态: ${value.status}');
      syncStatus.value = value.status;
      
      if (value.status == IMSdkStatus.syncStart) {
        Logger.print('开始同步数据');
        _isStartSyncing = true;
      } else if (value.status == IMSdkStatus.syncEnded) {
        Logger.print('同步数据结束');
        if (/*_isReceivedMessageWhenSyncing &&*/ _isStartSyncing) {
          Logger.print('开始加载同步结束后的历史消息');
          _isReceivedMessageWhenSyncing = false;
          _isStartSyncing = false;
          _isFirstLoad = true;
          _loadHistoryForSyncEnd();
        } else {
          Logger.print('跳过同步结束后的历史消息加载');
        }
      } else if (value.status == IMSdkStatus.syncFailed) {
        Logger.print('同步数据失败');
        _isReceivedMessageWhenSyncing = false;
        _isStartSyncing = false;
      }
    });
  }

  bool get isSyncFailed {
    final result = syncStatus.value == IMSdkStatus.syncFailed;
    Logger.print('是否是同步失败 - 同步状态: ${syncStatus.value}, 结果: $result');
    return result;
  }

  String? get syncStatusStr {
    Logger.print('获取同步状态字符串 - 同步状态: ${syncStatus.value}');
    
    String? result;
    switch (syncStatus.value) {
      case IMSdkStatus.syncStart:
      case IMSdkStatus.synchronizing:
        result = StrRes.synchronizing;
        break;
      case IMSdkStatus.syncFailed:
        result = StrRes.syncFailed;
        break;
      default:
        result = null;
        break;
    }
    
    Logger.print('同步状态字符串结果: $result');
    return result;
  }

  bool showBubbleBg(Message message) {
    final isNotification = isNotificationType(message);
    final isFailedHint = isFailedHintMessage(message);
    final isRevoke = isRevokeMessage(message);
    final result = !isNotification && !isFailedHint && !isRevoke;
    
    Logger.print('显示气泡背景 - 消息ID: ${message.clientMsgID}');
    Logger.print('判断条件 - 通知类型: $isNotification, 失败提示: $isFailedHint, 撤回消息: $isRevoke');
    Logger.print('显示结果: $result');
    
    return result;
  }

  bool isRevokeMessage(Message message) {
    final result = message.contentType == MessageType.revokeMessageNotification;
    Logger.print('是否是撤回消息 - 消息ID: ${message.clientMsgID}, 消息类型: ${message.contentType}, 结果: $result');
    return result;
  }

  void markRevokedMessage(Message message) {
    Logger.print('标记撤回消息 - 消息ID: ${message.clientMsgID}, 消息类型: ${message.contentType}');
    
    if (message.contentType == MessageType.text) {
      Logger.print('保存撤回的文本消息');
      revokedTextMessage[message.clientMsgID!] = jsonEncode(message);
    } else {
      Logger.print('非文本消息，跳过保存');
    }
  }

  Future<AdvancedMessage> _fetchHistoryMessages() {
    Logger.print('=== 开始获取历史消息 ===');
    Logger.print('是否首次加载: $_isFirstLoad');
    Logger.print('页面大小: $_pageSize');
    Logger.print('会话ID: ${conversationInfo.conversationID}');
    
    if (_isFirstLoad) {
      Logger.print('首次加载，不指定起始消息');
    } else {
      final firstMsg = messageList.firstOrNull;
      Logger.print('非首次加载，起始消息ID: ${firstMsg?.clientMsgID}');
    }
    
    Logger.print('调用SDK获取历史消息...');
    return OpenIM.iMManager.messageManager.getAdvancedHistoryMessageList(
      conversationID: conversationInfo.conversationID,
      count: _pageSize,
      startMsg: _isFirstLoad ? null : messageList.firstOrNull,
    );
  }

  Future<bool> onScrollToBottomLoad() async {
    Logger.print('=== 开始滚动加载历史消息 ===');
    
    // 如果正在为搜索加载历史消息，跳过正常的加载
    if (_isLoadingHistoryForSearch) {
      Logger.print('正在为搜索加载历史消息，跳过正常的滚动加载');
      return true; // 返回true表示还有更多数据，继续允许滚动
    }
    
    Logger.print('开始获取历史消息...');
    late List<Message> list;
    final result = await _fetchHistoryMessages();
    
    if (result.messageList == null || result.messageList!.isEmpty) {
      Logger.print('没有更多历史消息');
      _getGroupInfoAfterLoadMessage();
      return false;
    }
    
    list = result.messageList!;
    Logger.print('获取到 ${list.length} 条历史消息');
    if (_isFirstLoad) {
      Logger.print('首次加载历史消息');
      _isFirstLoad = false;
      
      // remove the message that has been timed down
      final beforeRemoveCount = list.length;
      list.removeWhere((msg) => _isBeDeleteMessage(msg));
      final afterRemoveCount = list.length;
      Logger.print('移除过期消息 - 移除前: $beforeRemoveCount, 移除后: $afterRemoveCount');
      
      messageList.assignAll(list);
      Logger.print('首次加载完成，消息列表长度: ${messageList.length}');
      
      // 清理重复消息
      _removeMessageDuplicates();
      
      scrollBottom();
      
      // 消息列表发生变化，需要重新计算高度
      Logger.print('消息列表发生变化，需要重新计算高度');

      _getGroupInfoAfterLoadMessage();
    } else {
      Logger.print('非首次加载历史消息');
      
      final beforeRemoveCount = list.length;
      list.removeWhere((msg) => _isBeDeleteMessage(msg));
      final afterRemoveCount = list.length;
      Logger.print('移除过期消息 - 移除前: $beforeRemoveCount, 移除后: $afterRemoveCount');
      
      // 过滤掉已经存在的消息，避免重复
      final existingMsgIDs = messageList.map((msg) => msg.clientMsgID).toSet();
      final uniqueNewMessages = list.where((msg) => 
        !existingMsgIDs.contains(msg.clientMsgID)
      ).toList();
      
      Logger.print('去重结果 - 原始数量: ${list.length}, 去重后数量: ${uniqueNewMessages.length}');
      
      if (uniqueNewMessages.isNotEmpty) {
        messageList.insertAll(0, uniqueNewMessages);
        Logger.print('滚动加载：添加了 ${uniqueNewMessages.length} 条新消息，过滤掉 ${list.length - uniqueNewMessages.length} 条重复消息');
        _checkMessageDuplicates(); // 检查是否有重复
      } else {
        Logger.print('滚动加载：所有新消息都已存在，跳过添加');
      }
      
      // 消息列表发生变化，需要重新计算高度
      Logger.print('消息列表发生变化，需要重新计算高度');
    }

    final hasMore = result.isEnd != true;
    Logger.print('滚动加载完成，是否还有更多数据: $hasMore');
    return hasMore;
  }

  Future<void> _loadHistoryForSyncEnd() async {
    Logger.print('=== 开始同步结束加载历史消息 ===');
    
    // 如果正在为搜索加载历史消息，跳过同步结束的加载
    if (_isLoadingHistoryForSearch) {
      Logger.print('正在为搜索加载历史消息，跳过同步结束的加载');
      return;
    }
    
    final targetCount = messageList.length < _pageSize ? _pageSize : messageList.length;
    Logger.print('目标加载数量: $targetCount, 当前消息数量: ${messageList.length}');
    
    final result = await OpenIM.iMManager.messageManager.getAdvancedHistoryMessageList(
      conversationID: conversationInfo.conversationID,
      count: targetCount,
      startMsg: null,
    );
    
    if (result.messageList == null || result.messageList!.isEmpty) {
      Logger.print('同步结束加载：没有获取到历史消息');
      return;
    }
    
    final list = result.messageList!;
    Logger.print('同步结束加载：获取到 ${list.length} 条历史消息');
    
    final beforeRemoveCount = list.length;
    list.removeWhere((msg) => _isBeDeleteMessage(msg));
    final afterRemoveCount = list.length;
    Logger.print('移除过期消息 - 移除前: $beforeRemoveCount, 移除后: $afterRemoveCount');

    final offset = scrollController.offset;
    final oldCount = messageList.length;
    messageList.assignAll(list);
    
    // 清理重复消息
    _removeMessageDuplicates();
    
    final newCount = messageList.length;
    Logger.print('同步结束加载：消息列表从 $oldCount 条更新为 $newCount 条');
    Logger.print('恢复滚动位置: $offset');
    scrollController.jumpTo(offset);
    
    // 消息列表发生变化，需要重新计算高度
    Logger.print('消息列表发生变化，需要重新计算高度');
    
    Logger.print('=== 同步结束加载完成 ===');
  }

  bool _isBeDeleteMessage(Message message) {
    Logger.print('检查是否是过期消息 - 消息ID: ${message.clientMsgID}');
    
    final isPrivate = message.attachedInfoElem?.isPrivateChat ?? false;
    final hasReadTime = message.hasReadTime ?? 0;
    
    Logger.print('消息属性 - 是否私聊: $isPrivate, 已读时间: $hasReadTime');
    
    if (isPrivate && hasReadTime > 0) {
      final readTimeValue = readTime(message);
      final result = readTimeValue <= 0;
      Logger.print('私聊消息已读时间检查 - 剩余时间: $readTimeValue, 是否过期: $result');
      return result;
    }
    
    Logger.print('非私聊消息或未读，不过期');
    return false;
  }

  void _getGroupInfoAfterLoadMessage() {
    Logger.print('加载消息后获取群组信息 - 是否群聊: $isGroupChat, 管理员列表长度: ${ownerAndAdmin.length}');
    
    if (isGroupChat && ownerAndAdmin.isEmpty) {
      Logger.print('群聊且管理员列表为空，检查是否在群组中');
      _isJoinedGroup();
    } else {
      Logger.print('非群聊或管理员列表不为空，检查黑名单');
      _checkInBlacklist();
    }
  }

  recommendFriendCarte(UserInfo userInfo) async {
    Logger.print('=== 开始推荐好友名片 ===');
    Logger.print('用户信息 - ID: ${userInfo.userID}, 昵称: ${userInfo.nickname}');
    
    final result = await AppNavigator.startSelectContacts(
      action: SelAction.recommend,
      ex: '[${StrRes.carte}]${userInfo.nickname}',
    );
    
    if (null != result) {
      Logger.print('选择联系人结果: $result');
      final customEx = result['customEx'];
      final checkedList = result['checkedList'];
      Logger.print('自定义说明: $customEx, 选中列表长度: ${checkedList.length}');
      
      for (var info in checkedList) {
        final userID = IMUtils.convertCheckedToUserID(info);
        final groupID = IMUtils.convertCheckedToGroupID(info);
        Logger.print('处理联系人 - 用户ID: $userID, 群组ID: $groupID');
        
        if (customEx is String && customEx.isNotEmpty) {
          Logger.print('发送自定义说明消息');
          _sendMessage(
            await OpenIM.iMManager.messageManager.createTextMessage(
              text: customEx,
            ),
            userId: userID,
            groupId: groupID,
          );
        }
        
        Logger.print('发送名片消息');
        _sendMessage(
          await OpenIM.iMManager.messageManager.createCardMessage(
            userID: userInfo.userID!,
            nickname: userInfo.nickname!,
            faceURL: userInfo.faceURL,
          ),
          userId: userID,
          groupId: groupID,
        );
      }
    } else {
      Logger.print('未选择联系人');
    }
    
    Logger.print('=== 推荐好友名片完成 ===');
  }

  void joinMeeting(Message msg) {
    Logger.print('加入会议 - 消息ID: ${msg.clientMsgID}, 消息类型: ${msg.contentType}');
    // 这里可以添加加入会议的逻辑
  }
  
  /// 获取消息项的GlobalKey
  GlobalKey getMessageKey(Message message) {
    final clientMsgID = message.clientMsgID ?? '';
    Logger.print('获取消息GlobalKey - 消息ID: $clientMsgID');
    
    if (!_messageKeys.containsKey(clientMsgID)) {
      Logger.print('创建新的GlobalKey - 消息ID: $clientMsgID');
      _messageKeys[clientMsgID] = GlobalKey();
    } else {
      Logger.print('使用已存在的GlobalKey - 消息ID: $clientMsgID');
    }
    
    final key = _messageKeys[clientMsgID]!;
    Logger.print('返回GlobalKey - 消息ID: $clientMsgID, 键值对数量: ${_messageKeys.length}');
    return key;
  }
  

  
  /// 等待消息列表初始化完成
  Future<void> _waitForMessageListInitialized() async {
    Logger.print('开始等待消息列表初始化 - 当前长度: ${messageList.length}, 是否首次加载: $_isFirstLoad');
    
    // 如果消息列表为空且不是第一次加载，等待初始化
    if (messageList.isEmpty && !_isFirstLoad) {
      Logger.print('消息列表为空且非首次加载，开始等待初始化...');
      int waitCount = 0;
      const maxWaitCount = 50; // 最多等待5秒
      
      while (messageList.isEmpty && waitCount < maxWaitCount) {
        await Future.delayed(Duration(milliseconds: 100));
        waitCount++;
        Logger.print('等待消息列表初始化 - 等待次数: $waitCount, 当前长度: ${messageList.length}');
      }
      
      if (messageList.isEmpty) {
        Logger.print('消息列表初始化超时 - 等待了 ${waitCount * 100}ms');
      } else {
        Logger.print('消息列表初始化完成 - 等待了 ${waitCount * 100}ms, 最终长度: ${messageList.length}');
      }
    } else {
      Logger.print('消息列表已初始化或正在首次加载，无需等待');
    }
  }
  
  /// 检查是否正在加载历史消息
  bool get isLoadingHistory {
    final result = _isLoadingHistoryForSearch || _isFirstLoad;
    Logger.print('是否正在加载历史消息 - 搜索加载: $_isLoadingHistoryForSearch, 首次加载: $_isFirstLoad, 结果: $result');
    return result;
  }
  
  /// 检查消息列表中是否有重复项
  void _checkMessageDuplicates() {
    Logger.print('开始检查消息列表重复项 - 当前消息数量: ${messageList.length}');
    
    final msgIDs = messageList.map((msg) => msg.clientMsgID).toList();
    final uniqueIDs = msgIDs.toSet();
    
    Logger.print('消息ID统计 - 总数量: ${msgIDs.length}, 唯一数量: ${uniqueIDs.length}');
    
    if (msgIDs.length != uniqueIDs.length) {
      final duplicates = <String, int>{};
      for (final id in msgIDs) {
        if(id != null) duplicates[id] = (duplicates[id] ?? 0) + 1;
      }
      
      final duplicateItems = duplicates.entries.where((e) => e.value > 1);
      Logger.print('发现重复消息：${duplicateItems.length} 个重复的clientMsgID');
      for (final item in duplicateItems) {
        Logger.print('重复的clientMsgID: ${item.key}, 出现次数: ${item.value}');
      }
    } else {
      Logger.print('消息列表无重复项，总数量: ${msgIDs.length}');
    }
  }
  
  /// 清理消息列表中的重复项
  void _removeMessageDuplicates() {
    Logger.print('开始清理消息列表重复项 - 当前消息数量: ${messageList.length}');
    
    final seenIDs = <String>{};
    final uniqueMessages = <Message>[];
    
    for (final message in messageList) {
      final clientMsgID = message.clientMsgID ?? '';
      if (clientMsgID.isNotEmpty && !seenIDs.contains(clientMsgID)) {
        seenIDs.add(clientMsgID);
        uniqueMessages.add(message);
      }
    }
    
    Logger.print('去重结果 - 原始数量: ${messageList.length}, 去重后数量: ${uniqueMessages.length}');
    
    if (uniqueMessages.length != messageList.length) {
      final removedCount = messageList.length - uniqueMessages.length;
      Logger.print('清理重复消息：移除了 $removedCount 条重复消息');
      messageList.assignAll(uniqueMessages);
    } else {
      Logger.print('无需清理重复消息');
    }
  }
  
  /// 计算反向ListView中目标消息的滚动位置
  double _calculateReverseListViewScrollPosition(int targetIndex) {
    Logger.print('开始计算反向ListView滚动位置 - 目标索引: $targetIndex');
    
    // 在反向ListView中：
    // - messageList[0] = 最早的消息，显示在ListView顶部
    // - messageList[n] = 最新的消息，显示在ListView底部
    // - 滚动位置0 = 底部（最新消息）
    // - 滚动位置maxScrollExtent = 顶部（最早消息）
    
    final itemCount = messageList.length;
    if (targetIndex < 0 || targetIndex >= itemCount) {
      Logger.print('目标索引超出范围: $targetIndex, 总消息数: $itemCount');
      return 0.0;
    }
    
    // 计算从底部到目标消息的总高度
    double totalHeight = 0.0;
    int calculatedCount = 0;
    
    Logger.print('开始累加消息高度 - 从索引 ${itemCount - 1} 到 ${targetIndex + 1}');
    
    // 从最新消息（底部）开始计算到目标消息
    for (int i = itemCount - 1; i > targetIndex; i--) {
      final messageHeight = _getActualMessageHeight(i);
      totalHeight += messageHeight;
      calculatedCount++;
      
      Logger.print('累加消息高度 - 索引: $i, 高度: $messageHeight, 累计高度: $totalHeight');
    }
    
    Logger.print('反向ListView滚动计算完成 - 目标索引: $targetIndex, 计算消息数: $calculatedCount, 总高度: $totalHeight');
    
    return totalHeight;
  }
  
  /// 等待消息项渲染完成
  Future<void> _waitForMessageRendering() async {
    Logger.print('开始等待消息项渲染完成');
    
    // 等待一帧，确保所有消息项都已渲染
    await Future.delayed(Duration(milliseconds: 50));
    
    // 检查关键消息是否已渲染
    bool allRendered = false;
    int retryCount = 0;
    const maxRetries = 10;
    
    while (!allRendered && retryCount < maxRetries) {
      allRendered = true;
      
      // 检查前几个和后几个消息是否已渲染
      final checkIndices = <int>[
        0, // 第一条消息
        messageList.length ~/ 4, // 1/4位置
        messageList.length ~/ 2, // 中间位置
        (messageList.length * 3) ~/ 4, // 3/4位置
        messageList.length - 1, // 最后一条消息
      ];
      
      Logger.print('检查消息渲染状态 - 重试次数: $retryCount');
      
      for (final index in checkIndices) {
        if (index < messageList.length) {
          final message = messageList[index];
          final clientMsgID = message.clientMsgID ?? '';
          final height = _getMessageActualHeight(clientMsgID);
          
          Logger.print('检查消息渲染 - 索引: $index, 消息ID: $clientMsgID, 高度: $height');
          
          if (height <= 0) {
            allRendered = false;
            Logger.print('消息未渲染完成: $clientMsgID, 高度: $height');
            break;
          }
        }
      }
      
      if (!allRendered) {
        retryCount++;
        Logger.print('等待消息渲染 - 重试次数: $retryCount');
        await Future.delayed(Duration(milliseconds: 50));
      }
    }
    
    if (allRendered) {
      Logger.print('所有消息项渲染完成');
    } else {
      Logger.print('部分消息项可能未完全渲染，将使用预估高度');
    }
  }

  @override
  void onDetached() {}

  @override
  void onHidden() {}

  @override
  void onInactive() {}

  @override
  void onPaused() {}

  @override
  void onResumed() {
    _loadHistoryForSyncEnd();
  }
}
