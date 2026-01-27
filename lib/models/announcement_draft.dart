class AnnouncementDraft {
  final String id;
  final String title;
  final String content;
  final Set<String> selectedAudiences;
  final String? aiRefinedContent;

  AnnouncementDraft({
    required this.id,
    required this.title,
    required this.content,
    required this.selectedAudiences,
    this.aiRefinedContent,
  });
}
