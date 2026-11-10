#pragma once
// =====================================================================================
// Frostbite 2014 Anisotropic (各向异性微表面模型)
// 参数化: 沿用 Disney 2012 的 aspect = sqrt(1 - 0.9 * anisotropy)
// D 项  : GTR2 Anisotropic (Burley 2012)
// V 项  : 首次实装各向异性高度相关 Smith G 项 (Heitz 2014 Exact)
// ====================================================================================

//  Frostbite 2014 原版各向异性粗糙度转换
// 采用 Disney 一样的参数化
void GetAnisotropicAlpha_Frostbite2014(half roughness, half anisotropy, out half alphat, out half alphab)
{
    half alpha = roughness * roughness;
    half aspect = sqrt(1.0h - 0.9h * anisotropy);
    alphat = max(alpha / aspect, 1e-3h); // 沿切线 Tangent 的粗糙度 α_t
    alphab = max(alpha * aspect, 1e-3h); // 沿副切线 Bitangent 的粗糙度 α_b
}

// 各向异性 D 项
// 数学原式: 1 / [ π * αt * αb * ( ( T · H / αt)² + (B · H / αb)² + (N · H)² )² ]
// 令 α2 = αt * αb, 上下同乘 α2 * α2
// 分子 ：(αt * αb)⁴
// 分母 ：PI * αt * αb * [(αb * (T · H))² + (αt * (B · H))² + (αt * ay * (N · H))²]²
// 构造向量 v = (αb * (T·H), αt * (B·H), α2 * (N·H))
half D_GGX_Anisotropic_Frostbite(half alphat, half alphab, half TdotH, half BdotH, half NdotH)
{
    half alpha2 = alphat * alphab;
    half3 v = half3(alphab * TdotH, alphat * BdotH, alpha2 * NdotH);
    half v2 = dot(v, v);
    half d = alpha2 / v2;
    return alpha2 * d * d * (1.0h / PI);
}

// 各向异性 高度相关 Smith V 项 (Heitz 2014 精确版)
// 数学原式: 0.5 / [ (N · L) * sqrt(αt² * (T · V)² + αb² * (B · V)² + (N · V)²) + (N · V)²) * sqrt(αt² * (T · L)² + αb² * (B · L)² + (N · L)²) ]
half V_SmithJoint_GGX_Anisotropic_Frostbite(half alphat, half alphab, 
    half TdotV, half BdotV, half NdotV,half TdotL, half BdotL, half NdotL)
{
    // 利用硬件 length() 直接计算 sqrt(αt² * (T · V)² + αb² * (B · V)² + (N · V)²) + (N · V)²)
    half lambdaV = NdotL * length(half3(alphat * TdotV, alphab * BdotV, NdotV));
    half lambdaL = NdotV * length(half3(alphat * TdotL, alphab * BdotL, NdotL));
    return 0.5h * rcp(lambdaV + lambdaL + 1e-5h);
}