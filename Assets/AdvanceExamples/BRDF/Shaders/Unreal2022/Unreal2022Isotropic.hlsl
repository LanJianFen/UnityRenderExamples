#pragma once
// ===================================================
// Unreal 2022
// ===================================================
// UE5 D 项 (源自 Engine/Shaders/Private/BRDF.ush: D_GGX)
// 全局统一 α = roughness²，分母采用 FMA 结合律，并在分母加极小量防止 α=0 且 NdotH=1 时除零
half D_GGX_Unreal2022(half Roughness, half NdotH)
{
    half Alpha = Roughness * Roughness;
    half Alpha2 = max(Alpha * Alpha, 1e-5h);
    half D = (NdotH * Alpha2 - NdotH) * NdotH + 1.0h;
    return Alpha2 / (PI * D * D);
}

// UE5 V 项 [精确版] (源自 BRDF.ush: Vis_SmithJoint)
// 纯正高度相关 (Height-Correlated) Smith-GGX，彻底废除了 2013 年的 (roughness+1)/2 魔改
// V = 0.5 / [ (N · L) * sqrt((N · V)² * (1 - α²) + α²) + (N · V) * sqrt((N · L)² * (1 - α²) + α²) ]
half V_SmithJointGGX_Unreal2022(half Roughness, half NdotL, half NdotV)
{
    half Alpha = Roughness * Roughness;
    half Alpha2 = max(Alpha * Alpha, 1e-5h);
    half Vis_SmithV = NdotL * sqrt(NdotV * (NdotV - NdotV * Alpha2) + Alpha2);
    half Vis_SmithL = NdotV * sqrt(NdotL * (NdotL - NdotL * Alpha2) + Alpha2);
    return 0.5h * rcp(Vis_SmithV + Vis_SmithL);
}