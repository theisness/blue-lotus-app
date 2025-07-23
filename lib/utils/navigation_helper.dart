import 'package:get/get.dart';

/// 不重复栈导航工具类
/// 用于避免页面栈中出现重复页面
class NavigationHelper {
  /// 不重复栈导航到指定页面
  /// [routeName] 目标路由名称
  /// [arguments] 传递的参数
  /// [predicate] 判断是否为目标页面的条件函数
  static void navigateWithoutDuplicates({
    required String routeName,
    dynamic arguments,
    bool Function(GetPageRoute route)? predicate,
  }) {
    // 检查当前路由是否为目标页面
    final currentRoute = Get.currentRoute;
    
    if (currentRoute == routeName) {
      // 如果当前已经是目标页面，则替换参数
      Get.offNamed(
        routeName,
        arguments: arguments,
      );
    } else {
      // 否则使用preventDuplicates参数来防止重复页面
      Get.toNamed(
        routeName,
        arguments: arguments,
        preventDuplicates: true,
      );
    }
  }
  
  /// 不重复栈导航到聊天页面
  static void navigateToChatWithoutDuplicates({
    required dynamic conversationInfo,
    dynamic searchMessage,
  }) {
    final arguments = {
      'conversationInfo': conversationInfo,
      'searchMessage': searchMessage,
    };
    
    navigateWithoutDuplicates(
      routeName: 'AppRoutes.chat', // 这里需要根据实际情况调整
      arguments: arguments,
    );
  }
} 