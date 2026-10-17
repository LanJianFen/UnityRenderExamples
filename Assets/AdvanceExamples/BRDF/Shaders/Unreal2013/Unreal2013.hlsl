#pragma once
#include "../Fresnel.hlsl"
// ===================================================
// Unreal 2013
// ===================================================
// Unreal 2013 也使用的 Disney 的 D 项, α_D = roughness²
// 在 2013 年的 UE4 管线里，美术输入的 Roughness 被强制限制了最小值（当年是 Roughness = max(Roughness, 0.04) 
// 或在 d 上加 1e-4f）：
half D_GGX_Unreal(half roughness, half NdotH)
{
    roughness = max(roughness, 0.04h); 
    half alpha_D = roughness * roughness;
    half alpha_D2 = alpha_D * alpha_D;
    half denominator = PI * pow(NdotH * NdotH * (alpha_D2 - 1.0f) + 1.0f, 2.0f); // 分母
    half D = alpha_D2 / denominator;
    return D;
}

// 2013：Epic 分离式 Smith Schlick G项
// shadowing : (N · L) / [(N · L)  * (1 - k) + k]
// masking    : (N · V) / [(N · V)  * (1 - k) + k]
// V = G1(L) * G1(V) / [4 * (N · L) * (N · V)] =
// rcp(4 * [(N · L)  * (1 - k) + k] * [(N · V)  * (1.0h - k) + k])
// Brian Karis 做了一系列数学推演和曲线最小二乘法拟合，得到 k = α_G / 2。
// Brian Karis 对直接光的 α_G 用了 Burley 的做法，但是 IBL 回归到了 roughness²
// roughness 即使是 0， k 也是 0.125，天生不需要保护
half V_SmithSeparable_GGX_Unreal(half roughness, half NdotL, half NdotV)
{
    half alpha_G = (roughness + 1.0h) * (roughness + 1.0h) / 4.0h;
    half k = alpha_G / 2.0h;
    half G1_light_denominator = NdotL * (1.0h - k) + k;
    half G1_view_denominator = NdotV * (1.0h - k) + k;
    half V = rcp(4.0h * G1_light_denominator * G1_view_denominator);
    return V;
}


half3 F_Schlick_Unreal2013(half3 base_color, half specular, half metallic, half VdotH)
{
    half3 F0_dielectric = 0.08h * specular;
    half3 F0 = lerp(F0_dielectric, base_color, metallic);
    half3 F = F_Lagarde_Approximation(F0, VdotH);
    return F;
}


// 向量都是 normalization 的
half3 DirectSpecularBrdfUnreal2013(half roughness, half3 N, half3 L, half3 V, half3 H, half3 base_color, half specular, half metallic)
{
    half NdotV = max(dot(N, V), 1e-5h);
    half NdotL = saturate(dot(N, L));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));
    half3 specular_brdf = 
        D_GGX_Unreal(roughness, NdotH) *  V_SmithSeparable_GGX_Unreal(roughness, NdotL, NdotV) *
        F_Schlick_Unreal2013(base_color, specular, metallic, VdotH);
    return specular_brdf;
}