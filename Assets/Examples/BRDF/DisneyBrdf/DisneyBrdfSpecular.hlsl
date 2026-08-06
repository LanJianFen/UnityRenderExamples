// 绝缘体的 F0,dielectric = 0.08h * specular * lerp((half3)1.0h, chromaticity, specular_tint)
// 金属的    F0,electric   =  lerp(F0_dielectric, base_color, metallic)
half3 F_Schlick_Disney(half3 base_color, half specular, half specular_tint, half metallic, half VdotH)
{
    half luminance = dot(base_color, half3(0.2126h, 0.7152h, 0.0722h)); // 亮度
    half3 chromaticity = base_color / luminance;                                // 色相
    half3 F0_dielectric = 0.08h * specular * lerp((half3)1.0h, chromaticity, specular_tint);
    half3 F0 = lerp(F0_dielectric, base_color, metallic);
    half3 F = F0 + (1.0h - F0) * pow(1.0h - VdotH,5);
    return F;
}

// GGX 法线分布函数 (D项)
// 分子 : alpha ²
// 分母 : PI * ((N · H) ² * (alpha ² - 1) + 1)  ²
half D_GGX_Disney(half roughness, half NdotH)
{
    half alpha = roughness * roughness;
    half alpha2 = alpha * alpha;
    half denominator = PI * pow(NdotH * NdotH * (alpha2 - 1.0f) + 1.0f, 2.0f); // 分母
    half D = alpha2 / denominator;
    return D;
}

// 分离式 Smith G项
// shadowing : (N · L) / [(N · L)  * (1.0h - k) + k]
// masking    : (N · V) / [(N · V)  * (1.0h - k) + k]
// V = G1(L) * G1(V) / [4.0 * (N · L) * (N · V)] =
// rcp(4.0h * [(N · L)  * (1.0h - k) + k] * [(N · V)  * (1.0h - k) + k])
// k在物理上是 roughness / 2，但是因为这个分离模型忽略了光线的弹射，所以
half V_SmithJoint_Schlick(half roughness, half NdotL, half NdotV)
{
    half k = (roughness + 1.0h) * (roughness + 1.0h) / 8.0h;
    half G1_light_denominator = NdotL * (1.0h - k) + k;
    half G1_view_denominator = NdotV * (1.0h - k) + k;
    half V = rcp(4.0h * G1_light_denominator * G1_view_denominator);
    return V;
}