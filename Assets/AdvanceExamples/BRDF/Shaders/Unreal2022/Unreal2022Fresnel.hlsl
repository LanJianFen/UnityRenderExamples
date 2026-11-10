#pragma once
#include "../Fresnel.hlsl"
// ===================================================
// Unreal 2022 Fresnel
// ===================================================
// 物理世界中根本不存在“半金属（50% 是塑料、50% 是黄金）”这种原子结构！
// UE5 将这两种材质彻底分开了

// 非金属菲涅尔 F
// ior 取值范围从 [1, +∞), 在材质面板限制取值范围
// 现实中，物理上的 F90 就是 1
// 采用的是普通的 F_Schlick 五次方拟合吗？UE5 是否有使用麦克斯韦？
half3 F_Schlick_Dielectric_Unreal2022(half VdotH, half IorMaterial, half IorEnvironment)
{
    half3 F0_Dielectric = pow((IorMaterial - IorEnvironment) / (IorMaterial + IorEnvironment), 2.0h);
    half3 F90_Dielectric = (half3) 1.0h;
    half3 F = F_Schlick_Approximation(F0_Dielectric, F90_Dielectric, VdotH);
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

// 金属 菲涅尔 F
// F_Schlick - { (7⁷/6⁶) * [F0 + (1 - F0) * (6 / 7)⁵] * (1 - T82)} * (V · H) * (1 - V · H)⁶
half3 F_F82_Unreal2022(half3 F0, half3 Tint82, half VdotH)
{
    half3 F90 = (half3)1.0h;
    half3 F_Schlick_Base = F_Schlick_Approximation(F0, F90, VdotH);
    half3 F_Schlick_82 = F_Schlick_Approximation_82(F0);
    
    // 归一化常数 k = (7^7) / (6^6) = 823543.0 / 46656.0 ≈ 17.6513846
    const half K = 17.6513846h;
    half3 FresnelDip = K * F_Schlick_82 * ((half3)1.0h - Tint82) * VdotH * pow(1.0h - VdotH, 6.0h);
    half3 F = saturate(F_Schlick_Base - FresnelDip);
    return F;
}