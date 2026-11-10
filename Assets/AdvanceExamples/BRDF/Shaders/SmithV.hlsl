#pragma once
// 2007 对 GGX(GTR2) 推导出的精确 G项
// Bruce Walter 在物理上给 α 的严谨定义是：微表面山坡斜率的均方根（RMS Slope）。
// shadowing : 2 * (N · L) / [ N · L  + sart( α² + (N · L)² * (1 - α²) ]
// masking : 2 * (N · V) / [ N · V  + sart( α² + (N · V)² * (1 - α²) ]
// V = G1(L) * G1(V) / [4 * (N · L) * (N · V)] =
// rcp( [ N · L  + sart( α² + (N · L)² * (1 - α²) ] * [ N · V  + sart( α² + (N · V)² * (1 - α²) ])
// V 的 [4 * (N · L) * (N · V)] 是 BRDF 的雅可比矩阵缩放系数
half V_SmithSeparable_GGX(half rms_slope, half NdotL, half NdotV)
{
    half alpha = rms_slope * rms_slope;
    half alpha2 = alpha * alpha;
    half G1_light_denominator = NdotL + sqrt(alpha2 + NdotL * NdotL * (1.0h - alpha2));
    half G1_view_denominator = NdotV + sqrt(alpha2 + NdotV * NdotV * (1.0h - alpha2));
    half V = rcp(G1_light_denominator * G1_view_denominator);
    return V;
}

// 纯正 分离式 Smith G项
// 部分对物理要求极严的渲染管线，α_G 严格等于 roughness²
// 不用 Disney 的那个魔改版 α_G, 强制 D 项和 G 项一起使用同一个 α
// 用 Kulla-Conty 进行补偿
half V_SmithSeparable_GGX_Exact(half roughness, half NdotL, half NdotV)
{
    half alpha = roughness * roughness;
    half alpha2 = alpha * alpha;
    half G1_light_denominator = NdotL + sqrt(alpha2 + NdotL * NdotL * (1.0h - alpha2));
    half G1_view_denominator = NdotV + sqrt(alpha2 + NdotV * NdotV * (1.0h - alpha2));
    half V = rcp(G1_light_denominator * G1_view_denominator);
    return V;
}

// 2014 纯正 高度相关 Smith G 项
//  G(L,V) = 2 * (N · L) * (N · V) / [(N · V) * Al + (N · L) * Av]
// Al = sqrt(α² + (1 - α²) * (N · L)²)
// Av = sqrt(α² + (1 - α²) * (N · V)²)
// V = G(L,V) / [4 * (N · L) * (N · V)] = rcp(2 * [(N · V) Al + (N · L) Av])
half V_SmithJoint_GGX_Exact(half roughness, half NdotL, half NdotV)
{
    half alpha = roughness * roughness;
    half alpha2 = alpha * alpha;
    half Al = sqrt(alpha2 + (1.0h - alpha2) * NdotL * NdotL);
    half Av = sqrt(alpha2 + (1.0h - alpha2) * NdotV * NdotV);
    half G_denominator = NdotV * Al + NdotL * Av;
    half V = rcp(2.0h * G_denominator);
    return V;
}

// Kelemen 分离式近似
// V = G1(L) * G1(V) / [4 * (N · L) * (N · V)]
// 很多时候和 1 / [4 * (V · H)²] 长得像
half V_Kelemen(half VdotH)
{
    half V = rcp(4.0h * VdotH * VdotH + 1e-5h); 
    return V;
}
