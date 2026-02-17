import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import 'custom_button.dart';
import 'outline_button.dart';

/// Preset reasons for decline/suspension (governance audit trail).
const List<String> kDeclineReasonPresets = [
  'Invalid proof of residence',
  'Invalid ID',
  'Duplicate account',
  'Does not live at address',
  'Expired document',
  'Incomplete information',
  'Other',
];

/// Presets that require only proof resubmit (not full credentials). Rest = full re-apply.
const List<String> kProofOnlyPresets = [
  'Invalid proof of residence',
  'Invalid ID',
  'Expired document',
];

/// Result of the decline/status dialog.
class DeclineReasonResult {
  const DeclineReasonResult({
    required this.reason,
    this.status,
    this.reapplyType,
  });
  /// Final text to store in adminNote (preset + custom).
  final String reason;
  /// For "Change status" flow: 'declined' | 'suspended'.
  final String? status;
  /// For mobile re-apply: 'proof_only' (resubmit image only) or 'full' (fill credentials again).
  final String? reapplyType;
}

/// Dialog to capture reason for decline or account status change.
/// Use for: (1) Declining a pending registration, (2) Changing status of an existing user (Declined/Suspended).
class DeclineReasonDialog extends StatefulWidget {
  const DeclineReasonDialog({
    super.key,
    this.title = 'Reason for decline',
    this.submitLabel = 'Submit',
    this.showStatusDropdown = false,
  });

  final String title;
  final String submitLabel;
  /// If true, show Declined vs Suspended dropdown (for existing user status change).
  final bool showStatusDropdown;

  @override
  State<DeclineReasonDialog> createState() => _DeclineReasonDialogState();
}

class _DeclineReasonDialogState extends State<DeclineReasonDialog> {
  String _preset = kDeclineReasonPresets.first;
  final TextEditingController _customController = TextEditingController();
  String _status = 'declined';

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  String get _effectiveReason {
    final custom = _customController.text.trim();
    if (_preset == 'Other') {
      return custom.isEmpty ? 'Other' : custom;
    }
    return custom.isEmpty ? _preset : '$_preset. $custom';
  }

  bool get _canSubmit {
    if (widget.showStatusDropdown) {
      return _effectiveReason.isNotEmpty;
    }
    return _effectiveReason.isNotEmpty;
  }

  /// 'proof_only' if preset is in kProofOnlyPresets, else 'full'.
  String get _reapplyType =>
      kProofOnlyPresets.contains(_preset) ? 'proof_only' : 'full';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowColor,
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkGrey,
                ),
              ),
              const SizedBox(height: 20),
              if (widget.showStatusDropdown) ...[
                const Text(
                  'Status',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.darkGrey,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'declined', child: Text('Declined')),
                    DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'declined'),
                ),
                const SizedBox(height: 16),
              ],
              const Text(
                'Reason (required – visible to resident if they log in)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.darkGrey,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _preset,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: kDeclineReasonPresets
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => _preset = v ?? kDeclineReasonPresets.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _customController,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Additional details (optional)',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlineButton(
                    text: 'Cancel',
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  CustomButton(
                    text: widget.submitLabel,
                    isFullWidth: false,
                    onPressed: _canSubmit
                        ? () {
                            Navigator.pop(
                              context,
                              DeclineReasonResult(
                                reason: _effectiveReason,
                                status: widget.showStatusDropdown ? _status : null,
                                reapplyType: _reapplyType,
                              ),
                            );
                          }
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
