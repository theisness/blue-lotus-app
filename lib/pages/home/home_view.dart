import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../contacts/contacts_view.dart';
import '../conversation/conversation_view.dart';
import '../mine/mine_view.dart';
import '../discover/discover_view.dart';
import 'home_logic.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';

class HomePage extends StatelessWidget {
  final logic = Get.find<HomeLogic>();
  HomePage({super.key});

  List<PersistentTabConfig> _tabs() => [
        PersistentTabConfig(
          screen: ConversationPage(),
          item: ItemConfig(
            icon: GestureDetector(
              onDoubleTap: () {
                logic.scrollToUnreadMessage();
              },
              child: _setupIcon(ImageRes.homeTab1Sel.toImage, logic.unreadMsgCount.value),
            ),
            inactiveIcon: _setupIcon(ImageRes.homeTab1Nor.toImage, logic.unreadMsgCount.value),
            title: StrRes.home,
            textStyle: Styles.ts_0089FF_10sp_semibold,
          ),
        ),
        PersistentTabConfig(
          screen: ContactsPage(),
          item: ItemConfig(
            icon: _setupIcon(ImageRes.homeTab2Sel.toImage, logic.unhandledCount.value),
            inactiveIcon: _setupIcon(ImageRes.homeTab2Nor.toImage, logic.unhandledCount.value),
            title: StrRes.contacts,
            textStyle: Styles.ts_0089FF_10sp_semibold,
          ),
        ),
        // 影院页
        PersistentTabConfig(
          screen: DiscoverPage(
              url: 'https://ssbx.site'
          ),
          item: ItemConfig(
            icon: ImageRes.tabMovieSel.toImage,
            inactiveIcon: ImageRes.tabMovieNor.toImage,
            title: StrRes.movie,
            textStyle: Styles.ts_0089FF_10sp_semibold,
          ),
        ),
        // 社区页
        PersistentTabConfig(
          screen: DiscoverPage(
            url:'https://blog.ssbx.site'
          ),
          item: ItemConfig(
            icon: ImageRes.tabDiscourseSel.toImage,
            inactiveIcon: ImageRes.tabDiscourseNor.toImage,
            title: StrRes.discourse,
            textStyle: Styles.ts_0089FF_10sp_semibold,
          ),
        ),
        PersistentTabConfig(
          screen: MinePage(),
          item: ItemConfig(
            icon: ImageRes.homeTab4Sel.toImage,
            inactiveIcon: ImageRes.homeTab4Nor.toImage,
            title: StrRes.mine,
            textStyle: Styles.ts_0089FF_10sp_semibold,
          ),
        ),
      ];

  Widget _setupIcon(Widget icon, int unReadCount) {
    return Stack(
      alignment: Alignment.center,
      children: [
        icon,
        Positioned(
          top: 0,
          right: 0,
          child: Transform.translate(
            offset: const Offset(2, -2),
            child: UnreadCountView(count: unReadCount),
          ),
        ),
      ],
    );
  }

  // final PersistentTabController _controller = PersistentTabController(initialIndex: 0);
  //
  // @override
  // Widget build(BuildContext context) {
  //   return PopScope(
  //     canPop: false, // 禁止直接 pop
  //     onPopInvokedWithResult: (bool didPop, result) async {
  //       if(didPop) return;
  //       if (_controller.index != 0) {
  //         _controller.jumpToTab(0); // 切换到首页 tab
  //       } else {
  //         // 如果已经在首页 tab，允许 pop
  //         Navigator.of(context).pop();
  //       }
  //     },
  //     child: Scaffold(
  //       backgroundColor: Styles.c_FFFFFF,
  //       body: Obx(
  //             () => PersistentTabView(
  //           controller: _controller,
  //           tabs: _tabs(),
  //           navBarBuilder: (navBarConfig) => Style6BottomNavBar(
  //             navBarConfig: navBarConfig,
  //             navBarDecoration: const NavBarDecoration(
  //               color: Colors.white,
  //               boxShadow: [
  //                 BoxShadow(color: Colors.black12, blurRadius: 0.5, spreadRadius: 0.5),
  //               ],
  //             ),
  //           ),
  //           navBarOverlap: const NavBarOverlap.none(),
  //           screenTransitionAnimation: const ScreenTransitionAnimation.none(),
  //         ),
  //       ),
  //     ),
  //   );
  // }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Styles.c_FFFFFF,
      body: Obx(
        () => PersistentTabView(
          tabs: _tabs(),
          navBarBuilder: (navBarConfig) => Style2BottomNavBar(
            navBarConfig: navBarConfig,
            navBarDecoration: const NavBarDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black12, blurRadius: 0.5, spreadRadius: 0.5),
              ],
            ),
          ),
          navBarOverlap: const NavBarOverlap.none(),
          screenTransitionAnimation: const ScreenTransitionAnimation.none(),
        ),
      ),
    );
  }
}
