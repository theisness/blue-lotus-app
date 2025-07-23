import 'package:get/get.dart';

import 'message_search_logic.dart';

class MessageSearchBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => MessageSearchLogic());
  }
} 