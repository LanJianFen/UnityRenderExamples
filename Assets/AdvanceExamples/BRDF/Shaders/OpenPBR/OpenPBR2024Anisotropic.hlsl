#pragma once

// ===================================================
// OpenPBR Surface Anisotropic (v1.0 / v1.1 Official Specification, 2024+)
// ===================================================

// OpenPBR 官方各向异性粗糙度转换 (源自 MaterialX: open_pbr_anisotropy)
// 核心物理守恒律：
//   (1) 长宽比线性控制: ay / ax = 1 - anisotropy
//   (2) 斜率方差平方和守恒: (ax² + ay²) / 2 = α² (其中 α = roughness²)
//  αx = α * sqrt( 2 / (1 + (1 - anisotropy)²)), αy = αx * (1 - anisotropy)
// αx * αy = 2α² * (1 - anisotropy) / (1 + (1 - anisotropy)²)，中心亮度缓慢上升
// αx >= αy，必须额外贴一张旋转角度贴图，调用sin\cos旋转 T
void GetAnisotropicAlpha_OpenPBR2024(half roughness, half anisotropy, out half alphax, out half alphay)
{
    half alpha = roughness * roughness;
    half a = 1.0h - saturate(anisotropy); // a ∈ [0, 1]
    
    alphax = alpha * sqrt(2.0h / (1.0h + a * a));
    alphay = a * alphax;
    
    // 防除零安全底线
    alphax = max(alphax, 1e-3h);
    alphay = max(alphay, 1e-3h);
}

// 各向异性 D 项 (与 Frostbite / Filament / UE5 / glTF 完全通用)
// 数学原式: 1 / [ π * αx * αy * ( (T·H / αx)² + (B·H / αb)² + (N·H)² )² ]
// 通过构造向量 v = (αy * (T·H), αx * (B·H), αx*αy * (N·H))，将分母内的两次除法转化为一次点乘 dot(v, v)
half D_GGX_Anisotropic_OpenPBR(half alphax, half alphay, half TdotH, half BdotH, half NdotH)
{
    half alpha2 = alphax * alphay;
    float3 v = float3(alphay * TdotH, alphax * BdotH, alpha2 * NdotH);
    float v2 = max(dot(v, v), 1e-7f);
    half d = alpha2 / v2;
    return alpha2 * d * d * (1.0h / PI);
}

// 各向异性 V 项 (Heitz 2014 高度相关各向异性精确版)
// 数学原式: 0.5 / [ (N · L) * sqrt(αx² * (T · V)² + αy² * (B · V)² + (N · V)²) + (N · V) * sqrt(αx² * (T · L)² + αy² * (B · L)² + (N · L)²) ]
half V_SmithJoint_GGX_Anisotropic_OpenPBR(
    half alphax, half alphay,
    half XdotV, half YdotV, half NdotV,
    half XdotL, half YdotL, half NdotL)
{
    half Al = length(half3(alphax * XdotL, alphay * YdotL, NdotL));
    half Av = length(half3(alphax * XdotV, alphay * YdotV, NdotV));
    return 0.5h * rcp(NdotV * Al + NdotL * Av + 1e-5h);
}