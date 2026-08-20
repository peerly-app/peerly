import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../design/colors.dart';
import '../services/avatar_store.dart';

class Avatar extends StatelessWidget {
  final String id;
  final String name;
  final double diameter;

  const Avatar({
    super.key,
    required this.id,
    required this.name,
    this.diameter = 48,
  });

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final photo = context.watch<AvatarStore>().photoBytes(id);
    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.avatarColorFor(id),
        shape: BoxShape.circle,
        image: photo != null
            ? DecorationImage(image: MemoryImage(photo), fit: BoxFit.cover)
            : null,
      ),
      child: photo != null
          ? null
          : Text(
              _initials,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                fontSize: diameter * 0.34,
                color: AppColors.onAccent,
              ),
            ),
    );
  }
}
