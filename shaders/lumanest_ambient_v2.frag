#include <flutter/runtime_effect.glsl>

// Independent low-frequency field for栖光. It renders atmosphere only; weather
// semantics are expressed as continuous noise fields driven by deterministic
// environmental parameters owned by Dart.
uniform vec2 uSize;
uniform float uTime;
uniform float uTimeSpeed;
uniform float uColorBalance;
uniform float uWarpStrength;
uniform float uWarpFrequency;
uniform float uWarpSpeed;
uniform float uWarpAmplitude;
uniform float uBlendAngle;
uniform float uBlendSoftness;
uniform float uRotationAmount;
uniform float uNoiseScale;
uniform float uGrainAmount;
uniform float uGrainScale;
uniform float uGrainAnimated;
uniform float uContrast;
uniform float uGamma;
uniform float uSaturation;
uniform vec2 uCenter;
uniform float uZoom;
uniform vec4 uColor1;
uniform vec4 uColor2;
uniform vec4 uColor3;
uniform float uStormFactor;
uniform float uRainStreaks;
uniform float uFlowRadians;
uniform float uWeatherKind;
uniform float uDayPhaseKind;
uniform float uCloudOpacity;
uniform float uWarmGlow;

out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float fieldNoise(vec2 p) {
  vec2 cell = floor(p);
  vec2 local = fract(p);
  vec2 smoothLocal = local * local * (3.0 - 2.0 * local);
  float a = mix(hash(cell), hash(cell + vec2(1.0, 0.0)), smoothLocal.x);
  float b = mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0, 1.0)), smoothLocal.x);
  return mix(a, b, smoothLocal.y);
}

// Two-octave fbm for richer cloud and storm structure without discrete
// particles. Kept short so balanced quality tier remains 30fps-friendly.
float fbm(vec2 p) {
  float v = 0.0;
  float amp = 0.5;
  for (int i = 0; i < 3; i++) {
    v += amp * fieldNoise(p);
    p *= 2.02;
    amp *= 0.5;
  }
  return v;
}

mat2 rotate(float radians) {
  float s = sin(radians);
  float c = cos(radians);
  return mat2(c, -s, s, c);
}

// Macro-realistic typhoon spiral field. The screen is treated as a polar
// coordinate space centered on the storm eye. Rotation speed and arm density
// grow with uStormFactor; the eye stays calm via an exp(-r^2) attenuation so
// the centre reads as a moment of stillness inside the violent flow.
float typhoonField(vec2 uv, float time, float strength) {
  vec2 centered = uv - vec2(0.5, 0.52);
  float radius = length(centered);
  float angle = atan(centered.y, centered.x);
  // Rotation rate scales with storm strength but stays below flicker threshold.
  float spin = time * (0.6 + strength * 1.8);
  // Logarithmic spiral arms: angle modulated by radius produces the inward
  // curvature characteristic of real cyclone imagery.
  float armAngle = angle + spin + radius * (6.5 + strength * 3.5);
  float arms = 0.5 + 0.5 * sin(armAngle * 3.0);
  // Turbulent detail prevents the arms from looking like a pinwheel.
  float turbulence = fbm(centered * (7.0 + strength * 4.0) + vec2(spin * 0.3));
  arms = mix(arms, turbulence, 0.45);
  // Eye: calm disc, sharp wall, outward decay.
  float eyeRadius = 0.06 + strength * 0.04;
  float eye = 1.0 - smoothstep(eyeRadius * 0.6, eyeRadius, radius);
  float wall = smoothstep(eyeRadius, eyeRadius + 0.04, radius)
             * (1.0 - smoothstep(eyeRadius + 0.06, eyeRadius + 0.22, radius));
  // Combine arms with radial falloff so the storm occupies the upper sky.
  float radialFalloff = exp(-radius * radius * 2.2);
  float field = arms * radialFalloff * (1.0 - eye * 0.92);
  field += wall * 0.45 * strength;
  return field * strength;
}

