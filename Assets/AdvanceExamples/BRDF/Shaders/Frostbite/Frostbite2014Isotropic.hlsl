#pragma once
// ===================================================
// Frostbite 2014
// ===================================================
// Frostbite 2014 也使用 GGX 的 D 项, α_D = roughness²
// 针对移动端 FP16，为了防止除 0 和高光核爆，roughness 的最小值在被限制在了 10 的 -5 次方
half D_GGX_Frostbite(half roughness, half NdotH)
{
    half alpha = roughness * roughness;
    half alpha2 = max(alpha * alpha, 1e-5);
    half denominator = PI * pow(NdotH * NdotH * (alpha2 - 1.0f) + 1.0f, 2.0f); // 分母
    half D = alpha2 / denominator;
    return D;
}

// 2014 纯正 高度相关 Smith G 项
//  G(L,V) = 2 * (N · L) * (N · V) / [(N · V) * Al + (N · L) * Av]
// Al = sqrt(α² + (1 - α²) * (N · L)²)
// Av = sqrt(α² + (1 - α²) * (N · V)²)
// V = G(L,V) / [4 * (N · L) * (N · V)] = rcp(2 * [(N · V) Al + (N · L) Av])
// alpha clamp + 分母末端加 1e-5f 保护
half V_SmithJoint_GGX_Frostbite(half roughness, half NdotL, half NdotV)
{
    half alpha = roughness * roughness;
    half alpha2 = max(alpha * alpha, 1e-5h);;
    half Al = sqrt(alpha2 + (1.0h - alpha2) * NdotL * NdotL);
    half Av = sqrt(alpha2 + (1.0h - alpha2) * NdotV * NdotV);
    half G_denominator = NdotV * Al + NdotL * Av;
    half V = rcp(2.0h * (G_denominator + 1e-5h));
    return V;
}
