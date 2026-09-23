import 'package:flutter/material.dart';
import 'package:suvi_core/suvi_core.dart';

import '../theme/app_theme.dart';
import '../util/format.dart';

/// Colored circle with the device-type glyph, used everywhere a device appears.
class DeviceAvatar extends StatelessWidget {
  const DeviceAvatar({
    super.key,
    required this.colorIndex,
    required this.deviceType,
    this.size = 44,
    this.badge,
  });

  final int colorIndex;
  final DeviceType deviceType;
  final double size;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final color = SuviColors.avatar(colorIndex);
    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.18)!],
        ),
      ),
      child: Icon(
        iconForDevice(deviceType),
        color: Colors.white,
        size: size * 0.5,
      ),
    );
    if (badge == null) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(right: -2, bottom: -2, child: badge!),
      ],
    );
  }
}
