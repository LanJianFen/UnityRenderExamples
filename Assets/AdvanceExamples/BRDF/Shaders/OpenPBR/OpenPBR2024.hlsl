#pragma once
#include "../Fresnel.hlsl"
#include "OpenPBR2024Isotropic.hlsl"
#include "OpenPBR2024Anisotropic.hlsl"
#include "OpenPBR2024Coat.hlsl"
// ===================================================
// OpenPBR Surface (v1.0 / v1.1 Specification, 2024+)
// Autodesk (Arnold/Maya) & Adobe (Substance 3D) 联合标准
// ===================================================

// 输入向量均已归一化 (Normalized)
half3 DirectSpecularBrdfOpenPBR2024(half roughness, half3 N, half3 L, half3 V, half3 H, half3 base_color, half3 specular_tint, half specular, half ior, half metallic)
{
    half NdotV = saturate(abs(dot(N, V)) + 1e-5h);
    half NdotL = saturate(dot(N, L));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));
    
    half3 specular_brdf = D_GGX_OpenPBR(roughness, NdotH) * V_SmithJoint_GGX_OpenPBR(roughness, NdotL, NdotV) * 
        F_OpenPBR2024(base_color, specular_tint, specular, ior, metallic, VdotH);
        
    return specular_brdf;
}


// OpenPBR 2024 各向异性直接光高光主函数
// (结合 OpenPBR 的绝缘体精确 IOR 调制菲涅尔与金属 F82-Tint 菲涅尔)
half3 DirectSpecularBrdfAnisotropicOpenPBR2024(
    half roughness, half anisotropy,
    half3 N, half3 T, half3 B, half3 L, half3 V, half3 H,
    half3 base_color, half3 specular_tint, half specular, half ior, half metallic)
{
    half NdotV = saturate(abs(dot(N, V)) + 1e-5h);
    half NdotL = saturate(dot(N, L));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));

    // 切线与副切线点乘保留正负号，不可 saturate
    half TdotH = dot(T, H);
    half BdotH = dot(B, H);
    half TdotV = dot(T, V);
    half BdotV = dot(B, V);
    half TdotL = dot(T, L);
    half BdotL = dot(B, L);

    // 第一步：使用 OpenPBR 斜率方差守恒公式计算 ax, ay
    half ax, ay;
    GetAnisotropicAlpha_OpenPBR2024(roughness, anisotropy, ax, ay);

    // 第二步：评估 D * V * F
    half  D = D_GGX_Anisotropic_OpenPBR(ax, ay, TdotH, BdotH, NdotH);
    half  V_vis = V_SmithJoint_GGX_Anisotropic_OpenPBR(ax, ay, TdotV, BdotV, NdotV, TdotL, BdotL, NdotL);
    half3 F = F_OpenPBR2024(base_color, specular_tint, specular, ior, metallic, VdotH);

    return (D * V_vis) * F;
}