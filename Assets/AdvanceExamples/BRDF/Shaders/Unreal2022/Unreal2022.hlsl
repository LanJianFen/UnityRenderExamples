#pragma once
#include "Unreal2022Isotropic.hlsl"
#include "Unreal2022Anisotropic.hlsl"
#include "Unreal2022Fresnel.hlsl"
#include "Unreal2022Diffuse.hlsl"
#include "Unreal2022DiffuseDefault.hlsl"

// 向量都是 normalization 的
// 注意看主函数的参数列表：没有 base_color，没有 metallic！直接接收 F0 和 T82！
half3 DirectSpecularBrdfUnreal2022(half Roughness, half3 N, half3 L, half3 V, half3 H, half3 F0, half3 Tint82)
{
    half NdotV = saturate(abs(dot(N, V)) + 1e-5h);
    half NdotL = saturate(dot(N, L));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));
    
    half3 SpecularBRDF = 
        D_GGX_Unreal2022(Roughness, NdotH) * 
        V_SmithJointGGX_Unreal2022(Roughness, NdotL, NdotV) * 
        F_F82_Unreal2022(F0, Tint82, VdotH);
        
    return SpecularBRDF;
}

// Unreal2022  各向异性直接光高光主函数
half3 DirectSpecularBrdfAnisotropicUnreal20222018(half Roughness, half Anisotropy,
    half3 N, half3 T, half3 B, half3 L, half3 V, half3 H,
    half3 F0, half3 Tint82)
{

    half NdotV = clamp(abs(dot(N, V)), 1e-5h, 1.0h);
    half NdotL = saturate(dot(N, L));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));

    // 切线空间点乘保留正负号，不可 saturate
    half TdotH = dot(T, H);
    half BdotH = dot(B, H);
    half TdotV = dot(T, V);
    half BdotV = dot(B, V);
    half TdotL = dot(T, L);
    half BdotL = dot(B, L);

    half at, ab;
    GetAnisotropicAlpha_Unreal2022(Roughness, Anisotropy, at, ab);

    half  D = D_GGX_Anisotropic_Unreal2022(at, ab, TdotH, BdotH, NdotH);
    half  V_vis = V_SmithJointGGX_Anisotropic_Unreal2022(at, ab, TdotV, BdotV, NdotV, TdotL, BdotL, NdotL);
    half3 F = F_F82_Unreal2022(F0, Tint82, VdotH);

    return (D * V_vis) * F;
}



// UE5 各向同性完整直接光 BRDF (Diffuse + Specular)
// 输入向量 N, L, V, H 均已归一化 (Normalized)
half3 DirectBRDF_Unreal2022(half Roughness, half3 N, half3 L, half3 V, half3 H,half3 DiffuseColor, half3 F0, half3 Tint82)
{
    half NoV = saturate(abs(dot(N, V)) + 1e-5h);
    half NoL = saturate(dot(N, L));
    half NoH = saturate(dot(N, H));
    half VoH = saturate(dot(V, H));
    
    // 计算能量守恒与能量保持项 ?? 这里的 F90 怎么确定？
    half  DiffEnergyPreservation;
    half3 SpecEnergyConservation;
    ComputeGGXSpecEnergyTerms_Unreal2022(Roughness, NoV, F0, Tint82, DiffEnergyPreservation, SpecEnergyConservation);
    
    // 漫反射可根据需求切换 Diffuse_Lambert / Diffuse_OrenNayar / Diffuse_Chan
    half3 DiffuseBRDF = DiffEnergyPreservation * DiffuseOrenNayar_Unreal2022(DiffuseColor, Roughness, NoV, NoL, VoH);
    // 高光部分利用 F_F82 同时通吃金属与非金属
    half3 SpecularBRDF = SpecEnergyConservation * 
        D_GGX_Unreal2022(Roughness, NoH) * 
        V_SmithJointGGX_Unreal2022(Roughness, NoL, NoV) * 
        F_F82_Unreal2022(F0, Tint82, VoH);

    return DiffuseBRDF + SpecularBRDF;
}