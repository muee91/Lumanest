enum EntryActionType {
  openShootingWindow,
  openExplore,
  openRoute,
  openPlaceDetail,
  openAstronomyDetail,
  openWildlifeDetail,
  openSafetyDetail,
  openCreativeDetail,
  dismiss,
}

class EntryAction {
  const EntryAction({required this.type, this.targetId, this.query});

  final EntryActionType type;
  final String? targetId;
  final String? query;
}
