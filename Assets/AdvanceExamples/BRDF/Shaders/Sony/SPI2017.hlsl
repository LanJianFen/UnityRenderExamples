#pragma once
#include "SPI2017Isotropic.hlsl"
#include "SPI2017Anisotropic.hlsl"
#include "SPI2017Fresnel.hlsl"
#include "SPI2017Diffuse.hlsl"
// ===================================================
// Sony Pictures Imageworks (SPI) 2017
// 出处: SIGGRAPH 2017 "Revisiting Physically Based Shading at Imageworks" (Kulla & Conty)
// ===================================================


// 各向同性主函数
half3 DirectSpecularBrdfSPI2017(
    half roughness, half3 N, half3 L, half3 V, half3 H,
    half3 base_color, half3 edge_tint, half ior, half metallic)
{
    half NdotV = saturate(abs(dot(N, V)) + 1e-5h);
    half NdotL = saturate(dot(N, L));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));

    half  D = D_GGX_SPI2017(roughness, NdotH);
    half  V_vis = V_SmithJointGGX_SPI2017(roughness, NdotL, NdotV);
    half3 F = lerp(F_Dielectric_Exact_SPI2017(ior, VdotH), F_Metal_Gulbrandsen_SPI2017(base_color, edge_tint, VdotH), metallic);

    return (D * V_vis) * F;
}


// 各向异性主函数
half3 DirectSpecularBrdfAnisotropicSPI2017(
    half roughness, half anisotropy,
    half3 N, half3 T, half3 B, half3 L, half3 V, half3 H,
    half3 base_color, half3 edge_tint, half ior, half metallic)
{
    half NdotV = saturate(abs(dot(N, V)) + 1e-5h);
    half NdotL = saturate(dot(N, L));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));

    half TdotH = dot(T, H);
    half BdotH = dot(B, H);
    half TdotV = dot(T, V);
    half BdotV = dot(B, V);
    half TdotL = dot(T, L);
    half BdotL = dot(B, L);

    half ax, ay;
    GetAnisotropicAlpha_SPI2017(roughness, anisotropy, ax, ay);

    half  D = D_GGX_Anisotropic_SPI2017(ax, ay, TdotH, BdotH, NdotH);
    half  V_vis = V_SmithJointGGX_Anisotropic_SPI2017(ax, ay, TdotV, BdotV, NdotV, TdotL, BdotL, NdotL);
    half3 F = lerp(F_Dielectric_Exact_SPI2017(ior, VdotH), F_Metal_Gulbrandsen_SPI2017(base_color, edge_tint, VdotH), metallic);

    return (D * V_vis) * F;
}