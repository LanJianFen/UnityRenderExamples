#pragma once
// ===================================================
// Sony Pictures Imageworks (SPI) 2017
// 出处: SIGGRAPH 2017 "Revisiting Physically Based Shading at Imageworks" (Kulla & Conty)
// ===================================================

// 各向同性 D 项 (纯正 GGX，α = roughness²)
half D_GGX_SPI2017(half roughness, half NdotH)
{
    half alpha = roughness * roughness;
    half alpha2 = max(alpha * alpha, 1e-5h);
    half d = (NdotH * alpha2 - NdotH) * NdotH + 1.0h;
    return alpha2 / (PI * d * d);
}

// 各向同性 高度相关 Smith V 项
half V_SmithJointGGX_SPI2017(half roughness, half NdotL, half NdotV)
{
    half alpha = roughness * roughness;
    half alpha2 = max(alpha * alpha, 1e-5h);
    half Al = sqrt(alpha2 + (1.0h - alpha2) * NdotL * NdotL);
    half Av = sqrt(alpha2 + (1.0h - alpha2) * NdotV * NdotV);
    return 0.5h * rcp(NdotV * Al + NdotL * Av);
}