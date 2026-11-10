#pragma once
#include "../Fresnel.hlsl"

// ===================================================
// Unreal 2013 Specular Fresnel
// ===================================================
half3 F_Schlick_Unreal2013(half3 base_color, half specular, half metallic, half VdotH)
{
    half3 F0_dielectric = 0.08h * specular;
    half3 F0 = lerp(F0_dielectric, base_color, metallic);
    half3 F = F_Lagarde_Approximation(F0, VdotH);
    return F;
}