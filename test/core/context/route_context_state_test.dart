import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/core/context/context_snapshot.dart';
import 'package:luma_nest/src/core/context/route_context_state.dart';

void main() {
  group('RouteContextState factories', () {
    test('none holds the none/none invariant', () {
      const state = RouteContextState.none;
      expect(state.mode, ContextRouteMode.none);
      expect(state.stage, ContextRouteStage.none);
      expect(state.hasRoute, isFalse);
      expect(state.isActive, isFalse);
      expect(state.isPlanned, isFalse);
    });

    test('planned produces a non-none mode with planned stage', () {
      final state = RouteContextState.planned(ContextRouteMode.driving);
      expect(state.mode, ContextRouteMode.driving);
      expect(state.stage, ContextRouteStage.planned);
      expect(state.hasRoute, isTrue);
      expect(state.isPlanned, isTrue);
      expect(state.isActive, isFalse);
    });

    test('active produces a non-none mode with active stage', () {
      final state = RouteContextState.active(ContextRouteMode.hiking);
      expect(state.mode, ContextRouteMode.hiking);
      expect(state.stage, ContextRouteStage.active);
      expect(state.isActive, isTrue);
    });

    test('paused produces a non-none mode with paused stage', () {
      final state = RouteContextState.paused(ContextRouteMode.driving);
      expect(state.mode, ContextRouteMode.driving);
      expect(state.stage, ContextRouteStage.paused);
      expect(state.isActive, isFalse);
      expect(state.isPlanned, isFalse);
    });

    test('planned rejects none mode', () {
      expect(
        () => RouteContextState.planned(ContextRouteMode.none),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('active rejects none mode', () {
      expect(
        () => RouteContextState.active(ContextRouteMode.none),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('paused rejects none mode', () {
      expect(
        () => RouteContextState.paused(ContextRouteMode.none),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('RouteContextState.withMode', () {
    test('setting mode to none clears to none/none', () {
      final state = RouteContextState.active(ContextRouteMode.driving);
      final next = state.withMode(ContextRouteMode.none);
      expect(next, RouteContextState.none);
      expect(next.mode, ContextRouteMode.none);
      expect(next.stage, ContextRouteStage.none);
    });

    test('switching mode preserves an active stage', () {
      final state = RouteContextState.active(ContextRouteMode.driving);
      final next = state.withMode(ContextRouteMode.hiking);
      expect(next.mode, ContextRouteMode.hiking);
      expect(next.stage, ContextRouteStage.active);
    });

    test('switching from none defaults to planned', () {
      const state = RouteContextState.none;
      final next = state.withMode(ContextRouteMode.driving);
      expect(next.mode, ContextRouteMode.driving);
      expect(next.stage, ContextRouteStage.planned);
    });
  });

  group('RouteContextState equality and serialization', () {
    test('equal states are equal', () {
      expect(
        RouteContextState.active(ContextRouteMode.driving),
        RouteContextState.active(ContextRouteMode.driving),
      );
    });

    test('different stages are not equal', () {
      expect(
        RouteContextState.planned(ContextRouteMode.driving),
        isNot(RouteContextState.active(ContextRouteMode.driving)),
      );
    });

    test('toRequest serializes the canonical shape', () {
      expect(RouteContextState.paused(ContextRouteMode.hiking).toRequest(), {
        'mode': 'hiking',
        'stage': 'paused',
      });
      expect(RouteContextState.none.toRequest(), {
        'mode': 'none',
        'stage': 'none',
      });
    });
  });

  group('RouteContextStateController', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    RouteContextStateController controller() =>
        container.read(routeContextStateProvider.notifier);

    RouteContextState state() => container.read(routeContextStateProvider);

    test('initial state is none', () {
      expect(state(), RouteContextState.none);
    });

    test('plan marks a route as planned', () {
      controller().plan(ContextRouteMode.driving);
      expect(state().mode, ContextRouteMode.driving);
      expect(state().stage, ContextRouteStage.planned);
    });

    test('plan with none clears to none', () {
      controller().plan(ContextRouteMode.driving);
      controller().plan(ContextRouteMode.none);
      expect(state(), RouteContextState.none);
    });

    test('plan does not downgrade an active route on the same mode', () {
      controller().plan(ContextRouteMode.driving);
      controller().start();
      controller().plan(ContextRouteMode.driving);
      expect(state().stage, ContextRouteStage.active);
    });

    test('plan on a different mode resets to planned', () {
      controller().plan(ContextRouteMode.driving);
      controller().start();
      controller().plan(ContextRouteMode.hiking);
      expect(state().mode, ContextRouteMode.hiking);
      expect(state().stage, ContextRouteStage.planned);
    });

    test('plan keeps active stage for the same route identity', () {
      final identity = RouteIdentity(
        latitude: 31.0,
        longitude: 121.0,
        mode: ContextRouteMode.driving,
      );
      controller().plan(ContextRouteMode.driving, identity: identity);
      controller().start();
      controller().plan(ContextRouteMode.driving, identity: identity);
      expect(state().stage, ContextRouteStage.active);
    });

    test('plan resets to planned when route identity differs', () {
      controller().plan(
        ContextRouteMode.driving,
        identity: const RouteIdentity(
          latitude: 31.0,
          longitude: 121.0,
          mode: ContextRouteMode.driving,
        ),
      );
      controller().start();
      // Same mode, different destination (A -> B): active must not survive.
      controller().plan(
        ContextRouteMode.driving,
        identity: const RouteIdentity(
          latitude: 30.0,
          longitude: 120.0,
          mode: ContextRouteMode.driving,
        ),
      );
      expect(state().mode, ContextRouteMode.driving);
      expect(state().stage, ContextRouteStage.planned);
    });

    test('plan without identity keeps mode-only compatibility', () {
      controller().plan(
        ContextRouteMode.driving,
        identity: const RouteIdentity(
          latitude: 31.0,
          longitude: 121.0,
          mode: ContextRouteMode.driving,
        ),
      );
      controller().start();
      controller().plan(ContextRouteMode.driving);
      expect(state().stage, ContextRouteStage.active);
    });

    test('end clears the route identity', () {
      controller().plan(
        ContextRouteMode.driving,
        identity: const RouteIdentity(
          latitude: 31.0,
          longitude: 121.0,
          mode: ContextRouteMode.driving,
        ),
      );
      controller().end();
      // Re-planning the same coords after end must not be treated as same.
      controller().plan(
        ContextRouteMode.driving,
        identity: const RouteIdentity(
          latitude: 31.0,
          longitude: 121.0,
          mode: ContextRouteMode.driving,
        ),
      );
      expect(state().stage, ContextRouteStage.planned);
    });

    test('start moves a planned route to active', () {
      controller().plan(ContextRouteMode.driving);
      controller().start();
      expect(state().stage, ContextRouteStage.active);
      expect(state().isActive, isTrue);
    });

    test('start is a no-op when there is no route', () {
      controller().start();
      expect(state(), RouteContextState.none);
    });

    test('pause moves an active route to paused', () {
      controller().plan(ContextRouteMode.driving);
      controller().start();
      controller().pause();
      expect(state().stage, ContextRouteStage.paused);
    });

    test('pause is a no-op when not active', () {
      controller().plan(ContextRouteMode.driving);
      controller().pause();
      expect(state().stage, ContextRouteStage.planned);
    });

    test('resume moves a paused route back to active', () {
      controller().plan(ContextRouteMode.driving);
      controller().start();
      controller().pause();
      controller().resume();
      expect(state().stage, ContextRouteStage.active);
    });

    test('resume is a no-op when not paused', () {
      controller().plan(ContextRouteMode.driving);
      controller().resume();
      expect(state().stage, ContextRouteStage.planned);
    });

    test('end clears the state to none', () {
      controller().plan(ContextRouteMode.driving);
      controller().start();
      controller().end();
      expect(state(), RouteContextState.none);
    });

    test('switchMode preserves an active stage across a mode change', () {
      controller().plan(ContextRouteMode.driving);
      controller().start();
      controller().switchMode(ContextRouteMode.hiking);
      expect(state().mode, ContextRouteMode.hiking);
      expect(state().stage, ContextRouteStage.active);
    });

    test('switchMode to none clears the state', () {
      controller().plan(ContextRouteMode.driving);
      controller().switchMode(ContextRouteMode.none);
      expect(state(), RouteContextState.none);
    });

    test('full lifecycle plan → start → pause → resume → end', () {
      final c = controller();
      c.plan(ContextRouteMode.hiking);
      expect(state(), RouteContextState.planned(ContextRouteMode.hiking));

      c.start();
      expect(state(), RouteContextState.active(ContextRouteMode.hiking));

      c.pause();
      expect(state(), RouteContextState.paused(ContextRouteMode.hiking));

      c.resume();
      expect(state(), RouteContextState.active(ContextRouteMode.hiking));

      c.end();
      expect(state(), RouteContextState.none);
    });
  });
}
