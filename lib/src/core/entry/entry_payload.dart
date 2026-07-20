import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/photography/shooting_session.dart';

sealed class EntryPayload {
  const EntryPayload();
}

class OpportunityEntryPayload extends EntryPayload {
  const OpportunityEntryPayload({
    required this.definitionId,
    required this.instanceId,
    this.sessionId,
    this.targetId,
    this.peaksAt,
    this.conditionBand,
  });

  final String definitionId;
  final String instanceId;
  final String? sessionId;
  final String? targetId;
  final DateTime? peaksAt;
  final ShootingConditionBand? conditionBand;
}

class SafetyEntryPayload extends EntryPayload {
  const SafetyEntryPayload({
    required this.eventId,
    required this.action,
    this.authorityRequired = false,
  });

  final String eventId;
  final ContextAction action;
  final bool authorityRequired;
}

class PlaceEntryPayload extends EntryPayload {
  const PlaceEntryPayload({
    required this.placeId,
    required this.category,
    this.distanceMeters,
    this.travelDurationSeconds,
    this.reviewedTarget = false,
  });

  final String placeId;
  final String category;
  final int? distanceMeters;
  final int? travelDurationSeconds;

  /// A normal POI or discovery candidate must never be promoted to a trusted
  /// shooting target merely because it ranks well.
  final bool reviewedTarget;
}

class SystemEntryPayload extends EntryPayload {
  const SystemEntryPayload({required this.stateCode});

  final String stateCode;
}

class InspirationEntryPayload extends EntryPayload {
  const InspirationEntryPayload({required this.noteId});

  final String noteId;
}
