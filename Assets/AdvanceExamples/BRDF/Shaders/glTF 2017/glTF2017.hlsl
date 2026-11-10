#pragma once
#include "glTF2017Isotropic.hlsl"
#include "glTF2017Diffuse.hlsl"
// ===================================================
// glTF 2.0
// ===================================================



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