import 'package:flutter/foundation.dart';
import 'package:luma_nest/src/core/context/context_event.dart';
import 'package:luma_nest/src/core/entry/entry_action.dart';
import 'package:luma_nest/src/core/entry/entry_payload.dart';
import 'package:luma_nest/src/core/entry/entry_provenance.dart';

enum EntryKind {
  safety,
  photographyOpportunity,
  place,
  route,
  astronomy,
  inspiration,
  system,
}

enum EntryPriority { p0, p1, p2, p3 }

enum EntryFreshness { fresh, stale, expired }

enum EntrySeverity { info, caution, warning, critical }

enum EntrySurface {
  today,
  explore,
  route,
  inspiration,
  profile,
  shootingWindow,
  widget,
  notification,
}

enum EntryPresentationVariant {
  safety,
  shootingSession,
  skyOpportunity,
  nextWindow,
  manifestOpportunity,
  quiet,
}

enum EntryAccent { sky, moss, ember, mutedInk, night, danger }

@immutable
class EntryPresentation {
  const EntryPresentation({
    required this.variant,
    required this.eyebrow,
    required this.title,
    required this.detail,
    this.judgement,
    required this.timeLabel,
    required this.actionLabel,
    required this.accent,
  });

  final EntryPresentationVariant variant;
  final String eyebrow;
  final String title;
  final String detail;
  final String? judgement;
  final String timeLabel;
  final String actionLabel;
  final EntryAccent accent;
}

@immutable
class EntryGeoScope {
  const EntryGeoScope({required this.type, this.key});

  final ContextGeoScope type;
  final String? key;
}

@immutable
class ContextEntry {
  ContextEntry({
    required this.id,
    required this.kind,
    required this.sourceNamespace,
    required this.sourceId,
    required this.revision,
    required this.observedAt,
    required this.validFrom,
    required this.expiresAt,
    required this.freshness,
    required this.evidenceConfidence,
    required this.basePriority,
    required this.severity,
    required this.geoScope,
    required Set<EntrySurface> allowedSurfaces,
    required Iterable<EntryAction> actions,
    required this.presentation,
    required this.payload,
    required Iterable<EntryProvenance> provenance,
    required this.dedupeKey,
    Set<String> suppressionKeys = const {},
    required this.contentFingerprint,
  }) : assert(evidenceConfidence >= 0 && evidenceConfidence <= 1),
       allowedSurfaces = Set.unmodifiable(allowedSurfaces),
       actions = List.unmodifiable(actions),
       provenance = List.unmodifiable(provenance),
       suppressionKeys = Set.unmodifiable(suppressionKeys);

  final String id;
  final EntryKind kind;
  final String sourceNamespace;
  final String sourceId;
  final int revision;
  final DateTime observedAt;
  final DateTime validFrom;
  final DateTime expiresAt;
  final EntryFreshness freshness;

  /// Internal evidence signal used for deterministic qualification and rank.
  /// Presentation code must not render it as a probability or percentage.
  final double evidenceConfidence;
  final EntryPriority basePriority;
  final EntrySeverity severity;
  final EntryGeoScope geoScope;
  final Set<EntrySurface> allowedSurfaces;
  final List<EntryAction> actions;
  final EntryPresentation presentation;
  final EntryPayload payload;
  final List<EntryProvenance> provenance;
  final String dedupeKey;
  final Set<String> suppressionKeys;
  final String contentFingerprint;

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now.toUtc());
}
