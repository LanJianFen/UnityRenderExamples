#pragma once
#include "../Fresnel.hlsl"
// ===================================================
// glTF 2.0
// ===================================================
// glTF 2.0 使用纯正的 GGX D 项, α = roughness²
half D_GGX_glTF2017(half roughness, half NdotH)
{
    roughness = clamp(roughness, 0.04, 1.0);
    half alpha = roughness * roughness;
    half alpha2 = max(alpha * alpha, 1e-5h);
    half denominator = PI * pow(NdotH * NdotH * (alpha2 - 1.0f) + 1.0f, 2.0f); // 分母
    half D = alpha2 / denominator;
    return D;
}

// 2014 纯正 高度相关 Smith G 项
//  G(L,V) = 2 * (N · L) * (N · V) / [(N · V) * Al + (N · L) * Av]
// Al = sqrt(α² + (1 - α²) * (N · L)²)
// Av = sqrt(α² + (1 - α²) * (N · V)²)
// V = G(L,V) / [4 * (N · L) * (N · V)] = rcp(2 * [(N · V) Al + (N · L) Av])
half V_SmithJoint_GGX_glTF2017(half roughness, half NdotL, half NdotV)
{
    half alpha = roughness * roughness;
    half alpha2 = max(alpha * alpha, 1e-5h);
    half Al = sqrt(alpha2 + (1.0h - alpha2) * NdotL * NdotL);
    half Av = sqrt(alpha2 + (1.0h - alpha2) * NdotV * NdotV);
    half G_denominator = NdotV * Al + NdotL * Av;
    half V = rcp(2.0h * G_denominator);
    return clamp(V, 0.0h, 1.0h);
}


// 绝缘体的 F0,dielectric 强制锁死为 0.04（即 4%，对应 IOR 1.5）
// 不再提供 Disney 的 Specular 调节滑杆（在后来的扩展中才允许输入真实的 IOR）。
half3 F_Schlick_glTF2017(half3 base_color, half metallic, half VdotH)
{
    half3 F0_dielectric = (half3)0.04h;
    half3 F0 = lerp(F0_dielectric, base_color, metallic);
    half3 F = F_Schlick_Approximation(F0, VdotH);
    return F;
}


// 向量都是 normalization 的
half3 DirectSpecularBrdfGlTF2017(half roughness, half3 N, half3 L, half3 V, half3 H, half3 base_color, half metallic)
{
    half NdotV = clamp(abs(dot(N, V)), 0.001h, 1.0h);
    half NdotL = saturate(dot(N, L));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));
    half3 specular_brdf = 
        D_GGX_glTF2017(roughness, NdotH) *  V_SmithJoint_GGX_glTF2017(roughness, NdotL, NdotV) *
        F_Schlick_glTF2017(base_color, metallic, VdotH);
    return specular_brdf;
}

half3 Diffuse_Brdf_glTF2017(half3 base_color, half metallic, half3 F)
{
    half3 diffuse_albedo = base_color * (1.0h - metallic);
    half3 diffuse_brdf =  (1.0h - F) * diffuse_albedo * INV_PI;
    return diffuse_brdf;
}