> **文档权威级别：HISTORICAL / VERSIONED REFERENCE**
> 当前产品范围以 [`docs/core-1.0-scope.md`](docs/core-1.0-scope.md) 为准。本文仅保留历史设计 QA 证据，不能重新启用 Core 1.0 已冻结或退役的能力。

# Presentation V2 Design QA

## Comparison target

- Source visual truth: `/tmp/callog-appstore-reference/reference-1.webp` through `/tmp/callog-appstore-reference/reference-5.webp` (calLog App Store captures). These references define spatial and interaction grammar rather than photography content: one dominant object, off-white stage, bold black type, olive emphasis, controls surrounding the object, and continuous state change.
- Implementation evidence: `/tmp/lumanest-v2-device/today-qinghai-session.png`, `/tmp/lumanest-v2-device/explore-collapsed-v2.png`, `/tmp/lumanest-v2-device/route-active-v2.png`, `/tmp/lumanest-v2-device/inspiration-slip-final.png`, `/tmp/lumanest-v2-device/profile-final.png`, and `/tmp/lumanest-v2-device/opportunity-final.png`.
- Combined comparison input: `/tmp/lumanest-v2-device/design-qa-comparison-v2.jpg`.
- Device and viewport: Xiaomi Mi 10 Pro, Android, 1080 x 2340 physical capture (approximately 360 logical pixels wide), portrait, system dark mode with V2-controlled light/dark stages.
- States: actionable Today session, collapsed Explore map result handle, active Route companion, lifted Inspiration slip, Profile control center, expanded Opportunity object.

## Full-view comparison evidence

The combined comparison shows the same high-level visual grammar as the source: a restrained off-white or dark stage, one dominant object per screen, heavy black display typography, olive-green action emphasis, low chrome density, and controls positioned around the current object. Explore and Route preserve the map as the full-screen action surface. Inspiration changes the entire stage instead of placing a bottle inside a generic page. Profile leads with one personal-understanding object and moves settings to secondary pages.

## Focused-region evidence

Separate original-resolution captures were inspected for the Today opportunity object, Explore search/handle, Route verdict/action object, Inspiration slip controls, Profile three-entry control row, Opportunity timeline/factor row, system bars, and selected navigation state. Additional crops were not needed because each original capture preserves readable type and control detail at 1080 x 2340; the combined comparison was used for composition and the originals for typography, spacing, icon alignment, and state inspection.

## Required fidelity surfaces

- Fonts and typography: Android system CJK sans-serif is used consistently. Display copy uses a heavy optical weight, tight negative tracking, controlled line height, and bounded wrapping. Small labels remain legible and do not compete with the main judgment.
- Spacing and layout rhythm: the implementation preserves one strong vertical rhythm and one dominant object. The 22 px page margin, 64 px floating navigation, 92 px collapsed Explore handle, and 150 px active Route action object remain usable at the device viewport without overlap or clipping.
- Colors and visual tokens: off-white canvas, near-black ink/night material, olive emphasis, blue map/action accent, and restrained danger tint map coherently to the reference language. System dark mode no longer changes V2 light-stage fields.
- Image quality and asset fidelity: the production experience uses the real AMap surface and the existing high-resolution bottle presentation. Standard Cupertino icon assets are used for controls. No placeholder raster, fake photo, or handcrafted SVG substitute was introduced. The source application's food photography is intentionally not copied into this photography product.
- Copy and content: qualitative condition bands, trends, factors, verified-target honesty, and safety separation remain intact. No probability-like quality claims or fabricated nearest-POI shooting target appears.
- Interaction and accessibility: five semantic navigation destinations, 48 px or larger primary targets, reduced-motion preference, visible selected states, direct drag on the Explore result object, bottle-paper manipulation, Route planning/active state transition, and paired Hero tags were verified.

## Findings

No actionable P0, P1, or P2 findings remain in the final comparison.

- [P3] Inspiration remains more illustrative than the source application's photoreal object cutouts.
  Location: Inspiration bottle and paper symbols.
  Evidence: the source uses food photography; the implementation uses the existing LumaNest bottle and catalog notation.
  Impact: small art-direction difference, but it does not weaken the selected spatial or interaction grammar and avoids importing irrelevant food imagery.
  Follow-up: consider a dedicated photography-paper asset set in a later brand-art pass.

## Comparison history

### Iteration 1 - blocked

- [P1] Explore search used a dark Material field under system dark mode, conflicting with the light map stage.
- [P1] Starting a Route changed only the button label; the action surface did not contract into the quiet companion state.
- [P2] Android status icons were white on the light Today stage.
- [P2] Explore kept keyboard focus after selecting a result.
- [P2] The default Explore result handle occupied too much vertical space.

### Fixes

- Applied an explicit V2 light theme in the shell while retaining the dedicated dark Inspiration stage and high-contrast preference.
- Made the persisted active journey the visible Route lifecycle truth, prevented repeated plan synchronization, and contracted active Route controls.
- Added route-aware system UI icon brightness and navigation-bar colors.
- Released search focus on map/result selection.
- Reduced the collapsed Explore object to a 92 px handle.

### Iteration 2 - passed

- Post-fix Explore evidence: `/tmp/lumanest-v2-device/explore-collapsed-v2.png`.
- Post-fix Route active evidence: `/tmp/lumanest-v2-device/route-active-v2.png`.
- Post-fix status, Today, Inspiration, Profile, and Opportunity evidence is listed in the comparison target above.
- Android log inspection showed no fatal Flutter exception or RenderFlex overflow after the final interactions.

