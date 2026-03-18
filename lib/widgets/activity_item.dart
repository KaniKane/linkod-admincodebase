import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class ActivityItem extends StatelessWidget {
  final String description;
  final String timestamp;
  final String? boldText;

  const ActivityItem({
    super.key,
    required this.description,
    required this.timestamp,
    this.boldText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.inputBackground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildDescription()),
          const SizedBox(width: 16),
          Text(
            timestamp,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.normal,
              color: AppColors.mediumGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription() {
    final text = description.trim();

    // Fallback: bold full actor name up to the action verb.
    final parts = text.split(RegExp(r'\s+'));
    final actionVerbs = {
      'approved',
      'posted',
      'decline',
      'declined',
      'edited',
      'submitted',
      'created',
      'updated',
      'deleted',
      'rejected',
      'suspended',
      'accepted',
      'archived',
    };

    int actionIndex = -1;
    for (int i = 0; i < parts.length; i++) {
      if (actionVerbs.contains(parts[i].toLowerCase())) {
        actionIndex = i;
        break;
      }
    }

    final String name;
    final String rest;
    if (parts.isEmpty) {
      name = '';
      rest = '';
    } else if (actionIndex > 0) {
      name = parts.sublist(0, actionIndex).join(' ');
      rest = parts.sublist(actionIndex).join(' ');
    } else {
      name = parts.first;
      rest = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }

    final trailingText = rest.isNotEmpty ? ' $rest' : '';
    final children = <TextSpan>[
      TextSpan(
        text: name,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ];

    final token = boldText?.trim() ?? '';
    if (token.isNotEmpty) {
      final tokenIndex = trailingText.indexOf(token);
      if (tokenIndex >= 0) {
        final beforeToken = trailingText.substring(0, tokenIndex);
        final afterToken = trailingText.substring(tokenIndex + token.length);
        children.add(TextSpan(text: beforeToken));
        children.add(
          TextSpan(
            text: token,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
        children.add(TextSpan(text: afterToken));
      } else {
        children.add(TextSpan(text: trailingText));
      }
    } else {
      children.add(TextSpan(text: trailingText));
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: AppColors.darkGrey,
        ),
        children: children,
      ),
    );
  }
}
