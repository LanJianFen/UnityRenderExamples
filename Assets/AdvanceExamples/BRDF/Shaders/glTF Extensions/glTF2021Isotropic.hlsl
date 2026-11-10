#pragma once
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