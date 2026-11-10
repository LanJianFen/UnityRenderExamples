#pragma once
#include "../Fresnel.hlsl"

// ===================================================
// glTF 2.0 2017 Fresnel
// ===================================================
// 绝缘体的 F0,dielectric 强制锁死为 0.04（即 4%，对应 IOR 1.5）
// 不再提供 Disney 的 Specular 调节滑杆（在后来的扩展中才允许输入真实的 IOR）。
half3 F_Schlick_glTF2017(half3 base_color, half metallic, half VdotH)
{
    half3 F0_dielectric = (half3)0.04h;
    half3 F0 = lerp(F0_dielectric, base_color, metallic);
    half3 F = F_Schlick_Approximation(F0, VdotH);
    return F;
}