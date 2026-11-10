#pragma once
#include "../Fresnel.hlsl"
// ===================================================
// Frostbite 2014 Fresnel
// ===================================================
// 为了更符合感知曲线， Frostbite 把 Disney 的 0.08 * specular 改成了 0.16 * reflectance * reflectance
// 真钻石（IOR=2.42）超过了 2.0, F0 约等于 0.172，Frostbite 上限只有 0.16，丢弃了 1% 的极限钻石精度
// Frostbite 2014  原版使用的是 5 次方 F_Schlick_Approximation，
half3 F_Schlick_Frostbite(half3 base_color, half reflectance, half metallic, half VdotH)
{
    half3 F0_dielectric = 0.16h * reflectance * reflectance;
    half3 F0 = lerp(F0_dielectric, base_color, metallic);
    half3 F = F_Schlick_Approximation(F0, VdotH);
    return F;
}