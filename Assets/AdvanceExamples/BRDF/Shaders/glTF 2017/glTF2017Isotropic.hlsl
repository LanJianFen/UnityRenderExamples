#pragma once
// ===================================================
// glTF 2.0 2017 只有各向同性版本
// ===================================================
// glTF 2.0 使用纯正的 GGX D 项, α = roughness²
half D_GGX_glTF2017(half roughness, half NdotH)
{
    roughness = clamp(roughness, 0.04h, 1.0h);
    half alpha = roughness * roughness;
    half alpha2 = max(alpha * alpha, 1e-5h);
    half denominator = PI * pow(NdotH * NdotH * (alpha2 - 1.0h) + 1.0h, 2.0h); // 分母
    half D = alpha2 / denominator;
    return D;
}

// 2014 纯正 高度相关 Smith G 项
//  G(L,V) = 2 * (N · L) * (N · V) / [(N · V) * Al + (N · L) * Av]
// Al = sqrt(α² + (1 - α²) * (N · L)²)
// Av = sqrt(α² + (1 - α²) * (N · V)²)
// V = G(L,V) / [4 * (N · L) * (N · V)] = rcp(2 * [(N · V) Al + (N · L) Av])
half V_SmithJoint_GGX_glTF2017(half roughness, half NdotL, half NdotV)
{
    half alpha = roughness * roughness;
    half alpha2 = max(alpha * alpha, 1e-5h);
    half Al = sqrt(alpha2 + (1.0h - alpha2) * NdotL * NdotL);
    half Av = sqrt(alpha2 + (1.0h - alpha2) * NdotV * NdotV);
    half G_denominator = NdotV * Al + NdotL * Av;
    half V = rcp(2.0h * G_denominator);
    return clamp(V, 0.0h, 1.0h);
}