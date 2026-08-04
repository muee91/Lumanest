#include <flutter/runtime_effect.glsl>

// 山野胶片环境色场：不承担事实表达，只为可靠内容提供低频氛围。
// V1 baseline field — same semantic channels as V2 but with a lighter
// computation budget for devices that cannot sustain the V2 shader. Weather
// is expressed as continuous noise fields (no discrete particles); the
// foreground glass blur is applied in Dart via BackdropFilter.
uniform vec2 uSize;
uniform float uTime;
uniform float uFlowRadians;
uniform float uMotion;
uniform float uCloud;
uniform float uWarmGlow;
uniform float uStormFactor;
uniform float uRainStreaks;
uniform vec4 uSky;
uniform vec4 uGround;
uniform vec4 uAccent;

out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
    mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
    f.y
  );
}

float field(vec2 p, vec2 center, float radius) {
  return exp(-dot(p - center, p - center) / radius);
}

// Compact typhoon spiral field — same polar construction as V2 but with a
// single noise octave so V1 stays within budget.
float typhoonField(vec2 uv, float time, float strength) {
  if (strength <= 0.001) return 0.0;
  vec2 centered = uv - vec2(0.5, 0.52);
  float radius = length(centered);
  float angle = atan(centered.y, centered.x);
  float spin = time * (0.5 + strength * 1.5);
  float armAngle = angle + spin + radius * (5.5 + strength * 3.0);
  float arms = 0.5 + 0.5 * sin(armAngle * 3.0);
  float turbulence = noise(centered * (5.0 + strength * 3.0) + vec2(spin * 0.3));
  arms = mix(arms, turbulence, 0.4);
  float eyeRadius = 0.07 + strength * 0.04;
  float eye = 1.0 - smoothstep(eyeRadius * 0.6, eyeRadius, radius);
  float wall = smoothstep(eyeRadius, eyeRadius + 0.05, radius)
             * (1.0 - smoothstep(eyeRadius + 0.07, eyeRadius + 0.24, radius));
  float radialFalloff = exp(-radius * radius * 2.0);
  float f = arms * radialFalloff * (1.0 - eye * 0.9);
  f += wall * 0.4 * strength;
  return f * strength;
}

// Compact rain streak field — continuous, no drops.
float rainStreakField(vec2 uv, float time, float intensity, float flowRadians) {
  if (intensity <= 0.001) return 0.0;
  vec2 flow = vec2(cos(flowRadians), sin(flowRadians));
  vec2 along = vec2(-flow.y, flow.x);
  vec2 streakUv = vec2(dot(uv, along), dot(uv, flow));
  streakUv.y -= time * (0.8 + intensity * 1.8);
  float freq = 16.0 + intensity * 22.0;
  // Keep the V1 fallback continuous too. A threshold over floor(cell) was
  // rendered as repeated rectangular bands in strong rain on some GPUs.
  float lane = streakUv.x * freq + sin(streakUv.y * 1.1) * 0.12;
  float laneId = floor(lane);
  float distanceToLane = abs(fract(lane) - 0.5);
  float streak = 1.0 - smoothstep(0.06, 0.20, distanceToLane);
  float opacity = smoothstep(
    0.30,
    0.73,
    noise(vec2(laneId + 19.1, streakUv.y * 2.0))
  );
  return streak * opacity * intensity;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 flow = vec2(cos(uFlowRadians), sin(uFlowRadians));
  float time = uTime * (0.018 + uMotion * 0.05);
  float grain = noise(uv * 4.8 + flow * time);
  vec2 drift = flow * time + vec2(grain * 0.08, sin(time * 1.4) * 0.035);

  vec3 color = mix(uGround.rgb, uSky.rgb, smoothstep(-0.12, 1.04, uv.y));
  float cloud = smoothstep(0.24, 0.86, noise(uv * 3.3 - drift * 1.8));
  color = mix(color, vec3(dot(color, vec3(0.333))), cloud * uCloud * 0.52);

  float blueField = field(uv + drift * 0.18, vec2(0.20, 0.20), 0.15);
  float greenField = field(uv - drift * 0.12, vec2(0.78, 0.66), 0.19);
  float ridgeField = field(uv + drift * 0.08, vec2(0.44, 0.92), 0.11);
  color = mix(color, uAccent.rgb, (blueField + greenField * 0.72 + ridgeField * 0.38) * 0.18);

  float warm = field(uv - flow * 0.07, vec2(0.78, 0.18), 0.075) * uWarmGlow;
  color = mix(color, vec3(1.0, 0.48, 0.25), warm * 0.38);

  // Rain streak field — continuous, no discrete drops.
  float rain = rainStreakField(uv, uTime, clamp(uRainStreaks, 0.0, 1.0), uFlowRadians);
  color = mix(color, vec3(0.62, 0.70, 0.78), rain * 0.40);

  // Typhoon spiral field — rotating arms with a calm eye.
  float storm = typhoonField(uv, uTime, clamp(uStormFactor, 0.0, 1.0));
  color = mix(color, vec3(0.45, 0.55, 0.68), storm * 0.55);

  float vignette = smoothstep(1.32, 0.22, distance(uv, vec2(0.5, 0.48)));
  color *= mix(0.84, 1.0, vignette);
  fragColor = vec4(color, 1.0);
}
