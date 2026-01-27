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
          Expanded(
            child: _buildDescription(),
          ),
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
    // Extract name (first 1-2 words before action verb)
    final parts = description.split(' ');
    String name = '';
    String rest = description;
    
    if (parts.length >= 2) {
      // Common action verbs
      final actionVerbs = ['approved', 'posted', 'decline', 'declined', 'edited'];
      int nameEndIndex = 1;
      
      for (int i = 1; i < parts.length && i <= 2; i++) {
        if (actionVerbs.contains(parts[i].toLowerCase())) {
          nameEndIndex = i;
          break;
        }
      }
      
      name = parts.sublist(0, nameEndIndex).join(' ');
      rest = parts.sublist(nameEndIndex).join(' ');
    } else if (parts.isNotEmpty) {
      name = parts[0];
      rest = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }

    // Handle bold text if specified (for announcement titles)
    if (boldText != null && description.contains(boldText!)) {
      final nameIndex = description.indexOf(name);
      final boldIndex = description.indexOf(boldText!);
      final beforeBold = description.substring(nameIndex + name.length, boldIndex);
      final afterBold = description.substring(boldIndex + boldText!.length);
      
      return RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: AppColors.darkGrey,
          ),
          children: [
            TextSpan(
              text: name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: beforeBold),
            TextSpan(
              text: boldText,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: afterBold),
          ],
        ),
      );
    }

    // Default: bold name, normal rest
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: AppColors.darkGrey,
        ),
        children: [
          TextSpan(
            text: name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: ' $rest'),
        ],
      ),
    );
  }
}
