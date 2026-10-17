#pragma once
#include "../Fresnel.hlsl"
// ===================================================
// glTF 2.0 Extensions (2021: KHR_materials_ior + KHR_materials_specular)
// ===================================================
// [Khronos 官方 glTF-Sample-Viewer (brdf.glsl) 原版 D 项源码]
half D_GGX_glTF2021(half roughness, half NdotH)
{
    half alphaRoughness = roughness * roughness;
    half alphaRoughnessSq = alphaRoughness * alphaRoughness;
    half f = (NdotH * NdotH) * (alphaRoughnessSq - 1.0h) + 1.0h;
    return alphaRoughnessSq / (PI * f * f);
}
// [Khronos 官方 glTF-Sample-Viewer (brdf.glsl) 原版 V 项源码]
half V_SmithJoint_GGX_glTF2021(half roughness, half NdotL, half NdotV)
{
    half alphaRoughness = roughness * roughness;
    half alphaRoughnessSq = alphaRoughness * alphaRoughness;
    half GGXV = NdotL * sqrt(NdotV * NdotV * (1.0h - alphaRoughnessSq) + alphaRoughnessSq);
    half GGXL = NdotV * sqrt(NdotL * NdotL * (1.0h - alphaRoughnessSq) + alphaRoughnessSq);
    half GGX = GGXV + GGXL;
    if (GGX > 0.0h) return 0.5h / GGX;
    return 0.0h;
}

// glTF 2021 引入了真正的折射率
// 空气的折射率是 1，介质的折射率是 ior
// 对 F0 的估计是 [(ior - 1.0h) / (ior + 1.0h)]², ior ∈ [1, + ∞]，默认值为 1.5
// F0_dielectric 的参数化是 min(F0 * specular_tint, 1.0h) * specular; 这里的 specular 只控制强度
// 现实中，物理上的 F90 就是 1，但是有些极其粗糙或表面覆有微观吸光涂层的材质（如哑光黑橡胶、粗陶），美术希望彻底关掉或减弱它边缘那圈刺眼的白光
// 因此，glTF 扩展做了一个重大改革：让 specular 权重接管 F90_dielectric
half3 F_Dielectric_glTF2021(half3 specular_tint, half specular, half ior, half VdotH)
{
    half F0_physics = pow((ior - 1.0h) / (ior + 1.0h), 2.0h);
    half3 F0_dielectric = min(F0_physics * specular_tint, 1.0h) * specular;
    half3 F90_dielectric = specular;
    half3 F = F_Schlick_Approximation(F0_dielectric, F90_dielectric, VdotH);
    return F;
}

half3 F_Metal_glTF2021(half3 base_color, half VdotH)
{
    half3 F0_metal = base_color;
    half3 F90_metal = (half3)1.0h;
    half3 F = F_Schlick_Approximation(F0_metal, F90_metal, VdotH);
    return F;
}


//glTF 官方规范定义了金属和绝缘体的两种混合方式，在数学上等价，结合漫反射的时候有方便的区别
half3 F_Schlick_glTF2021(half3 base_color, half3 specular_tint, half specular, half ior, half metallic, half VdotH)
{
    half3 F_dielectric = F_Dielectric_glTF2021(specular_tint, specular, ior, VdotH);
    half3 F_metal = F_Metal_glTF2021(base_color, VdotH);
    half3 F = lerp(F_dielectric, F_metal, metallic);
    return F;
}

half3 F_Schlick_glTF2021_B(half3 base_color, half3 specular_tint, half specular, half ior, half metallic, half VdotH)
{
    half F0_dielectric_physics = pow((ior - 1.0h) / (ior + 1.0h), 2.0h);
    half3 F0_dielectric = min(F0_dielectric_physics * specular_tint, 1.0h) * specular;
    half3 F90_dielectric = specular;
    half3 F0_metal = base_color;
    half3 F90_metal = (half3)1.0h;
    
    half3 F0 = lerp(F0_dielectric, F0_metal, metallic);
    half3 F90 = lerp(F90_dielectric, F90_metal, metallic);
    half3 F = F_Schlick_Approximation(F0, F90, VdotH);
    return F;
}

// 输入向量均已归一化 (Normalized)
half3 DirectSpecularBrdfGlTF2021(half roughness, half3 N, half3 L, half3 V, half3 H, half3 base_color, half3 specular_tint, half specular, half ior, half metallic)
{
    // glTF 官方参考实现保护标准
    half NdotV = clamp(abs(dot(N, V)), 0.001h, 1.0h);
    half NdotL = saturate(dot(N, L));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));
    
    half3 specular_brdf = 
        D_GGX_glTF2021(roughness, NdotH) * 
        V_SmithJoint_GGX_glTF2021(roughness, NdotL, NdotV) * 
        F_Schlick_glTF2021(base_color, specular_tint, specular, ior, metallic, VdotH);
        
    return specular_brdf;
}
