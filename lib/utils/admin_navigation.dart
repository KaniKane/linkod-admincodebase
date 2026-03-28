import 'package:flutter/material.dart';

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

  Navigator.pushReplacement(
    context,
    buildAdminNoFadeRoute(page: page, routeName: targetRoute),
  );
}
