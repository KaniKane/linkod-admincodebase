class AnnouncementDraft {
  final String id;
  final String title;
  final String content;
  /// Original content (before AI refine). Used to restore the Content field when loading draft.
  final String? originalContent;
  final Set<String> selectedAudiences;
  final String? aiRefinedContent;

  AnnouncementDraft({
    required this.id,
    required this.title,
    required this.content,
    this.originalContent,
    required this.selectedAudiences,
    this.aiRefinedContent,
  });
}
