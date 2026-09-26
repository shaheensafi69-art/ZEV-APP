import 'package:flutter/material.dart';

/// Responsive layout utilities ensuring the ZEV UI looks flawless
/// on iPhones, Android phones, iPad/tablets, macOS, Windows, and Web.
class ResponsiveLayout {
  // Breakpoints
  static const double phoneMaxWidth = 768.0;
  static const double tabletMaxWidth = 1150.0;

  // Max content widths
  static const double maxFeedWidth = 640.0;
  static const double maxContentWidth = 880.0;
  static const double maxStoreWidth = 1200.0;
  static const double maxTabletWidth = 1024.0;

  static bool isPhone(BuildContext context) =>
      MediaQuery.of(context).size.width < phoneMaxWidth;

  static bool isMobile(BuildContext context) => isPhone(context);

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= phoneMaxWidth && width < tabletMaxWidth;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletMaxWidth;

  static bool isWebOrDesktop(BuildContext context) => isDesktop(context);

  /// Returns responsive value based on device: phone, tablet (iPad), or desktop (macOS/Windows/Web)
  static T value<T>(
    BuildContext context, {
    required T phone,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop(context)) return desktop ?? tablet ?? phone;
    if (isTablet(context)) return tablet ?? phone;
    return phone;
  }

  /// Returns responsive font size proportionally scaled per platform
  static double fontSize(
    BuildContext context, {
    required double phone,
    double? tablet,
    double? desktop,
  }) =>
      value<double>(
        context,
        phone: phone,
        tablet: tablet ?? (phone * 1.15),
        desktop: desktop ?? (phone * 1.25),
      );

  /// Returns responsive icon size proportionally scaled per platform
  static double iconSize(
    BuildContext context, {
    required double phone,
    double? tablet,
    double? desktop,
  }) =>
      value<double>(
        context,
        phone: phone,
        tablet: tablet ?? (phone * 1.2),
        desktop: desktop ?? (phone * 1.15),
      );

  /// Returns responsive spacing / padding
  static double spacing(
    BuildContext context, {
    required double phone,
    double? tablet,
    double? desktop,
  }) =>
      value<double>(
        context,
        phone: phone,
        tablet: tablet ?? (phone * 1.25),
        desktop: desktop ?? (phone * 1.35),
      );

  /// Dynamically determines column count for grid views based on device width
  static int gridColumns(
    BuildContext context, {
    int mobile = 2,
    int tablet = 3,
    int desktop = 4,
  }) {
    final width = MediaQuery.of(context).size.width;
    if (width < phoneMaxWidth) return mobile;
    if (width < tabletMaxWidth) return tablet;
    return desktop;
  }

  /// Wraps children in a centered box with max width constraint
  /// to prevent awkward stretching on iPad, macOS, Windows, and Web.
  /// On phones, returns full width without boxing or artificial margins.
  static Widget feedConstraint({
    required Widget child,
    double maxWidth = maxFeedWidth,
    Color? backgroundColor,
  }) {
    return Builder(
      builder: (context) {
        if (isPhone(context)) {
          return Container(
            width: double.infinity,
            color: backgroundColor,
            child: child,
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              color: backgroundColor,
              child: child,
            ),
          ),
        );
      },
    );
  }

  /// Full-page responsive container with max width constraint
  /// On phones, returns full width directly.
  static Widget pageConstraint({
    required Widget child,
    double maxWidth = maxStoreWidth,
    Color? backgroundColor,
  }) {
    return Builder(
      builder: (context) {
        if (isPhone(context)) {
          return Container(
            width: double.infinity,
            color: backgroundColor,
            child: child,
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              color: backgroundColor,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// A drop-in widget for page bodies that automatically adapts to iPad, Desktop, and Mobile.
class ResponsivePageContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final Color? backgroundColor;

  const ResponsivePageContainer({
    super.key,
    required this.child,
    this.maxWidth = ResponsiveLayout.maxFeedWidth,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    if (ResponsiveLayout.isPhone(context)) {
      return Container(
        width: double.infinity,
        color: backgroundColor,
        child: child,
      );
    }

    final width = MediaQuery.of(context).size.width;
    if (width <= maxWidth) {
      return Container(
        color: backgroundColor,
        child: child,
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 24,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Convenience extensions on BuildContext for fluid responsive values
extension ResponsiveContextExtension on BuildContext {
  bool get isPhone => ResponsiveLayout.isPhone(this);
  bool get isTablet => ResponsiveLayout.isTablet(this);
  bool get isDesktop => ResponsiveLayout.isDesktop(this);

  T responsive<T>({
    required T phone,
    T? tablet,
    T? desktop,
  }) =>
      ResponsiveLayout.value<T>(
        this,
        phone: phone,
        tablet: tablet,
        desktop: desktop,
      );

  double respFont({
    required double phone,
    double? tablet,
    double? desktop,
  }) =>
      ResponsiveLayout.fontSize(
        this,
        phone: phone,
        tablet: tablet,
        desktop: desktop,
      );

  double respIcon({
    required double phone,
    double? tablet,
    double? desktop,
  }) =>
      ResponsiveLayout.iconSize(
        this,
        phone: phone,
        tablet: tablet,
        desktop: desktop,
      );

  double respSpacing({
    required double phone,
    double? tablet,
    double? desktop,
  }) =>
      ResponsiveLayout.spacing(
        this,
        phone: phone,
        tablet: tablet,
        desktop: desktop,
      );
}
