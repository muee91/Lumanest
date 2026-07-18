import 'package:flutter/animation.dart';

abstract final class LumaNestMotion {
  static const pressIn = Duration(milliseconds: 80);
  static const pressOut = Duration(milliseconds: 190);
  static const iconFeedback = Duration(milliseconds: 160);
  static const tabTransition = Duration(milliseconds: 200);
  static const contentExit = Duration(milliseconds: 160);
  static const contentEnter = Duration(milliseconds: 280);
  static const numberTransition = Duration(milliseconds: 220);
  static const bottomSheet = Duration(milliseconds: 360);
  static const containerTransform = Duration(milliseconds: 420);
  static const environmentChange = Duration(milliseconds: 1600);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve emphasized = Cubic(0.20, 0.80, 0.20, 1.00);
}
