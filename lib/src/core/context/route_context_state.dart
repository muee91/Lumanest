import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';

/// Controller-private identity of the route being followed.
///
/// Used only inside [RouteContextStateController] to decide whether a rebuilt
/// route is the *same* route as the one currently active/paused. It is never
/// exposed through [ContextSnapshot] or [RouteContextState.toRequest]; it only
/// exists so that switching from destination A to destination B (same travel
/// mode) resets the lifecycle to planned instead of keeping A's active/paused
/// stage on B.
///
/// Identity is stable across name-only changes: it is composed of the
/// destination coordinates and the travel mode, not the destination name.
class RouteIdentity {
  const RouteIdentity({
    required this.latitude,
    required this.longitude,
    required this.mode,
  });

  final double latitude;
  final double longitude;
  final ContextRouteMode mode;

  @override
  bool operator ==(Object other) =>
      other is RouteIdentity &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(latitude, longitude, mode);

  @override
  String toString() => 'RouteIdentity($latitude, $longitude, ${mode.name})';
}

/// Immutable route context state used by the environment snapshot pipeline.
///
/// This is a minimal, type-safe representation of the user's route-following
/// intent. It is owned by the route feature and consumed by core/context via
/// the environment loader and broker repository, so core never depends on a
/// feature package. It deliberately carries no navigation data: it only
/// describes whether the user is following a driving or hiking route and at
/// which stage (planned/active/paused/none).
///
/// Invariant: `mode == none` iff `stage == none`. A non-none mode always
/// carries a non-none stage. This is enforced for every construction path in
/// release builds: the constructor is private and the named factories
/// ([none], [planned], [active], [paused]) only produce legal combinations.
/// The only public mutator ([withMode]) preserves the invariant. There is no
/// public `copyWith`/`withStage` that could produce a `(none, active)` or
/// `(driving, none)` state.
class RouteContextState {
  /// Private constructor. Only the named factories call this, and they never
  /// pass an illegal combination, so the invariant holds without relying on
  /// debug asserts.
  const RouteContextState._internal({
    this.mode = ContextRouteMode.none,
    this.stage = ContextRouteStage.none,
  });

  /// No route context: no destination or no active follow.
  static const RouteContextState none = RouteContextState._internal();

  /// A route of [mode] has been planned but not started.
  ///
  /// [mode] must not be [ContextRouteMode.none]; use [none] instead.
  static RouteContextState planned(ContextRouteMode mode) {
    _rejectNoneMode(mode);
    return RouteContextState._internal(
      mode: mode,
      stage: ContextRouteStage.planned,
    );
  }

  /// A route of [mode] is being actively followed.
  ///
  /// [mode] must not be [ContextRouteMode.none].
  static RouteContextState active(ContextRouteMode mode) {
    _rejectNoneMode(mode);
    return RouteContextState._internal(
      mode: mode,
      stage: ContextRouteStage.active,
    );
  }

  /// A route of [mode] is paused.
  ///
  /// [mode] must not be [ContextRouteMode.none].
  static RouteContextState paused(ContextRouteMode mode) {
    _rejectNoneMode(mode);
    return RouteContextState._internal(
      mode: mode,
      stage: ContextRouteStage.paused,
    );
  }

  static void _rejectNoneMode(ContextRouteMode mode) {
    if (mode == ContextRouteMode.none) {
      throw ArgumentError.value(
        mode,
        'mode',
        'must not be none for a non-none stage; use RouteContextState.none',
      );
    }
  }

  final ContextRouteMode mode;
  final ContextRouteStage stage;

  /// Returns a state with [mode] applied, enforcing none/none consistency.
  /// Setting mode to none clears the stage; any other mode keeps the current
  /// stage unless it is none (a mode without a stage is treated as planned).
  RouteContextState withMode(ContextRouteMode mode) {
    if (mode == ContextRouteMode.none) return RouteContextState.none;
    final stage = this.stage == ContextRouteStage.none
        ? ContextRouteStage.planned
        : this.stage;
    return RouteContextState._internal(mode: mode, stage: stage);
  }

