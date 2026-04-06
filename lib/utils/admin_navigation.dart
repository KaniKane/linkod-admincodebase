import 'package:flutter/material.dart';

typedef AdminShellRouteSelector = void Function(
  String targetRoute, {
  Widget? page,
});

class AdminNavigationScope extends InheritedWidget {
  const AdminNavigationScope({
    super.key,
    required this.currentRoute,
    required this.selectRoute,
    required super.child,
  });

  final String currentRoute;
  final AdminShellRouteSelector selectRoute;

  static AdminNavigationScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AdminNavigationScope>();
  }

  @override
  bool updateShouldNotify(AdminNavigationScope oldWidget) {
    return currentRoute != oldWidget.currentRoute;
  }
}

class AdminRefreshBus {
  AdminRefreshBus._();

  static final ValueNotifier<int> userManagementRefreshTick =
      ValueNotifier<int>(0);
  static final ValueNotifier<int?> pendingUsersCount =
      ValueNotifier<int?>(null);

  static void requestUserManagementRefresh() {
    userManagementRefreshTick.value = userManagementRefreshTick.value + 1;
  }

  static void publishPendingUsersCount(int count) {
    pendingUsersCount.value = count;
  }
}

Route<T> buildAdminNoFadeRoute<T>({
  required Widget page,
  String? routeName,
}) {
  return PageRouteBuilder<T>(
    settings: routeName != null ? RouteSettings(name: routeName) : null,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return child;
    },
  );
}

void navigateToAdminScreen(
  BuildContext context, {
  required String currentRoute,
  required String targetRoute,
  required Widget page,
}) {
  if (currentRoute == targetRoute) {
    return;
  }

  final navigationScope = AdminNavigationScope.maybeOf(context);
  if (navigationScope != null) {
    navigationScope.selectRoute(targetRoute, page: page);
    return;
  }

  Navigator.pushReplacement(
    context,
    buildAdminNoFadeRoute(page: page, routeName: targetRoute),
  );
}
