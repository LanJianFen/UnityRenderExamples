#pragma once
#include "Filament2018Isotropic.hlsl"
#include "Filament2018Anisotropic.hlsl"
#include "Filament2018Fresnel.hlsl"
#include "Filament2018Diffuse.hlsl"
// ===================================================
// Filament 2018
// ===================================================
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

// ===================================================
// Filament 2018 Anisotropic (各向异性微表面模型)
// 出处: Filament Whitepaper Section 4.9 (Listing 15 & Listing 16)
// ===================================================

// Filament 2018 各向异性直接光高光主函数
half3 DirectSpecularBrdfAnisotropicFilament2018(
    half roughness, half anisotropy,
    half3 N, half3 T, half3 B, half3 L, half3 V, half3 H,
    half3 base_color, half reflectance, half metallic)
{
    roughness = clamp(roughness, 0.045h, 1.0h);

    half NdotV = clamp(abs(dot(N, V)), 1e-5h, 1.0h);
    half NdotL = saturate(dot(N, L));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));

    // 切线空间点乘保留正负号，不可 saturate
    half TdotH = dot(T, H);
    half BdotH = dot(B, H);
    half TdotV = dot(T, V);
    half BdotV = dot(B, V);
    half TdotL = dot(T, L);
    half BdotL = dot(B, L);

    half at, ab;
    GetAnisotropicAlpha_Filament2018(roughness, anisotropy, at, ab);

    half  D = D_GGX_Anisotropic_Filament2018(at, ab, TdotH, BdotH, NdotH);
    half  V_vis = V_SmithJoint_Anisotropic_Filament2018(at, ab, TdotV, BdotV, NdotV, TdotL, BdotL, NdotL);
    half3 F = F_Schlick_Filament(base_color, reflectance, metallic, VdotH);

    return (D * V_vis) * F;
}