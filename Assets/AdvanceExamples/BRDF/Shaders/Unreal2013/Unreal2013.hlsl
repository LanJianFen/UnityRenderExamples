#pragma once
#include "Unreal2013Isotropic.hlsl"
#include "Unreal2013Fresnel.hlsl"
#include "Unreal2013Diffuse.hlsl"
// ===================================================
// Unreal 2013
// ===================================================



// 向量都是 normalization 的
half3 DirectSpecularBrdfUnreal2013(half roughness, half3 N, half3 L, half3 V, half3 H, half3 base_color, half specular, half metallic)
{
    half NdotV = max(dot(N, V), 1e-5h);
    half NdotL = saturate(dot(N, L));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));
    half3 specular_brdf = 
        D_GGX_Unreal(roughness, NdotH) *  V_SmithSeparable_GGX_Unreal(roughness, NdotL, NdotV) *
        F_Schlick_Unreal2013(base_color, specular, metallic, VdotH);
    return specular_brdf;
}