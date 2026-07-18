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
- Spacing and layout rhythm: the implementation preserves one strong vertical rhythm and one dominant object. The 22 px page margin, 70 px floating navigation, 92 px collapsed Explore handle, and 150 px active Route action object remain usable at the device viewport without overlap or clipping.
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

## Final automated verification

- `flutter analyze`: passed with no issues after removing the legacy presentation files.
- `flutter test`: passed in full, including V2 navigation, interaction, compact 360 x 800 layout, and 1.5x text-scale coverage.
- `lib/src/presentation_v2/` contains no `CircularProgressIndicator`.
- `lib/src/app/router.dart` contains no legacy feature-presentation import.
- The former Golden directory and self-derived V1 Golden baselines are absent.

final result: passed