// Rain expressed as a continuous tilted streak field. Density and tilt follow
// the meteorological flow direction; speed rises with intensity. No discrete
// drops — the foreground glass blur in Dart softens everything further.
float rainStreakField(vec2 uv, float time, float intensity, float flowRadians) {
  if (intensity <= 0.001) return 0.0;
  vec2 flow = vec2(cos(flowRadians), sin(flowRadians));
  // Streak coordinate frame: one axis along the flow, one across.
  vec2 along = vec2(-flow.y, flow.x);
  vec2 streakUv = vec2(dot(uv, along), dot(uv, flow));
  // Animate along the flow direction (rain falls with the wind).
  streakUv.y -= time * (0.9 + intensity * 2.2);
  // Frequency rises with intensity. Do not threshold a full grid cell here:
  // that turns each random cell into a large rectangular band on Impeller.
  // Instead, form narrow anti-aliased lanes and use continuous noise only to
  // vary their opacity along the flow direction.
  float freq = 18.0 + intensity * 26.0;
  float lane = streakUv.x * freq + sin(streakUv.y * 1.15) * 0.13;
  float laneId = floor(lane);
  float distanceToLane = abs(fract(lane) - 0.5);
  float streak = 1.0 - smoothstep(0.055, 0.19, distanceToLane);
  float opacity = smoothstep(
    0.28,
    0.72,
    fieldNoise(vec2(laneId + 17.3, streakUv.y * 2.1))
  );

  // A quieter, thinner layer keeps depth without producing a second set of
  // repeated rectangular blocks.
  float laneB = streakUv.x * freq * 1.58 + sin(streakUv.y * 1.7 + 2.4) * 0.16;
  float laneIdB = floor(laneB);
  float distanceToLaneB = abs(fract(laneB) - 0.5);
  float streakB = 1.0 - smoothstep(0.04, 0.135, distanceToLaneB);
  float opacityB = smoothstep(
    0.38,
    0.76,
    fieldNoise(vec2(laneIdB + 43.7, streakUv.y * 2.8))
  );
  return (streak * opacity + streakB * opacityB * 0.32) * intensity;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / max(uSize, vec2(1.0));
  float ratio = uSize.x / max(uSize.y, 1.0);
  float time = uTime * uTimeSpeed;
  vec2 point = uv - vec2(0.5) + uCenter;
  point /= max(uZoom, 0.001);
  point.y /= max(ratio, 0.001);

  float directionNoise = fieldNoise(vec2(time * 0.08, point.x * point.y) * uNoiseScale);
  point = rotate(radians((directionNoise - 0.5) * uRotationAmount)) * point;

  float warp = max(uWarpStrength, 0.001);
  float amplitude = max(uWarpAmplitude, 1.0) / warp;
  float warpTime = time * uWarpSpeed;
  float visibleWarp = clamp(0.018 + uWarpStrength * 0.035 + 120.0 / amplitude * 0.002, 0.012, 0.085);
  point.x += sin(point.y * uWarpFrequency + warpTime) * visibleWarp;
  point.y += sin(point.x * (uWarpFrequency * 1.35) + warpTime * 1.18) * visibleWarp * 1.35;
  point += vec2(
    sin(warpTime * 0.55 + point.y * 2.2),
    cos(warpTime * 0.42 + point.x * 1.8)
  ) * visibleWarp * 0.42;
  point.y *= ratio;

  vec2 blendPoint = rotate(radians(uBlendAngle)) * point;
  float softness = max(uBlendSoftness, 0.001);
  float balance = uColorBalance;
  float blend = smoothstep(-0.30 - balance - softness, 0.20 - balance + softness, blendPoint.x);
  float vertical = smoothstep(-0.30 - balance - softness, 0.50 - balance + softness, blendPoint.y);
  vec3 lower = mix(uColor3.rgb, uColor2.rgb, blend);
  vec3 upper = mix(uColor2.rgb, uColor1.rgb, blend);
  vec3 color = mix(lower, upper, vertical);

  vec2 grainPoint = uv * max(uGrainScale, 0.001);
  if (uGrainAnimated > 0.5) {
    grainPoint += vec2(uTime * 0.045);
  }
  float grain = fract(sin(dot(grainPoint, vec2(12.9898, 78.233))) * 43758.5453);
  color += (grain - 0.5) * uGrainAmount;

  color = (color - 0.5) * uContrast + 0.5;
  float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
  color = mix(vec3(luminance), color, uSaturation);
  color = pow(max(color, vec3(0.0)), vec3(1.0 / max(uGamma, 0.001)));

  // Broad atmospheric movement keeps clear/cloudy scenes alive without
  // turning the background into a distracting kaleidoscope.
  float flowBand = sin(uTime * 0.32 + point.x * 3.2 + point.y * 1.4);
  float flowNoise = fieldNoise(point * 1.8 + vec2(uTime * 0.035));
  float flowAmount = (flowBand * 0.5 + flowNoise * 0.5 - 0.5) * 0.065;
  color += vec3(0.85, 0.94, 1.0) * flowAmount;

  if (uCloudOpacity > 0.01) {
    float cloudNoise = fbm(uv * 2.15 + vec2(uTime * 0.018, -uTime * 0.011));
    float cloudShape = smoothstep(0.28, 0.78, cloudNoise);
    float cloudStrength = cloudShape * uCloudOpacity * 1.45;
    float gray = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(color, vec3(gray) * 0.92 + vec3(0.025, 0.035, 0.045), cloudStrength);
  }

  // Dust gets a soft, layered veil rather than a flat brown fill.
  if (uWeatherKind > 3.5) {
    float haze = fieldNoise(uv * 3.0 + vec2(uTime * 0.018, -uTime * 0.012));
    float horizon = smoothstep(0.15, 0.85, uv.y);
    color = mix(color, color + vec3(0.12, 0.075, 0.025), haze * horizon * 0.28);
  }

  // Golden-hour scenes get a visible solar disc and halo instead of only a
  // globally warm tint. The signal is derived from the semantic warm accent
  // owned by Dart, so ordinary clear/cloudy scenes remain unchanged.
  float dawnSignal = 1.0 - step(0.5, abs(uDayPhaseKind));
  float sunsetSignal = 1.0 - step(0.5, abs(uDayPhaseKind - 2.0));
  float warmWeather = 1.0 - step(1.5, uWeatherKind);
  float warmSignal = max(dawnSignal, sunsetSignal) * warmWeather * clamp(uWarmGlow * 1.35, 0.0, 1.0);
  vec2 sunPosition = uDayPhaseKind < 1.0 ? vec2(0.78, 0.22) : vec2(0.82, 0.20);
  float sunDistance = distance(uv, sunPosition);
  float halo = exp(-sunDistance * sunDistance * 18.0);
  float disc = smoothstep(0.105, 0.055, sunDistance);
  color += vec3(1.0, 0.54, 0.16) * halo * warmSignal * 0.22;
  color += vec3(1.0, 0.78, 0.34) * disc * warmSignal * 0.34;

  // Rain streak field (continuous, no drops). Tinted cool grey-blue and
  // modulated by intensity so light rain reads as a faint veil and heavy
  // rain reads as a driving sheet.
  float rainAmount = clamp(uRainStreaks, 0.0, 1.0);
  float rain = rainStreakField(uv, uTime, rainAmount, uFlowRadians);
  color = mix(color, vec3(0.62, 0.70, 0.78), rain * 0.42);

  // Typhoon spiral field. Driven by uStormFactor and layered on top of rain so
  // the spiral arms remain visible through the falling streaks. The eye reads
  // as a calm disc inside the rotation.
  float storm = typhoonField(uv, uTime, uStormFactor);
  color = mix(color, vec3(0.45, 0.55, 0.68), storm * 0.55);

  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
