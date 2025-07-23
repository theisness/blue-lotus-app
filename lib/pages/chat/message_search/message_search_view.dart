import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:common_utils/common_utils.dart';

import 'message_search_logic.dart';

class MessageSearchPage extends StatelessWidget {
  final logic = Get.find<MessageSearchLogic>();

  MessageSearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TitleBar.back(title: '消息查询'),
      backgroundColor: Styles.c_F8F9FA,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildSearchHeader(),
            _buildFilterSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Container(
      padding: EdgeInsets.all(16.w),
      color: Styles.c_FFFFFF,
      child: Column(
        children: [
          // 搜索输入框
          Container(
            decoration: BoxDecoration(
              color: Styles.c_F8F9FA,
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: TextField(
              controller: logic.searchController,
              focusNode: logic.focusNode,
              decoration: InputDecoration(
                hintText: '输入关键词搜索消息内容',
                hintStyle: Styles.ts_8E9AB0_14sp,
                prefixIcon: Icon(Icons.search, color: Styles.c_8E9AB0),
                suffixIcon: logic.searchText.value.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: Styles.c_8E9AB0),
                        onPressed: () => logic.searchController.clear(),
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              ),
              onSubmitted: (_) => logic.performSearch(),
            ),
          ),
          12.verticalSpace,
          // 搜索按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: logic.isSearching.value ? null : logic.performSearch,
              style: ElevatedButton.styleFrom(
                backgroundColor: Styles.c_0089FF,
                foregroundColor: Styles.c_FFFFFF,
                padding: EdgeInsets.symmetric(vertical: 12.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.r),
                ),
              ),
              child: logic.isSearching.value
                  ? SizedBox(
                      width: 20.w,
                      height: 20.h,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Styles.c_FFFFFF),
                      ),
                    )
                  : Text('搜索', style: Styles.ts_FFFFFF_16sp),
            ),
          ),
          8.verticalSpace,
          // 提示信息
          Text(
            '搜索完成后将跳转到结果页面',
            style: Styles.ts_8E9AB0_12sp,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    return Obx(() => Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 筛选条件标题
          Row(
            children: [
              Text('筛选条件', style: Styles.ts_0C1C33_17sp_semibold),
              const Spacer(),
              GestureDetector(
                onTap: logic.clearSearchConditions,
                child: Text('清除', style: Styles.ts_0089FF_14sp),
              ),
            ],
          ),
          12.verticalSpace,
          // 日期范围选择
          _buildFilterItem(
            title: '时间范围',
            value: logic.selectedDateRange.value != null
                ? '${DateUtil.formatDate(logic.selectedDateRange.value!.start, format: 'yyyy-MM-dd')} 至 ${DateUtil.formatDate(logic.selectedDateRange.value!.end, format: 'yyyy-MM-dd')}'
                : '选择时间范围',
            onTap: logic.selectDateRange,
            isSelected: logic.selectedDateRange.value != null,
          ),
          8.verticalSpace,
          // 发言人选择
          _buildFilterItem(
            title: '发言人',
            value: logic.selectedSenderID.value.isNotEmpty
                ? logic.getSelectedSenderName()
                : '选择发言人',
            onTap: logic.showSenderSelectionDialog,
            isSelected: logic.selectedSenderID.value.isNotEmpty,
          ),
          8.verticalSpace,
          // 消息类型选择
          _buildMessageTypeFilter(),
          8.verticalSpace,
          // 已选择的条件显示
          if (logic.selectedDateRange.value != null || 
              logic.selectedSenderID.value.isNotEmpty || 
              logic.selectedMessageTypes.isNotEmpty)
            _buildSelectedConditions(),
        ],
      ),
    ));
  }

  Widget _buildFilterItem({
    required String title,
    required String value,
    required VoidCallback onTap,
    bool isSelected = false,
  }) {
    final isDefaultValue = value == '选择时间范围' || value == '选择发言人';
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isSelected ? Styles.c_0089FF.withOpacity(0.1) : Styles.c_FFFFFF,
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(
            color: isSelected ? Styles.c_0089FF : Styles.c_E8EAEF,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(title, style: Styles.ts_0C1C33_14sp),
            8.horizontalSpace,
            Expanded(
              child: Text(
                value,
                style: isDefaultValue 
                    ? Styles.ts_8E9AB0_14sp 
                    : Styles.ts_0C1C33_14sp,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            4.horizontalSpace,
            Icon(
              isSelected ? Icons.check_circle : Icons.arrow_forward_ios, 
              size: 12.w, 
              color: isSelected ? Styles.c_0089FF : Styles.c_8E9AB0
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedConditions() {
    return Obx(() {
      final selectedConditions = <Widget>[];

      // 时间范围
      if (logic.selectedDateRange.value != null) {
        selectedConditions.add(
          _buildConditionChip(
            '时间: ${DateUtil.formatDate(logic.selectedDateRange.value!.start,
                format: 'MM-dd')} 至 ${DateUtil.formatDate(
                logic.selectedDateRange.value!.end, format: 'MM-dd')}',
                () => logic.selectedDateRange.value = null,
          ),
        );
      }

      // 发言人
      if (logic.selectedSenderID.value.isNotEmpty) {
        selectedConditions.add(
          _buildConditionChip(
            '发言人: ${logic.getSelectedSenderName()}',
            logic.clearSenderSelection,
          ),
        );
      }

      // 消息类型
      for (final type in logic.selectedMessageTypes) {
        final typeName = logic.getMessageTypeName(type);
        selectedConditions.add(
          _buildConditionChip(
            typeName,
                () => logic.toggleMessageType(type),
          ),
        );
      }


      return Container(
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: Styles.c_0089FF.withOpacity(0.05),
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(color: Styles.c_0089FF.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.filter_list, size: 16.w, color: Styles.c_0089FF),
                4.horizontalSpace,
                Text('已选择的条件', style: Styles.ts_0089FF_12sp),
              ],
            ),
            8.verticalSpace,
            Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: selectedConditions,
            ),
          ],
        ),
      );
    }
    );
  }
  
  Widget _buildConditionChip(String label, VoidCallback onRemove) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: Styles.c_0089FF,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Styles.ts_FFFFFF_12sp,
          ),
          4.horizontalSpace,
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Icons.close,
              size: 14.w,
              color: Styles.c_FFFFFF,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageTypeFilter() {
    return Obx(() => Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Styles.c_FFFFFF,
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: Styles.c_E8EAEF),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('消息类型', style: Styles.ts_0C1C33_14sp),
          8.verticalSpace,
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: logic.messageTypeOptions.map((option) {
              final type = option['type'] as int;
              final name = option['name'] as String;
              final isSelected = logic.selectedMessageTypes.contains(type);
              
              return GestureDetector(
                onTap: () => logic.toggleMessageType(type),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: isSelected ? Styles.c_0089FF : Styles.c_F8F9FA,
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(
                      color: isSelected ? Styles.c_0089FF : Styles.c_E8EAEF,
                    ),
                  ),
                  child: Text(
                    name,
                    style: TextStyle(
                      color: isSelected ? Styles.c_FFFFFF : Styles.c_0C1C33,
                      fontSize: 12.sp,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    ));
  }


} 