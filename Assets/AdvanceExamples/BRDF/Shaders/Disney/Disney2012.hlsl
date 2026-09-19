// ===================================================
// Disney 2012
// ===================================================
// 2012 : Disney 的 GTR2 (GGX)
// 分子 : alpha_D ²
// 分母 : PI * ((N · H) ² * (alpha_D ² - 1) + 1)  ²
// Disney 在 D 里的 α_D = roughness², 和 G 项的 α_G 不是同一个
half D_GTR2_Disney(half roughness, half NdotH)
{
    half alpha_D = roughness * roughness;
    half alpha_D2 = alpha_D * alpha_D;
    half denominator = PI * pow(NdotH * NdotH * (alpha_D2 - 1.0f) + 1.0f, 2.0f); // 分母
    half D = alpha_D2 / denominator;
    return D;
}

// Christophe Schlick 在 1994 年提出的通用 Schlick Fresnel，全宇宙的渲染引擎都在用
// F_Schlick = F0 + (1 - F0) *  [1 - (V · H)]⁵
half3 F_Schlick_Approximation(half3 F0, half VdotH)
{
    return F0 + (1.0h - F0) * pow(saturate(1.0h - VdotH), 5.0h);
}

// 绝缘体的 F0,dielectric = 0.08h * specular * lerp((half3)1.0h, chromaticity, specular_tint)
// 金属的    F0,electric   =  lerp(F0_dielectric, base_color, metallic)
half3 F_Schlick_Disney(half3 base_color, half specular, half specular_tint, half metallic, half VdotH)
{
    half luminance = max(dot(base_color, half3(0.2126h, 0.7152h, 0.0722h)),  0.0001h); // 亮度
    half3 chromaticity = base_color / luminance;                                                    // 色相
    half3 F0_dielectric = 0.08h * specular * lerp((half3)1.0h, chromaticity, specular_tint);
    half3 F0 = lerp(F0_dielectric, base_color, metallic);
    half3 F = F_Schlick_Approximation(F0, VdotH);
    return F;
}

// 2012：Disney 分离式 Smith G项
// shadowing : 2 * (N · L) / [ N · L  + sart( α_G² + (N · L)² * (1 - α_G²) ]
// masking : 2 * (N · V) / [ N · V  + sart( α_G² + (N · V)² * (1 - α_G²) ]
// V = G1(L) * G1(V) / [4 * (N · L) * (N · V)] =
// rcp( [ N · L  + sart( α_G² + (N · L)² * (1 - α_G²) ] * [ N · V  + sart( α_G² + (N · V)² * (1 - α_G²) ])
// GTR2(GGX) 是单重弹射模型，掠射角会偏暗，Burley 重新定义了 α_G = [(roughness + 1) / 2]²
half V_SmithSeparable_GTR2_Disney(half roughness, half NdotL, half NdotV)
{
    half alpha_G = (roughness + 1.0h) * (roughness + 1.0h) / 4.0h;
    half alpha_G2 = alpha_G * alpha_G;
    half G1_light_denominator = NdotL + sqrt(alpha_G2 + NdotL * NdotL * (1.0h - alpha_G2));
    half G1_view_denominator = NdotV + sqrt(alpha_G2 + NdotV * NdotV * (1.0h - alpha_G2));
    half V = rcp(G1_light_denominator * G1_view_denominator);
    return V;
}