  /// Whether this state represents an active route follow.
  bool get isActive => stage == ContextRouteStage.active;

  /// Whether this state represents a route that has been planned but not
  /// started. Planned routes influence scene classification only for layout
  /// purposes; they must not be treated as active by the rule engine.
  bool get isPlanned => stage == ContextRouteStage.planned;

  /// Whether any route mode is set (driving or hiking).
  bool get hasRoute => mode != ContextRouteMode.none;

  /// Serializes this state into the broker canonical request shape.
  Map<String, Object?> toRequest() => {'mode': mode.name, 'stage': stage.name};

  @override
  bool operator ==(Object other) =>
      other is RouteContextState && other.mode == mode && other.stage == stage;

  @override
  int get hashCode => Object.hash(mode, stage);

  @override
  String toString() => 'RouteContextState(${mode.name}, ${stage.name})';
}

/// Riverpod state control entry for [RouteContextState].
///
/// Core owns this notifier so the environment pipeline can watch it without a
/// dependency on features. The route feature drives it through the imperative
/// helpers below ([plan], [start], [pause], [resume], [end], [switchMode]).
/// Every helper constructs [RouteContextState] through the named factories or
/// [withMode], so the none/none invariant is preserved.
class RouteContextStateController extends Notifier<RouteContextState> {
  RouteIdentity? _identity;

  @override
  RouteContextState build() {
    _identity = null;
    return RouteContextState.none;
  }

  /// Marks a route of [mode] as planned.
  ///
  /// [identity] identifies which route is being planned (destination coords +
  /// travel mode). When [identity] matches the currently-followed route and
  /// that route is already active/paused, the stage is preserved so a rebuild
  /// does not downgrade the lifecycle. When [identity] differs (e.g. switching
  /// from destination A to destination B on the same mode), the stage is reset
  /// to planned. When [identity] is null, behavior falls back to mode-only
  /// comparison.
  void plan(ContextRouteMode mode, {RouteIdentity? identity}) {
    if (mode == ContextRouteMode.none) {
      _identity = null;
      state = RouteContextState.none;
      return;
    }
    final current = state;
    if (current.mode == mode && current.stage != ContextRouteStage.none) {
      if (identity == null || identity == _identity) {
        return;
      }
    }
    _identity = identity;
    state = RouteContextState.planned(mode);
  }

  /// Switches the travel mode while preserving the current stage. A mode
  /// change while active keeps the route active so the user does not need to
  /// re-start after correcting driving/walking. Updates the route identity's
  /// travel mode so a subsequent rebuild of the same destination + new mode is
  /// treated as the same route.
  void switchMode(ContextRouteMode mode) {
    if (mode == ContextRouteMode.none) {
      _identity = null;
    } else if (_identity != null) {
      _identity = RouteIdentity(
        latitude: _identity!.latitude,
        longitude: _identity!.longitude,
        mode: mode,
      );
    }
    state = state.withMode(mode);
  }

  /// Begins an active route follow.
  void start() {
    if (state.mode == ContextRouteMode.none) return;
    state = RouteContextState.active(state.mode);
  }

  /// Pauses an active route follow.
  void pause() {
    if (!state.isActive) return;
    state = RouteContextState.paused(state.mode);
  }

  /// Resumes a paused route follow.
  void resume() {
    if (state.stage != ContextRouteStage.paused) return;
    state = RouteContextState.active(state.mode);
  }

  /// Ends the route follow entirely.
  void end() {
    _identity = null;
    state = RouteContextState.none;
  }
}

/// The single source of truth for route context state. Core/context watches
/// this; the route feature writes to it.
final routeContextStateProvider =
    NotifierProvider<RouteContextStateController, RouteContextState>(
      RouteContextStateController.new,
    );
