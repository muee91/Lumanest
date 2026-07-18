#include <flutter/runtime_effect.glsl>

// 液态玻璃（Liquid Glass）底部导航栏着色器
// 模拟物理玻璃：折射、模糊、内发光、表面光泽、细微颗粒与边缘高光

uniform vec2 uSize;
uniform float uTime;
uniform float uFlowRadians;
uniform float uMotion;
uniform float uGlassOpacity;
uniform float uBlur;
uniform float uNoiseAmount;

uniform vec4 uBase;      // 玻璃基底色
uniform vec4 uTint;      // 环境折射色
uniform vec4 uHighlight; // 表面高光色
uniform vec4 uShadow;    // 边缘阴影色

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

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * noise(p);
    p *= 2.02;
    a *= 0.5;
  }
  return v;
}

// 模拟玻璃内部的光线折射扭曲
vec2 refractUv(vec2 uv, float amount) {
  vec2 flow = vec2(cos(uFlowRadians), sin(uFlowRadians));
  float t = uTime * (0.015 + uMotion * 0.035);
  float n = fbm(uv * 3.4 + flow * t);
  float n2 = fbm(uv * 6.8 - flow * t * 1.3);
  return uv + vec2(n - 0.5, n2 - 0.5) * amount;
}

// 表面光泽（specular）
float specular(vec2 uv, float direction) {
  vec2 flow = vec2(cos(direction), sin(direction));
  float t = uTime * 0.012;
  // 一条缓慢划过玻璃的高光带
  vec2 bandCenter = vec2(0.5) + flow * (0.42 * sin(t * 0.7));
  vec2 delta = uv - bandCenter;
  float dist = length(delta);
  float band = smoothstep(0.28, 0.0, dist);
  // 叠加细碎的微光
  float micro = pow(noise(uv * 18.0 + t), 3.0) * 0.25;
  return band * 0.22 + micro;
}

// 边缘高光（让玻璃边界有体积感）
float rimLight(vec2 uv, float radius, float softness) {
  vec2 center = vec2(0.5);
  float d = distance(uv, center);
  return smoothstep(radius, radius - softness, d) * smoothstep(0.0, radius, d);
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = fragCoord / uSize;

  // 上下方向让 uv 的 Y 映射到 [0,1] 玻璃条带范围（实际由宿主裁剪，这里保留归一化）
  vec2 refracted = refractUv(uv, 0.018 * uBlur);

  // 基础玻璃颜色，带有环境折射扰动
  vec3 base = mix(uBase.rgb, uTint.rgb, (refracted.x - 0.5) * 0.18 + 0.1);

  // 细微玻璃颗粒感
  float grain = noise(uv * 240.0 + uTime * 0.05);
  base += (grain - 0.5) * uNoiseAmount;

  // 内部体积雾
  float volume = fbm(uv * 4.2 + vec2(uTime * 0.01)) * 0.5 + 0.5;
  base = mix(base, base * 1.06, volume * 0.12);

  // 表面光泽
  float shine = specular(uv, uFlowRadians);
  base += uHighlight.rgb * shine * uHighlight.a;

  // 边缘阴影与高光
  float rim = rimLight(uv, 0.92, 0.18);
  base += uShadow.rgb * (1.0 - rim) * 0.14 * uShadow.a;
  base += uHighlight.rgb * rim * 0.10 * uHighlight.a;

  // 底部稍厚，模拟玻璃材料厚度
  float thickness = smoothstep(0.0, 0.35, uv.y);
  base *= 0.96 + thickness * 0.08;

  // 计算 alpha：玻璃基底色 + 动态折射带来的 alpha 变化
  float alpha = uGlassOpacity + volume * 0.04 + shine * 0.15;
  alpha = clamp(alpha, 0.0, 0.92);

  fragColor = vec4(base, alpha);
}
