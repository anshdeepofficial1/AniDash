enum AssistantRole { coordinator, animeText, vision, action }

enum AiCapability { read, navigation, write, destructive }

enum AiAttachmentType { image, screenshot, pastedList, anime, episode }

enum AiStreamEventType { textDelta, handoff, action, error, done }

class AssistantProfile {
  const AssistantProfile({
    required this.id,
    required this.defaultName,
    required this.role,
    this.userName,
    this.customInstructions = '',
  });
  final String id;
  final String defaultName;
  final AssistantRole role;
  final String? userName;
  final String customInstructions;
  String get displayName =>
      userName?.trim().isNotEmpty == true ? userName!.trim() : defaultName;
  AssistantProfile copyWith({String? userName, String? customInstructions}) =>
      AssistantProfile(
        id: id,
        defaultName: defaultName,
        role: role,
        userName: userName ?? this.userName,
        customInstructions: customInstructions ?? this.customInstructions,
      );
}

class AiAttachment {
  const AiAttachment({required this.type, required this.value, this.label});
  final AiAttachmentType type;
  final String value;
  final String? label;
  Map<String, Object?> toJson() => {
    'type': type.name,
    'value': value,
    if (label != null) 'label': label,
  };
}

class AiContext {
  const AiContext({
    this.animeId,
    this.animeTitle,
    this.currentEpisode,
    this.librarySummary,
    this.conversationHistory = const [],
    this.sourceRoute,
  });
  final String? animeId;
  final String? animeTitle;
  final int? currentEpisode;
  final Map<String, Object?>? librarySummary;
  final List<Map<String, Object?>> conversationHistory;
  final String? sourceRoute;
  Map<String, Object?> toJson() => {
    if (animeId != null) 'animeId': animeId,
    if (animeTitle != null) 'animeTitle': animeTitle,
    if (currentEpisode != null) 'currentEpisode': currentEpisode,
    if (librarySummary != null) 'librarySummary': librarySummary,
    if (conversationHistory.isNotEmpty)
      'conversationHistory': conversationHistory,
    if (sourceRoute != null) 'sourceRoute': sourceRoute,
  };
}

class AiRequest {
  const AiRequest({
    required this.message,
    required this.assistantId,
    required this.displayName,
    required this.globalInstructions,
    required this.specialistInstructions,
    required this.context,
    this.attachments = const [],
    this.editAuthorized = false,
  });
  final String message;
  final String assistantId;
  final String displayName;
  final String globalInstructions;
  final String specialistInstructions;
  final AiContext context;
  final List<AiAttachment> attachments;
  final bool editAuthorized;
  Map<String, Object?> toJson() => {
    'message': message,
    'assistantId': assistantId,
    'assistantDisplayName': displayName,
    'instructions': {
      'global': globalInstructions,
      'specialist': specialistInstructions,
    },
    'context': context.toJson(),
    'attachments': attachments.map((item) => item.toJson()).toList(),
    'editAuthorized': editAuthorized,
  };
}

class AiAction {
  const AiAction({
    required this.type,
    required this.capability,
    this.arguments = const {},
    this.label,
  });
  final String type;
  final AiCapability capability;
  final Map<String, Object?> arguments;
  final String? label;
  factory AiAction.fromJson(Map<String, Object?> json) => AiAction(
    type: json['type']?.toString() ?? '',
    capability: AiCapability.values.firstWhere(
      (value) => value.name == json['capability'],
      orElse: () => AiCapability.read,
    ),
    arguments: Map<String, Object?>.from(json['arguments'] as Map? ?? const {}),
    label: json['label']?.toString(),
  );
}

class AiResponse {
  const AiResponse({
    required this.text,
    required this.assistantId,
    this.actions = const [],
    this.handoffFrom,
    this.handoffTo,
    this.cached = false,
  });
  final String text;
  final String assistantId;
  final List<AiAction> actions;
  final String? handoffFrom;
  final String? handoffTo;
  final bool cached;
}

class AiStreamEvent {
  const AiStreamEvent(this.type, {this.text, this.response});
  final AiStreamEventType type;
  final String? text;
  final AiResponse? response;
}

class AiActionProgress {
  const AiActionProgress({
    required this.jobId,
    required this.state,
    required this.completed,
    required this.total,
    this.item,
    this.error,
  });
  final String jobId;
  final String state;
  final int completed;
  final int total;
  final String? item;
  final String? error;
}
