// ===================================================
// Unreal 2013
// ===================================================
// Unreal 2013 也使用的 Disney 的 D 项, α_D = roughness²
half D_GGX_Unreal(half roughness, half NdotH)
{
    half alpha_D = roughness * roughness;
    half alpha_D2 = alpha_D * alpha_D;
    half denominator = PI * pow(NdotH * NdotH * (alpha_D2 - 1.0f) + 1.0f, 2.0f); // 分母
    half D = alpha_D2 / denominator;
    return D;
}

// F_Schlick = F0 + (1 - F0) *  [1 - (V · H)]⁵
// Karis 借用了 Sébastien Lagarde 的发现, 5 次方曲线可以用以" 2 为底的指数函数"极其完美地拟合
half3 F_Lagarde_Approximation(half3 F0, half VdotH)
{
    return F0 + (1.0 - F0) * exp2( (-5.55473h * VdotH - 6.98316h) * VdotH );
}

half3 F_Schlick_Unreal(half3 base_color, half specular, half metallic, half VdotH)
{
    half3 F0_dielectric = 0.08h * specular;
    half3 F0 = lerp(F0_dielectric, base_color, metallic);
    half3 F = F_Lagarde_Approximation(F0, VdotH);
    return F;
}

// 2013：Epic 分离式 Smith Schlick G项
// shadowing : (N · L) / [(N · L)  * (1 - k) + k]
// masking    : (N · V) / [(N · V)  * (1 - k) + k]
// V = G1(L) * G1(V) / [4 * (N · L) * (N · V)] =
// rcp(4 * [(N · L)  * (1 - k) + k] * [(N · V)  * (1.0h - k) + k])
// Brian Karis 做了一系列数学推演和曲线最小二乘法拟合，得到 k = α_G / 2。
// Brian Karis 对直接光的 α_G 用了 Burley 的做法，但是 IBL 回归到了 roughness²
half V_SmithSeparable_GGX_Unreal(half roughness, half NdotL, half NdotV)
{
    half alpha_G = (roughness + 1.0h) * (roughness + 1.0h) / 4.0h;;
    half k = alpha_G / 2.0h;
    half G1_light_denominator = NdotL * (1.0h - k) + k;
    half G1_view_denominator = NdotV * (1.0h - k) + k;
    half V = rcp(4.0h * G1_light_denominator * G1_view_denominator);
    return V;
}