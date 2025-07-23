import 'package:get/get.dart';

import 'message_search_logic.dart';

class MessageSearchResultsBinding extends Bindings {
  @override
  void dependencies() {
    // 确保使用已存在的MessageSearchLogic实例
    // 不创建新的实例，避免状态丢失
  }
} 