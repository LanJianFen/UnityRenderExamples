#pragma once
#include "../Fresnel.hlsl"

// ===================================================
// Filament 2018 Fresnel
// ===================================================
// Filament 的 F 项完全继承了 Frostbite 的 Reflectance 参数体系
half3 F_Schlick_Filament(half3 base_color, half reflectance, half metallic, half VdotH)
{
    half3 F0_dielectric = 0.16h * reflectance * reflectance;
    half3 F0 = lerp(F0_dielectric, base_color, metallic);
    half3 F = F_Schlick_Approximation(F0, VdotH);
    return F;
}