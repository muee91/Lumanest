#include <flutter/runtime_effect.glsl>

// 山野胶片环境色场：不承担事实表达，只为可靠内容提供低频氛围。
uniform vec2 uSize;
uniform float uTime;
uniform float uFlowRadians;
uniform float uMotion;
uniform float uCloud;
uniform float uWarmGlow;
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

  float vignette = smoothstep(1.32, 0.22, distance(uv, vec2(0.5, 0.48)));
  color *= mix(0.84, 1.0, vignette);
  fragColor = vec4(color, 1.0);
}
