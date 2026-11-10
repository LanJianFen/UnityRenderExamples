#pragma once
#include "Disney2012Isotropic.hlsl"
#include "Disney2012Anisotropic.hlsl"
#include "Disney2012Fresnel.hlsl"
#include "Disney2012Diffuse.hlsl"
// ===================================================
// Disney 2012
// ===================================================

// 向量都是 normalization 的
half3 DirectSpecularBrdfDisney(half roughness, half3 N, half3 L, half3 V, half3 H, half3 base_color, half specular, half specular_tint, half metallic)
{
    half NdotV = max(dot(N, V), 0.01h);
    half NdotL = saturate(dot(N, L));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));
    half3 SpecularBRDF = 
        D_GTR2_Disney(roughness, NdotH) *  V_SmithSeparable_GTR2_Disney(roughness, NdotL, NdotV) *
        F_Schlick_Disney(base_color, specular, specular_tint, metallic, VdotH);
    return SpecularBRDF;
}
