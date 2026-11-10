#pragma once
// ===================================================
// Sony Pictures Imageworks (SPI) 2017 Anisotropic
// ===================================================

// SPI 2017 首创的各向异性线性参数化
// (注：SPI 原版讲义中 anisotropy ∈ [0, 1]；后来的 Filament/UE5 将其直接推广至 [-1, 1] 双向拉伸)
// 恒定的量：(αx + αy) /2 = 2
// αx * αy = α² * (1- anisotropy²)，中心亮度会随着 anisotropy 增大而暴涨
void GetAnisotropicAlpha_SPI2017(half Roughness, half Anisotropy, out half AlphaX, out half AlphaY)
{
    half Alpha = Roughness * Roughness;
    AlphaX = max(Alpha * (1.0h + Anisotropy), 1e-3h);
    AlphaY = max(Alpha * (1.0h - Anisotropy), 1e-3h);
}

// 各向异性 D 项
// 数学原式: 1 / [ π * αx * αy * ( (T·H / αx)² + (B·H / αy)² + (N·H)² )² ]
half D_GGX_Anisotropic_SPI2017(half AlphaX, half AlphaY, half XdotH, half YdotH, half NdotH)
{
    half Alpha2 = AlphaX * AlphaY;
    half3 V = half3(AlphaY * XdotH, AlphaX * YdotH, Alpha2 * NdotH);
    half V2 = max(dot(V, V), 1e-5h);
    half D = Alpha2 / V2;
    return Alpha2 * D * D * (1.0h / PI);
}

// 各向异性 高度相关 Smith V 项
half V_SmithJointGGX_Anisotropic_SPI2017(half AlphaX, half AlphaY, half XdotV, half YdotV, half NdotV, half XdotL, half YdotL, half NdotL)
{
    half Al = length(half3(AlphaX * XdotL, AlphaY * YdotL, NdotL));
    half Av = length(half3(AlphaX * XdotV, AlphaY * YdotV, NdotV));
    return 0.5h * rcp(NdotV * Al + NdotL * Av + 1e-5h);
}