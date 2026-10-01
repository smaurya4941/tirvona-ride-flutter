import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/app_user.dart';
import '../../application/account_controller.dart';

/// The user's photo, or their initials while there is none (or while it
/// loads, or if it cannot be fetched).
class ProfileAvatar extends ConsumerWidget {
  const ProfileAvatar({super.key, required this.user, this.radius = 40});

  final AppUser user;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = user.profileImage;
    final photo = path == null ? null : ref.watch(profileImageProvider(path));
    final bytes = photo?.value;
    return Semantics(
      image: true,
      label: bytes == null
          ? '${user.displayName}, no profile photo'
          : '${user.displayName}, profile photo',
      child: CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.bhagwaLight,
        foregroundImage: bytes == null ? null : MemoryImage(bytes),
        child: Text(
          user.initials,
          style: TextStyle(
            fontSize: radius * 0.7,
            fontWeight: FontWeight.w700,
            color: AppColors.bhagwaDark,
          ),
        ),
      ),
    );
  }
}
