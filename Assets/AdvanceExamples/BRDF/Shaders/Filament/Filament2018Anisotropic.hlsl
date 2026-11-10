#pragma once
// ===================================================
// Filament 2018 Anisotropic
// ===================================================

// Filament 2018 各向异性粗糙度转换 (采纳 Kulla & Conty 2017 线性映射)
// anisotropy ∈ [-1.0, 1.0]：正值沿切线 T 变粗，负值沿副切线 B 变粗
// 下限强制锁死在 0.001h，防止 anisotropy = ±1.0 时粗糙度归零引发除零崩溃
void GetAnisotropicAlpha_Filament2018(half roughness, half anisotropy, out half at, out half ab)
{
    roughness = max(roughness, 0.045h);
    half alpha = roughness * roughness;
    at = max(alpha * (1.0h + anisotropy), 0.001h);
    ab = max(alpha * (1.0h - anisotropy), 0.001h);
}

// Filament 各向异性 D 项
// 数学原式: 1 / [ π * at * ab * ( (T·H / at)² + (B·H / ab)² + (N·H)² )² ]
// 通过构造向量 v = (ab * (T·H), at * (B·H), at*ab * (N·H))，将分母内的两次除法转化为一次点乘 dot(v, v)
half D_GGX_Anisotropic_Filament2018(half at, half ab, half TdotH, half BdotH, half NdotH)
{
    half alpha2 = at * ab;
    float3 v = float3(ab * TdotH, at * BdotH, alpha2 * NdotH); // 使用 float3 防止 a2*NdotH 在平方时精度丢失
    float v2 = dot(v, v);
    half d = alpha2 / v2;
    return alpha2 * d * d * (1.0h / PI);
}


// ===================================================
// Filament 2018 Anisotropic (各向异性微表面模型)
// 出处: Filament Whitepaper Section 4.9 (Listing 15 & Listing 16)
// ===================================================
// Filament 各向异性 V 项
// 高度相关各向异性 Smith G 项 (Heitz 2014 Exact)
// 数学原式: 0.5 / [ (N · L) * sqrt(αx² * (T · V)² + αy² * (B · V)² + (N · V)²) + (N · V)²) * sqrt(αx² * (T · L)² + αy² * (B · L)² + (N · L)²) ]
half V_SmithJoint_Anisotropic_Filament2018(
    half at, half ab,
    half TdotV, half BdotV, half NdotV,
    half TdotL, half BdotL, half NdotL)
{
    half lambdaV = NdotL * length(half3(at * TdotV, ab * BdotV, NdotV));
    half lambdaL = NdotV * length(half3(at * TdotL, ab * BdotL, NdotL));
    return 0.5h / (lambdaV + lambdaL);
}