import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_new_badger/flutter_new_badger.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart' as im;
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim_common/openim_common.dart';
import 'package:sound_mode/sound_mode.dart';
import 'package:sound_mode/utils/ringer_mode_statuses.dart';
import 'package:vibration/vibration.dart';

import '../../utils/upgrade_manager.dart';
import 'im_controller.dart';

class AppController extends GetxController with UpgradeManger {
  var isRunningBackground = false;

  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  final initializationSettingsAndroid = const AndroidInitializationSettings('@mipmap/ic_launcher');

  final DarwinInitializationSettings initializationSettingsDarwin = const DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
    requestCriticalPermission: true,
    defaultPresentAlert: true,
    defaultPresentBadge: true,
    defaultPresentSound: true,
  );

  RTCBridge? get rtcBridge => PackageBridge.rtcBridge;

  bool get shouldMuted =>
      rtcBridge?.hasConnection == true ||
      Get.find<IMController>().imSdkStatusSubject.values.last.status != IMSdkStatus.syncEnded;

  final _ring = 'assets/audio/message_ring.wav';
  final _audioPlayer = AudioPlayer();
  final configuration = const AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.ambient,
    avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
    androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
    androidAudioAttributes: AndroidAudioAttributes(
      contentType: AndroidAudioContentType.sonification,
      usage: AndroidAudioUsage.notification,
    ),
  );
  late AudioSession session;

  late BaseDeviceInfo deviceInfo;

  final clientConfigMap = <String, dynamic>{}.obs;

  Future<void> runningBackground(bool run) async {
    Logger.print('-----App running background : $run-------------');

    if (isRunningBackground && !run) {}
    isRunningBackground = run;
    if (!run) {
      _cancelAllNotifications();
    }
  }

  @override
  void onInit() async {
    _initPlayer();
    await _configureBackgroundTasks();
    final initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          _handleNotificationClick(response.payload!);
        }
      },
    );

    autoCheckVersionUpgrade();
    super.onInit();
  }

  void _requestPermissions() {
    flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  Future<void> showNotification(im.Message message, {bool showNotification = true}) async {
    if (_isGlobalNotDisturb() ||
        message.attachedInfoElem?.notSenderNotificationPush == true ||
        message.contentType == im.MessageType.typing ||
        message.sendID == OpenIM.iMManager.userID ||
        (message.contentType! >= 1000 && message.contentType != 1400)) return;

    var sourceID = message.sessionType == ConversationType.single ? message.sendID : message.groupID;
    if (sourceID != null && message.sessionType != null) {
      var i = await OpenIM.iMManager.conversationManager.getOneConversation(
        sourceID: sourceID,
        sessionType: message.sessionType!,
      );
      if (i.recvMsgOpt != 0) return;
    }

    if (showNotification) {
      promptSoundOrNotification(message.seq!);
    }
  }

  Future<void> promptSoundOrNotification(int seq) async {
    if (Get.find<IMController>().imSdkStatusSubject.values.lastOrNull?.status != IMSdkStatus.syncEnded) {
      return;
    }
    if (!isRunningBackground) {
      _playMessageSound();
    } else {
      final id = seq;
      
      if (Platform.isAndroid) {
        const androidPlatformChannelSpecifics = AndroidNotificationDetails(
          'chat', 
          'OpenIM聊天消息',
          channelDescription: '来自OpenIM的信息', 
          importance: Importance.max, 
          priority: Priority.high, 
          ticker: 'ticker'
        );
        const NotificationDetails platformChannelSpecifics = NotificationDetails(
          android: androidPlatformChannelSpecifics
        );
        await flutterLocalNotificationsPlugin.show(
          id, 
          '您收到了一条新消息', 
          '消息内容：.....', 
          platformChannelSpecifics,
          payload: ''
        );
      } else if (Platform.isIOS) {
        const iOSPlatformChannelSpecifics = DarwinNotificationDetails(
          presentAlert: true,    // 显示通知
          presentBadge: true,    // 显示角标
          presentSound: true,    // 播放声音
          sound: 'message_ring.wav', // 自定义通知声音
          badgeNumber: 1,        // 角标数量
        );
        const NotificationDetails platformChannelSpecifics = NotificationDetails(
          iOS: iOSPlatformChannelSpecifics
        );
        await flutterLocalNotificationsPlugin.show(
          id, 
          '您收到了一条新消息', 
          '消息内容：.....', 
          platformChannelSpecifics,
          payload: ''
        );
      }
    }
  }

  Future<void> _cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  Future<void> _startForegroundService() async {
    await getAppInfo();
    const androidPlatformChannelSpecifics = AndroidNotificationDetails('pro', 'OpenIM后台进程',
        channelDescription: '保证app能收到信息', importance: Importance.max, priority: Priority.high, ticker: 'ticker');

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.startForegroundService(1, packageInfo!.appName, '正在运行...',
            notificationDetails: androidPlatformChannelSpecifics, payload: '');
  }

  Future<void> _stopForegroundService() async {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.stopForegroundService();
  }

  void showBadge(count) {
    OpenIM.iMManager.messageManager.setAppBadge(count);

    if (count == 0) {
      removeBadge();
      PushController.resetBadge();
    } else {
      FlutterNewBadger.setBadge(count);
      PushController.setBadge(count);
    }
  }

  void removeBadge() {
    FlutterNewBadger.removeBadge();
  }

  @override
  void onClose() {
    closeSubject();
    _audioPlayer.dispose();
    super.onClose();
  }

  Locale? getLocale() {
    var local = Get.locale;
    var index = DataSp.getLanguage() ?? 0;
    switch (index) {
      case 1:
        local = const Locale('zh', 'CN');
        break;
      case 2:
        local = const Locale('en', 'US');
        break;
    }
    return local;
  }

  @override
  void onReady() {
    queryClientConfig();
    _getDeviceInfo();
    _cancelAllNotifications();
    super.onReady();
  }

  bool _isGlobalNotDisturb() {
    bool isRegistered = Get.isRegistered<IMController>();
    if (isRegistered) {
      var logic = Get.find<IMController>();
      return logic.userInfo.value.globalRecvMsgOpt == 2;
    }
    return false;
  }

  void _initPlayer() async {
    session = await AudioSession.instance;
    await session.configure(configuration);

    _audioPlayer.setAsset(_ring, package: 'openim_common');
    _audioPlayer.playerStateStream.listen((state) {
      switch (state.processingState) {
        case ProcessingState.idle:
        case ProcessingState.loading:
        case ProcessingState.buffering:
        case ProcessingState.ready:
          break;
        case ProcessingState.completed:
          _stopMessageSound();

          break;
      }
    });
  }

  void _playMessageSound() async {
    if (shouldMuted) {
      return;
    }
    bool isRegistered = Get.isRegistered<IMController>();
    bool isAllowVibration = true;
    bool isAllowBeep = true;
    if (isRegistered) {
      var logic = Get.find<IMController>();
      isAllowVibration = logic.userInfo.value.allowVibration == 1;
      isAllowBeep = logic.userInfo.value.allowBeep == 1;
    }

    RingerModeStatus ringerStatus = await SoundMode.ringerModeStatus;

    Logger.print('System ringer status: $ringerStatus, user is allow beep: $isAllowBeep',
        fileName: 'app_controller.dart');

    if (!_audioPlayer.playerState.playing &&
        isAllowBeep &&
        (ringerStatus == RingerModeStatus.normal || ringerStatus == RingerModeStatus.unknown)) {
      await session.setActive(true);
      _audioPlayer.setAsset(_ring, package: 'openim_common');
      _audioPlayer.setLoopMode(LoopMode.off);
      _audioPlayer.setVolume(1.0);
      _audioPlayer.play();
    }

    if (isAllowVibration &&
        (ringerStatus == RingerModeStatus.normal ||
            ringerStatus == RingerModeStatus.vibrate ||
            ringerStatus == RingerModeStatus.unknown)) {
      if (await Vibration.hasVibrator() == true) {
        Vibration.vibrate();
      }
    }
  }

  void _stopMessageSound() async {
    if (_audioPlayer.playerState.playing) {
      _audioPlayer.stop();
    }
    await session.setActive(false);
  }

  void _getDeviceInfo() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    deviceInfo = await deviceInfoPlugin.deviceInfo;
  }

  Future queryClientConfig() async {
    final map = await Apis.getClientConfig();
    clientConfigMap.assignAll(map);

    return clientConfigMap;
  }

  Future<void> _configureBackgroundTasks() async {
    if (Platform.isIOS) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
            critical: true,
          );
    }
  }

  void _handleNotificationClick(String payload) {
    // 根据 payload 处理不同的通知点击事件
    // 例如：跳转到特定聊天页面
  }

  Future<void> _checkNotificationPermission() async {
    if (Platform.isIOS) {
      final settings = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
            critical: true,
          );
    }
  }

  void _debugNotificationSettings() async {
    if (Platform.isIOS) {
      final settings = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.getNotificationAppLaunchDetails();
      print('Notification settings: $settings');
    }
  }
}
