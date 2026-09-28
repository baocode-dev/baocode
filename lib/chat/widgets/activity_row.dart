import 'package:flutter/material.dart';

import 'shimmer_text.dart';

/// What the agent is busy with out of sight: "Planning next move".
class ActivityRow extends StatelessWidget {
  const ActivityRow({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      // Lined up with the steps around it.
      child: ShimmerText(
        label,
        ellipsis: false,
        padding: const EdgeInsets.symmetric(vertical: 3),
      ),
    );
  }
}
