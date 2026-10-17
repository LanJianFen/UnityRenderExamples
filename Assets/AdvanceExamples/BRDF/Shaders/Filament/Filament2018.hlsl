#pragma once
#include "../Fresnel.hlsl"
// ===================================================
// Filament 2018
// ===================================================
// Filament 2018 使用了纯正的 GGX，但是做了 FMA 指令优化
// 分子 : α²
// 分母 : PI * ((N · H) ² * (α ² - 1) + 1)  ² = PI * ( ((N · H) * α ² -(N · H)) * (N · H)  + 1 )²
// Filament 规定 roughness 在传入前已确保 >= 0.089  或 0.045 (PC), 所以不需要写 max(a2, 1e-5)
half D_GGX_Filament(half roughness, half NdotH)
{
    roughness = clamp(roughness, 0.045h, 1.0h);
    half alpha = roughness * roughness;
    half alpha2 = alpha * alpha;
    half denominator = (NdotH * alpha2 - NdotH) * NdotH + 1.0h;
    denominator = PI * denominator * denominator;
    half D = alpha2 / denominator;                                                // Filament 直接使用极其干净的除法
    return D;
}


// Filament 为 V 项（高度相关 Smith G）准备了高配版（PC/主机）和低配版（移动端）两套方案
half V_SmithJoint_Filament(half roughness, half NdotL, half NdotV)
{
    roughness = clamp(roughness, 0.045h, 1.0h);
    half alpha = roughness * roughness;
    half alpha2 = alpha * alpha;
    half G_denominator1 = NdotL * sqrt(alpha2 + (1.0h - alpha2) * NdotV * NdotV);
    half G_denominator2 = NdotV * sqrt(alpha2 + (1.0h - alpha2) * NdotL * NdotL);
    half V = 0.5h / (G_denominator1 + G_denominator2);
    return V;
}


// V 项的 Hammon 2017 近似
// G 项的分母 (N · V) Al + (N · L) Av
// Al = sqrt(α² + (1 - α²) * (N · L)²)
// α = 0 时, (N · V) Al + (N · L) Av = 2 * (N · L) * (N · V)
// α = 1 时, (N · V) Al + (N · L) Av = (N · L) + (N · V)
// Hammon 直接用直接用 α 作为权重，在它们俩之间做一个 lerp
half V_SmithJoint_Hammon_Filament(half roughness, half NdotL, half NdotV)
{
    half alpha = roughness * roughness;
    half denominator = lerp(2.0h * NdotL * NdotV, NdotL + NdotV, alpha);
    half V = 0.5h / (denominator + 1e-5h);
    return V;
}


// Filament 的 F 项完全继承了 Frostbite 的 Reflectance 参数体系
half3 F_Schlick_Filament(half3 base_color, half reflectance, half metallic, half VdotH)
{
    half3 F0_dielectric = 0.16h * reflectance * reflectance;
    half3 F0 = lerp(F0_dielectric, base_color, metallic);
    half3 F = F_Schlick_Approximation(F0, VdotH);
    return F;
}


// 向量都是 normalization 的
half3 DirectSpecularBrdfFilament2018(half roughness, half3 N, half3 L, half3 V, half3 H, half3 base_color, half reflectance, half metallic)
{
    half NdotV = clamp(abs(dot(N, V)), 0.001h, 1.0h);
    half NdotL = saturate(dot(N, L));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));
    half3 specular_brdf = 
        D_GGX_Filament(roughness, NdotH) *  V_SmithJoint_Filament(roughness, NdotL, NdotV) *
        F_Schlick_Filament(base_color, reflectance, metallic, VdotH);
    return specular_brdf;
}