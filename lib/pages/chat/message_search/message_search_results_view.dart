import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'message_search_logic.dart';

class MessageSearchResultsPage extends StatelessWidget {
  final logic = Get.find<MessageSearchLogic>();

  MessageSearchResultsPage({super.key});
  
  // 注意：此页面不会自动加载更多结果
  // 只有在用户点击"加载更多"按钮时才会加载

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 确保返回到正确的页面
        Get.back();
        return false;
      },
      child: Scaffold(
        appBar: TitleBar.back(title: '搜索结果'),
        backgroundColor: Styles.c_F8F9FA,
        body: Column(
          children: [
            _buildSearchStats(),
            Expanded(child: _buildSearchResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchStats() {
    return Obx(() => Container(
      padding: EdgeInsets.all(16.w),
      color: Styles.c_FFFFFF,
      child: Row(
        children: [
          Icon(Icons.search, size: 16.w, color: Styles.c_0089FF),
          8.horizontalSpace,
          Text(
            '共显示 ${logic.searchResults.length} 条消息',
            style: Styles.ts_0C1C33_14sp,
          ),
          const Spacer(),
          if (logic.hasMoreResults.value)
            Text(
              '已加载${logic.currentPage}页，还有更多',
              style: Styles.ts_0089FF_12sp,
            )
          else if (logic.searchResults.isNotEmpty)
            Text(
              '第${logic.currentPage}页，已加载全部',
              style: Styles.ts_8E9AB0_12sp,
            ),
        ],
      ),
    ));
  }

  Widget _buildSearchResults() {
    return Obx(() {
      if (logic.searchResults.isEmpty && !logic.isSearching.value) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 64.w, color: Styles.c_8E9AB0),
              16.verticalSpace,
              Text('暂无搜索结果', style: Styles.ts_8E9AB0_16sp),
              8.verticalSpace,
              Text('请尝试调整搜索条件', style: Styles.ts_8E9AB0_14sp),
            ],
          ),
        );
      }

      return ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        itemCount: logic.searchResults.length + (logic.hasMoreResults.value ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == logic.searchResults.length) {
            // 加载更多按钮
            return Container(
              padding: EdgeInsets.symmetric(vertical: 16.h),
              child: Center(
                child: logic.isSearching.value
                    ? Column(
                        children: [
                          SizedBox(
                            width: 24.w,
                            height: 24.h,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Styles.c_0089FF),
                            ),
                          ),
                          8.verticalSpace,
                          Text('正在加载更多...', style: Styles.ts_8E9AB0_12sp),
                        ],
                      )
                    : ElevatedButton(
                        onPressed: () {
                          // 确保只有在点击按钮时才加载更多
                          if (!logic.isSearching.value && logic.hasMoreResults.value) {
                            logic.loadMoreResults();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Styles.c_0089FF,
                          foregroundColor: Styles.c_FFFFFF,
                          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                        ),
                        child: Text('加载更多', style: Styles.ts_FFFFFF_14sp),
                      ),
              ),
            );
          }

          final message = logic.searchResults[index];
          return _buildMessageItem(message);
        },
      );
    });
  }

  Widget _buildMessageItem(Message message) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Styles.c_FFFFFF,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 消息头部信息
          Row(
            children: [
              AvatarView(
                width: 40.w,
                height: 40.h,
                url: message.senderFaceUrl,
                text: message.senderNickname,
                textStyle: Styles.ts_FFFFFF_14sp,
              ),
              12.horizontalSpace,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.senderNickname ?? '未知用户',
                      style: Styles.ts_0C1C33_17sp_semibold,
                    ),
                    Text(
                      logic.formatTime(message.sendTime as int),
                      style: Styles.ts_8E9AB0_12sp,
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: Styles.c_0089FF.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  logic.getMessageTypeName(message.contentType ?? MessageType.text),
                  style: Styles.ts_0089FF_12sp,
                ),
              ),
            ],
          ),
          12.verticalSpace,
          // 消息内容
          GestureDetector(
            onTap: () => logic.jumpToMessage(message),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Styles.c_F8F9FA,
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: Styles.c_E8EAEF),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.message, size: 16.w, color: Styles.c_8E9AB0),
                      8.horizontalSpace,
                      Text('点击查看完整消息', style: Styles.ts_8E9AB0_12sp),
                    ],
                  ),
                  8.verticalSpace,
                  Text(
                    logic.getMessagePreview(message),
                    style: Styles.ts_0C1C33_14sp,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
} 