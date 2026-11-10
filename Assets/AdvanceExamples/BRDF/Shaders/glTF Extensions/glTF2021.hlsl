#pragma once
#include "glTF2021Isotropic.hlsl"
#include "glTF2023Anisotropic.hlsl"
#include "glTF2021Fresnel.hlsl"
#include "glTF2021Diffuse.hlsl"
// ===================================================
// glTF  Extensions (2021: KHR_materials_ior + KHR_materials_specular)
// ===================================================
// 输入向量均已归一化 (Normalized)
half3 DirectSpecularBrdfGlTF2021(half roughness, half3 N, half3 L, half3 V, half3 H, half3 base_color, half3 specular_tint, half specular, half ior, half metallic)
{
    // glTF 官方参考实现保护标准
    half NdotV = clamp(abs(dot(N, V)), 0.001h, 1.0h);
    half NdotL = saturate(dot(N, L));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));
    
    // 先分别算出绝缘体与金属的 F 项 (这正是我们在 glTF 2021 保留方式 A 的原因！)
    half3 F_dielectric = F_Dielectric_glTF2021(specular_tint, specular, ior, VdotH);
    half3 F_metal      = F_Metal_glTF2021(base_color, VdotH);
    half3 F_total      = lerp(F_dielectric, F_metal, metallic);
    
    // 漫反射只扣除绝缘体高光抢走的能量 (1 - max3(F_dielectric))
    half3 diffuse_brdf = Diffuse_glTF2021(base_color, metallic, F_dielectric);

    half3 specular_brdf = D_GGX_glTF2021(roughness, NdotH) * V_SmithJoint_GGX_glTF2021(roughness, NdotL, NdotV) * 
        F_Schlick_glTF2021(base_color, specular_tint, specular, ior, metallic, VdotH) * F_total
        
    return diffuse_brdf + specular_brdf;
}


// glTF 2023 各向异性直接光高光主函数 (结合 2021 的 IOR 与 Specular 扩展 F 项)
half3 DirectSpecularBrdfAnisotropicGlTF2023(
    half roughness, half anisotropy, half anisotropy_rotation,
    half3 N, half3 T_geom, half3 B_geom, half3 L, half3 V, half3 H,
    half3 base_color, half3 specular_tint, half specular, half ior, half metallic)
{
    half NdotV = clamp(abs(dot(N, V)), 0.001h, 1.0h);
    half NdotL = saturate(dot(N, L));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));
    // 根据旋转角旋转切线坐标系
    half3 T, B;
    RotateAnisotropicTangent_glTF2023(N, T_geom, B_geom, anisotropy_rotation, T, B);
    half TdotH = dot(T, H);
    half BdotH = dot(B, H);
    half TdotV = dot(T, V);
    half BdotV = dot(B, V);
    half TdotL = dot(T, L);
    half BdotL = dot(B, L);
    // 计算单向插值各向异性粗糙度 at, ab
    half at, ab;
    GetAnisotropicAlpha_glTF2023(roughness, anisotropy, at, ab);

    half  D = D_GGX_Anisotropic_glTF2023(at, ab, TdotH, BdotH, NdotH);
    half  V_vis = V_SmithJoint_GGX_Anisotropic_glTF2023(at, ab, TdotV, BdotV, NdotV, TdotL, BdotL, NdotL);
    half3 F = F_Schlick_glTF2021(base_color, specular_tint, specular, ior, metallic, VdotH);
    return (D * V_vis) * F;
}