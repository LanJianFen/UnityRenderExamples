#pragma once
#include "../Fresnel.hlsl"
// ===================================================
// Unreal 2022
// ===================================================
// UE5 D 项 (源自 Engine/Shaders/Private/BRDF.ush: D_GGX)
// 全局统一 α = roughness²，分母采用 FMA 结合律，并在分母加极小量防止 α=0 且 NdotH=1 时除零
half D_GGX_Unreal2022(half roughness, half NdotH)
{
    half alpha = roughness * roughness;
    half alpha2 = max(alpha * alpha, 1e-5h);
    half d = (NdotH * alpha2 - NdotH) * NdotH + 1.0h;
    return alpha2 / (PI * d * d);
}

// UE5 V 项 [精确版] (源自 BRDF.ush: Vis_SmithJoint)
// 纯正高度相关 (Height-Correlated) Smith-GGX，彻底废除了 2013 年的 (roughness+1)/2 魔改
// V = 0.5 / [ (N · L) * sqrt((N · V)² * (1 - α²) + α²) + (N · V) * sqrt((N · L)² * (1 - α²) + α²) ]
half V_SmithJoint_Unreal2022(half roughness, half NdotL, half NdotV)
{
    half alpha = roughness * roughness;
    half alpha2 = max(alpha * alpha, 1e-5h);
    half Vis_SmithV = NdotL * sqrt(NdotV * (NdotV - NdotV * alpha2) + alpha2);
    half Vis_SmithL = NdotV * sqrt(NdotL * (NdotL - NdotL * alpha2) + alpha2);
    return 0.5h * rcp(Vis_SmithV + Vis_SmithL);
}


// 物理世界中根本不存在“半金属（50% 是塑料、50% 是黄金）”这种原子结构！
// UE5 将这两种材质彻底分开了

// ior 取值范围从 [1, +∞), 在材质面板限制取值范围
// 现实中，物理上的 F90 就是 1
half3 F_Schlick_Dielectric_Unreal2022(half VdotH, half ior_material, half ior_environment)
{
    half3 F0_dielectric = pow((ior_material - ior_environment) / (ior_material + ior_environment), 2.0h);
    half3 F90_dielectric = (half3) 1.0h;
    half3 F = F_Schlick_Approximation(F0_dielectric, F90_dielectric, VdotH);
    return F;
}

// 金属的菲涅尔在 82 附近会有一个极小值，传统的 Schlick 拟合不了
// Hoffman 2019 / Lazanyi & Szirmay-Kalos 提出、后被 Adobe 改良的数学形式  F82 修正方程
// T82在面板上以 F90 的形式呈现
half3 F_Schlick_Approximation_82(half3 F0)
{
    // VdotH82 = 1/7 (约 81.79度) 处的基准 Schlick 数值,  (1 - 1/7)^5 = (6/7)^5 = 7776.0 / 16807.0 ≈ 0.46266437
    // pow( 1 - 1/7, 5) = 7776.0h / 16807.0h ≈ 0.46266437h
    half3 F90 = (half3)1.0h;
    half3 F_Schlick_82 = F0 + (F90 - F0) * 0.46266437h;
    return F_Schlick_82;
}

// F_Schlick - { (7⁷/6⁶) * [F0 + (1 - F0) * (6 / 7)⁵] * (1 - T82)} * (V · H) * (1 - V · H)⁶
half3 F_F82_Unreal2022(half3 F0, half3 tint_82, half VdotH)
{
    half3 F90 = (half3)1.0h;
    half3 F_Schlick_base = F_Schlick_Approximation(F0, F90, VdotH);
    half3 F_Schlick_82 = F_Schlick_Approximation_82(F0);
    
    // 归一化常数 k = (7^7) / (6^6) = 823543.0 / 46656.0 ≈ 17.6513846
    const half k = 17.6513846h;
    half3 fresnel_dip = k * F_Schlick_82 * ((half3)1.0h - tint_82) * VdotH * pow(1.0h - VdotH, 6.0h);
    half3 F = saturate(F_Schlick_base - fresnel_dip);
    return F;
}


// 向量都是 normalization 的
// 注意看主函数的参数列表：没有 base_color，没有 metallic！直接接收 F0 和 T82！
half3 DirectSpecularBrdfUnreal2022(half roughness, half3 N, half3 L, half3 V, half3 H, half3 F0, half3 T82)
{
    half NdotV = saturate(abs(dot(N, V)) + 1e-5h);
    half NdotL = saturate(dot(N, L));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));
    
    half3 specular_brdf = 
        D_GGX_Unreal2022(roughness, NdotH) * 
        V_SmithJoint_Unreal2022(roughness, NdotL, NdotV) * 
        F_F82_Unreal2022(F0, T82, VdotH);
        
    return specular_brdf;
}