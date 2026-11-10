#pragma once
// ===================================================
// Disney 2012 Isotropic
// ===================================================
// 2012 : Disney 的 GTR2 (GGX)
// 分子 : alpha_D ²
// 分母 : PI * ((N · H) ² * (alpha_D ² - 1) + 1)  ²
// Disney 在 D 里的 α_D = roughness², 和 G 项的 α_G 不是同一个
half D_GTR2_Disney(half roughness, half NdotH)
{
    half alpha_D = max(roughness * roughness, 0.001h);
    half alpha_D2 = alpha_D * alpha_D;
    half denominator = PI * pow(NdotH * NdotH * (alpha_D2 - 1.0f) + 1.0f, 2.0f); // 分母
    half D = alpha_D2 / denominator;
    return D;
}

// 2012：Disney 分离式 Smith G项
// shadowing : 2 * (N · L) / [ N · L  + sqrt( α_G² + (N · L)² * (1 - α_G²) ]
// masking : 2 * (N · V) / [ N · V  + sqrt( α_G² + (N · V)² * (1 - α_G²) ]
// V = G1(L) * G1(V) / [4 * (N · L) * (N · V)] =
// rcp( [ N · L  + sqrt( α_G² + (N · L)² * (1 - α_G²) ] * [ N · V  + sqrt( α_G² + (N · V)² * (1 - α_G²) ])
// GTR2(GGX) 是单重弹射模型
// 为了压暗 roughness→0 光滑材质在掠射角点光源下高达上万倍的极端高光过曝，Burley 重新定义了 α_G = [(roughness + 1) / 2]²
half V_SmithSeparable_GTR2_Disney(half roughness, half NdotL, half NdotV)
{
    half alpha_G = (roughness + 1.0h) * (roughness + 1.0h) / 4.0h;
    half alpha_G2 = alpha_G * alpha_G;
    half G1_light_denominator = NdotL + sqrt(alpha_G2 + NdotL * NdotL * (1.0h - alpha_G2));
    half G1_view_denominator = NdotV + sqrt(alpha_G2 + NdotV * NdotV * (1.0h - alpha_G2));
    half V = rcp(G1_light_denominator * G1_view_denominator);
    return V;
}