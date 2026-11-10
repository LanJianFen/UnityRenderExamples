#pragma once
// ===================================================
// OpenPBR Surface (v1.0 / v1.1 Specification, 2024+)
// Autodesk (Arnold/Maya) & Adobe (Substance 3D) 联合标准
// ===================================================


// ===================================================
// OpenPBR: Coat-on-Metal (或金属处于非空气环境介质中) 的 F82 修正实现
// ===================================================
// 1. 辅助函数：根据金属在空气中的基础反射率 F0_air (即 base_color) 与外部环境折射率 ior_extern，
//    通过等效折射率反演并代数消去奇点，计算出金属在当前外部介质 (如清漆 1.5 或水 1.33) 下的新起点 F0'
//    数学推导：n_eff = (1 + sqrt(F0)) / (1 - sqrt(F0))
//              F0'   = ((n_eff - ior_ext) / (n_eff + ior_ext))^2
//    通分消去 (1 - sqrt(F0)) 后，彻底避免 F0 = 1.0 时的除零 NaN 风险：
half3 ComputeF0_Metal_InMedium_OpenPBR(half3 F0_air, half ior_extern)
{
    half3 sqrt_F0 = sqrt(saturate(F0_air));
    half  one_minus_n = 1.0h - ior_extern;
    half  one_plus_n  = 1.0h + ior_extern;
    half3 numerator   = one_minus_n + one_plus_n * sqrt_F0;
    half3 denominator = one_plus_n  + one_minus_n * sqrt_F0;
    half3 r = numerator / max(denominator, 1e-5h);
    return r * r;
}
// 2. 支持外部介质折射率跳变 (Coat-on-Metal) 的 OpenPBR 金属 F82 函数
//    - base_color : 金属在空气中的 0度反射率 F0_air
//    - tint_82    : 82度拟布儒斯特凹陷染色系数 (即 OpenPBR 的 specular_color)
//    - specular   : 全局高光权重 (即 OpenPBR 的 specular_weight)
//    - ior_extern : 外部包裹介质的折射率 (空气传 1.0h；清漆通常传 1.5h；水传 1.33h)
//    - VdotH      : 入射角余弦 cos(theta_i)
half3 F_Metal_F82_Coat_OpenPBR(half3 base_color, half3 tint_82, half specular, half ior_extern, half VdotH)
{
    half mu = saturate(VdotH);
    
    // 第一步：将空气中的 base_color 转换为外部介质 ior_extern 下的真实交界面起点 F0'
    // (若 ior_extern == 1.0h，F0_medium 精确等于 base_color)
    half3 F0_medium = ComputeF0_Metal_InMedium_OpenPBR(base_color, ior_extern);
    half3 F90 = (half3)1.0h;
    // 第二步：以修正后的 F0_medium 为起点，计算基准 Schlick 曲线与 82度 (mu = 1/7) 基准值
    half3 F_Schlick_mu = F_Schlick_Approximation(F0_medium, F90, mu);
    half3 F_Schlick_82 = F_Schlick_Approximation_82(F0_medium);
    // 第三步：减去 7 次方拟布儒斯特角凹陷修正项
    // k = (7^7) / (6^6) = 823543.0 / 46656.0 ≈ 17.6513846
    const half k = 17.6513846h;
    half3 b = k * F_Schlick_82 * ((half3)1.0h - tint_82);
    half3 fresnel_dip = b * mu * pow(1.0h - mu, 6.0h);
    // 第四步：乘上 OpenPBR 的全局高光权重 specular
    half3 F_82 = saturate(F_Schlick_mu - fresnel_dip);
    return saturate(specular * F_82);
}


// 完整的双介质通用 OpenPBR F 项 (绝缘体与金属均支持外部清漆/水体折射率 ior_extern)
half3 F_OpenPBR2024_Full(half3 base_color, half3 specular_tint, half specular, half ior_intern, half ior_extern, half metallic, half VdotH)
{
    // 绝缘体分支：传入相对折射率 ior = ior_intern / ior_extern
    half relative_ior = ior_intern / max(ior_extern, 1e-5h);
    half3 F_dielectric = F_Dielectric_Exact_OpenPBR(specular_tint, specular, relative_ior, VdotH);
    // 金属分支：传入外部介质折射率 ior_extern 进行 Coat-on-Metal 起点修正
    half3 F_metal = F_Metal_F82_Coat_OpenPBR(base_color, specular_tint, specular, ior_extern, VdotH);
    return lerp(F_dielectric, F_metal, metallic);
}
