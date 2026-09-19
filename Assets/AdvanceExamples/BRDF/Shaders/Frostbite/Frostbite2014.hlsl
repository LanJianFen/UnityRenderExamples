// ===================================================
// Frostbite 2014
// ===================================================
// Frostbite 2014 也使用的 Disney 的 D 项, α_D = roughness²
half D_GGX_Frostbite(half roughness, half NdotH)
{
    half alpha_D = roughness * roughness;
    half alpha_D2 = max(alpha_D * alpha_D, 1e-5);
    half denominator = PI * pow(NdotH * NdotH * (alpha_D2 - 1.0f) + 1.0f, 2.0f); // 分母
    half D = alpha_D2 / denominator;
    return D;
}

// F_Schlick = F0 + (1 - F0) *  [1 - (V · H)]⁵
// Sébastien Lagarde 发现 5 次方曲线可以用以" 2 为底的指数函数"极其完美地拟合
half3 F_Lagarde_Approximation(half3 F0, half VdotH)
{
    return F0 + (1.0 - F0) * exp2( (-5.55473h * VdotH - 6.98316h) * VdotH );
}

half3 F_Schlick_Frostbite(half3 base_color, half reflectance, half metallic, half VdotH)
{
    half3 F0_dielectric = 0.16h * reflectance * reflectance;
    half3 F0 = lerp(F0_dielectric, base_color, metallic);
    half3 F = F_Lagarde_Approximation(F0, VdotH);
    return F;
}

// 2014 纯正 高度相关 Smith G 项
//  G(L,V) = 2 * (N · L) * (N · V) / [(N · V) * Al + (N · L) * Av]
// Al = sqrt(α² + (1 - α²) * (N · L)²)
// Av = sqrt(α² + (1 - α²) * (N · V)²)
// V = G(L,V) / [4 * (N · L) * (N · V)] = rcp(2 * [(N · V) Al + (N · L) Av])
half V_SmithJoint_GGX_Frostbite(half roughness, half NdotL, half NdotV)
{
    half alpha = roughness * roughness;
    half alpha2 = alpha * alpha;
    half Al = sqrt(alpha2 + (1.0h - alpha2) * NdotL * NdotL);
    half Av = sqrt(alpha2 + (1.0h - alpha2) * NdotV * NdotV);
    half G_denominator = NdotV * Al + NdotL * Av;
    half V = rcp(2.0h * G_denominator);
    return V;
}
