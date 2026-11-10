#pragma once
#include "../Fresnel.hlsl"

// =====================================================================================
// Disney 2012 Fresnel
// =====================================================================================
// 绝缘体的 F0,dielectric = 0.08h * specular * lerp((half3)1.0h, chromaticity, specular_tint)
// 金属的    F0,electric   =  lerp(F0_dielectric, base_color, metallic)
half3 F_Schlick_Disney(half3 base_color, half specular, half specular_tint, half metallic, half VdotH)
{
    half luminance = dot(base_color, half3(0.2126h, 0.7152h, 0.0722h)); // 亮度
    half3 chromaticity = (luminance > 0.0h) ? (base_color / luminance) : half3(1.0h, 1.0h, 1.0h);// 色相
    half3 F0_dielectric = 0.08h * specular * lerp((half3)1.0h, chromaticity, specular_tint);
    half3 F0 = lerp(F0_dielectric, base_color, metallic);
    half3 F = F_Schlick_Approximation(F0, VdotH);
    return F;
}