## Primary interactions tested

- Five-tab navigation and selected-state morph.
- Explore map load, search, result selection, panel growth, map camera movement, and Route handoff.
- Route planning, catchability summary, start, active quiet companion state, and end.
- Inspiration draw, lifted slip, return, continue draw, save affordance, and action affordance.
- Today-to-Opportunity Hero navigation with the same stable session ID.
- Profile control center and automated coverage for Style, Library, and Privacy secondary pages.

## Follow-up polish

- A later brand-art pass can replace catalog notation in the bottle with a dedicated photography paper asset family without changing the V2 layout or state model.

## Today weather ambient pass

- The dynamic weather field is instantiated only for `/today`; Explore, Route, Inspiration, Profile, Opportunity, and Shooting Session routes use their own static stages and do not retain a hidden ambient ticker or GPU shader.
- The Today field uses the existing deterministic weather snapshot mapping for palette, wind direction, cloud cover, precipitation, gusts, warm dawn/sunset light, and reduced-motion/energy-saving fallbacks.
- Presentation is constrained to the upper 44% of Today as a soft weather halo. A radial mask keeps the strongest movement in the surrounding negative space, and a second vertical mask reaches zero before the main object so there is no cropped color edge or full-screen tint.
- Current Mi 10 Pro evidence: `/private/tmp/lumanest-today-weather-halo-final-a.png` and `/private/tmp/lumanest-today-weather-halo-final-b.png`, captured eight seconds apart. Both preserve high-contrast typography and an undyed main object while showing low-frequency environment movement.
- Non-Today evidence: `/private/tmp/lumanest-explore-no-ambient-final.png`; the Explore map stage contains no inherited Today color field. Android log inspection showed no fatal Flutter exception or RenderFlex overflow during the route transition.

## Live calLog navigation reference pass

- Source visual truth: `/private/tmp/callog-live-home-reference.png`, captured from the running `/Applications/calLog.app` window rather than App Store promotional imagery.
- Additional source states: `/private/tmp/callog-live-second-reference.png` and `/private/tmp/callog-live-third-reference.png`.
- Binary evidence: the extracted `Assets.car` contains 84 x 84 ordinary/selected pairs for `home`, `live`, `me`, and `water`; the linked runtime also exposes `UITabBarController`, CoreAnimation, audio, and haptic infrastructure.
- Implementation evidence: `/private/tmp/lumanest-v2-device/lumanest-dock-final.png` on the Mi 10 Pro.
- Normalized focused comparison: `/private/tmp/lumanest-v2-device/dock-comparison-final.png`. Both navigation regions were cropped to the same 288 px component width; the live calLog reference is on the left and LumaNest is on the right.
- State: first grouped destination selected, isolated primary action idle.

The final dock preserves the reference interaction hierarchy: a quiet light-material capsule, icon-only frequent destinations, one continuously moving selection object, selected/unselected icon states, and a separate circular creation action. LumaNest uses four grouped destinations instead of calLog's three because Route and Profile remain required first-level product destinations; Inspiration maps to calLog's isolated camera-action role.

No actionable P0, P1, or P2 mismatch remains. The first material experiment used an oversized generic glass slab and was deleted. A later flattened lens experiment was also reverted after device review; the final 64 px object proportions are the user-approved version.

- [P3] LumaNest uses the closest Cupertino icon family instead of calLog's food-specific raster tab assets.
  Impact: small asset-language difference, but the source icons are semantically wrong for photography and cannot represent Route or Inspiration.
  Follow-up: a future brand pass may supply dedicated 84 x 84 ordinary/selected LumaNest icon pairs without changing the dock layout or motion model.

## Final automated verification

- `flutter analyze`: passed with no issues after removing the legacy presentation files.
- `flutter test`: passed in full, including V2 navigation, interaction, compact 360 x 800 layout, and 1.5x text-scale coverage.
- `lib/src/presentation_v2/` contains no `CircularProgressIndicator`.
- `lib/src/app/router.dart` contains no legacy feature-presentation import.
- The former Golden directory and self-derived V1 Golden baselines are absent.

## SunsetBot contextual opportunity pass

- The SunsetBot result does not create a permanent Today section. It can replace the existing dominant opportunity object only when the server marks it `proactiveEligible`; unavailable, missed, or sub-0.20 results leave no placeholder and preserve the original Today composition.
- The production Mi 10 Pro request resolved to Jiaxing and returned sub-threshold results for both active daily events. Device evidence: `/private/tmp/lumanest-sunsetbot-p0-device.png`. The layout remained fully contracted around the ordinary quiet-observation object, with no empty sunset card or skeleton.
- A second device launch produced four Broker cache hits and no new SunsetBot request, confirming that the installed APK uses the deployed Broker rather than contacting the provider directly.
- SunsetBot contributes only to the Today weather ambience. Its server-calculated strength is capped at 25%, halved for low confidence and stale data, and suppressed entirely when the current context contains a safety event. Other primary routes retain their own static stages.
- The structured inspiration note appears only at score 0.60 or above and routes to the same sky-opportunity detail object. Low-score production data generated no active note.
- The detail route exposes the opportunity index, event time, AOD clarity, GFS/EC results, agreement, freshness, attribution, and the photography-reference disclaimer without exposing raw provider HTML or request fields.

final result: passed
