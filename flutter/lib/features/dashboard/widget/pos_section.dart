import 'package:client/shared/widgets/section_card.dart';
import 'package:flutter/material.dart';

class PosSection extends StatelessWidget {
  const PosSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SectionCard(title: title, child: child);
  }
}
