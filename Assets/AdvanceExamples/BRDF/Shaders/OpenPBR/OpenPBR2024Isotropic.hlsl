#pragma once
// ===================================================
// OpenPBR Surface (v1.0 / v1.1 Specification, 2024+)
// Autodesk (Arnold/Maya) & Adobe (Substance 3D) 联合标准
// ===================================================


// D 项：纯正各向同性 GGX (Trowbridge-Reitz)，α = roughness²
half D_GGX_OpenPBR(half roughness, half NdotH)
{
    half alpha = roughness * roughness;
    half alpha2 = max(alpha * alpha, 1e-5h);
    half d = (NdotH * alpha2 - NdotH) * NdotH + 1.0h;
    return alpha2 / (PI * d * d);
}

//  V 项：纯正高度相关 (Height-Correlated) Smith-GGX
half V_SmithJoint_GGX_OpenPBR(half roughness, half NdotL, half NdotV)
{
    half alpha = roughness * roughness;
    half alpha2 = max(alpha * alpha, 1e-5h);
    half Al = NdotV * sqrt(NdotL * (NdotL - NdotL * alpha2) + alpha2);
    half Av = NdotL * sqrt(NdotV * (NdotV - NdotV * alpha2) + alpha2);
    return 0.5h * rcp(Al + Av);
}

// ===================================================
// OpenPBR F 项：绝缘体 (Dielectric) 与 金属 (Metal F82-Tint)
// ===================================================

// [绝缘体分支 - 方式 1：OpenPBR 官方 Exact Dielectric Fresnel + IOR 调制]
// OpenPBR 规范 Equation (modulated_ior)：通过 specular 权重调制 F0 并反推有效折射率 eta_prime
half3 F_Dielectric_Exact_OpenPBR(half3 specular_tint, half specular, half ior, half VdotH)
{
    // 1. 计算基准 F0_physics = ((ior - 1) / (ior + 1))^2
    half r = (ior - 1.0h) / (ior + 1.0h);
    half F_s = r * r;
    
    // 2. 用 specular (即 specular_weight) 调制 F_s，并反推调制后的有效相对折射率 eta_prime
    half eps = sign(ior - 1.0h) * sqrt(saturate(specular * F_s));
    half eta_prime = (1.0h + eps) / max(1.0h - eps, 1e-5h);
    
    // 3. 代入精确无偏振绝缘体菲涅尔方程 F_dielectric(mu, eta_prime)
    half c = saturate(VdotH);
    half g2 = eta_prime * eta_prime + c * c - 1.0h;
    
    half F = 1.0h; // 若 g2 < 0 则发生全反射 (TIR)，反射率为 1.0
    if (g2 >= 0.0h)
    {
        half g = sqrt(g2);
        half term1 = (g - c) / (g + c);
        half term2 = (c * (g + c) - 1.0h) / (c * (g - c) + 1.0h);
        F = 0.5h * (term1 * term1) * (1.0h + term2 * term2);
    }
    
    // 4. OpenPBR 规定：从外部入射的绝缘体反射光整体乘以 specular_color (即 specular_tint)
    F = F * specular_tint;
    return F;
}

half3 F_Dielectric_Exact_OpenPBR(half3 specular_tint, half specular, half ior_intern, half ior_extern, half VdotH)
{
    // 1. 计算原始相对折射率 eta = n_int / n_ext 及基准正视反射率 F_s
    half eta = ior_intern / max(ior_extern, 1e-5h);
    half r = (eta - 1.0h) / (eta + 1.0h);
    half F_s = r * r;
    
    // 2. 用 specular 权重调制 F_s，并反推等效的新相对折射率 eta_prime
    //    - 当 specular -> 0 时，eps -> 0，eta_prime -> 1.0 (无折射率跳变，后续精确菲涅尔在所有角度自动归零)
    //    - 当 ior_intern < ior_extern (如清漆下方的底层材质) 时，sign 为负，eta_prime < 1.0，可触发全反射
    half eps = sign(eta - 1.0h) * sqrt(saturate(specular * F_s));
    half eta_prime = (1.0h + eps) / max(1.0h - eps, 1e-5h);
    
    // 3. 将等效相对折射率 eta_prime 代入精确无偏振麦克斯韦菲涅尔方程
    half c = saturate(VdotH);
    half g2 = eta_prime * eta_prime + c * c - 1.0h;
    
    half F_uncolored = 1.0h; 
    if (g2 >= 0.0h) // 若 g2 < 0，说明 eta_prime < 1.0 且入射角超过临界角，直接保持 1.0 (全反射 TIR)
    {
        half g = sqrt(g2);
        half term1 = (g - c) / (g + c);
        half term2 = (c * (g + c) - 1.0h) / (c * (g - c) + 1.0h);
        F_uncolored = 0.5h * (term1 * term1) * (1.0h + term2 * term2);
    }
    
    // 4. 乘上绝缘体高光染色
    return F_uncolored * specular_tint;
}

// [绝缘体分支 - 方式 2：实时渲染 Schlick 近似版]
// 当使用 Schlick 近似上面的调制折射率曲线时，F0_modulated = saturate(specular * F_s)
half3 F_Dielectric_Schlick_OpenPBR(half3 specular_tint, half specular, half ior, half VdotH)

{
    half r = (ior - 1.0h) / (ior + 1.0h);
    half F0 = saturate(specular * (r * r));
    half F_uncolored = F0 + (1.0h - F0) * pow(saturate(1.0h - VdotH), 5.0h);
    half3 F = F_uncolored * specular_tint;
    return F;
}

// 辅助函数：计算 mu_bar = 1/7 (约 81.79度) 处的基准 Schlick 数值
// pow(1 - 1/7, 5) = (6/7)^5 = 7776.0 / 16807.0 ≈ 0.46266437
half3 F_Schlick_Approximation_82(half3 F0)
{
    half3 F90 = (half3)1.0h;
    return F0 + (F90 - F0) * 0.46266437h;
}

// [金属分支：OpenPBR 官方 F82-Tint 模型]
// 在 OpenPBR 中，“一鱼两吃”：
//   - F0  由 base_color (乘以 base_weight) 提供
//   - T82 直接复用 specular_tint (即官方的 specular_color)
//   - 最终结果整体乘以 specular (即官方的 specular_weight)
half3 F_Metal_F82_OpenPBR(half3 base_color, half3 tint_82, half specular, half VdotH)
{
    half3 F0 = base_color;
    half3 F90 = (half3)1.0h;
    
    // 1. 基准 Schlick 曲线 F_Schlick(mu) 与 82度基准值 F_Schlick(1/7)
    half3 F_Schlick_mu = F_Schlick_Approximation(F0, F90, VdotH);
    half3 F_Schlick_82 = F_Schlick_Approximation_82(F0);
    
    // 2. 7次方修正项：k = 1 / [ (1/7) * (6/7)^6 ] = (7^7) / (6^6) = 823543.0 / 46656.0 ≈ 17.6513846
    const half k = 17.6513846h;
    half3 fresnel_dip = k * F_Schlick_82 * ((half3)1.0h - tint_82) * VdotH * pow(1.0h - VdotH, 6.0h);
    
    // 3. OpenPBR 规范：F_metal(mu) = specular_weight * F_82(mu)
    half3 F_82 = saturate(F_Schlick_mu - fresnel_dip);
    half3 F = saturate(specular * F_82);
    return F;
}

// OpenPBR 完整 F 项合并 (按 metallic 即 base_metalness 在绝缘体Slab与金属Slab之间统计混合)
// base_weight
half3 F_OpenPBR2024(half3 base_color, half3 specular_tint, half specular, half ior, half metallic, half VdotH)
{
    // 绝缘体可使用精确版 F_Dielectric_Exact_OpenPBR 或 Schlick 版 F_Dielectric_Schlick_OpenPBR
    half3 F_dielectric = F_Dielectric_Exact_OpenPBR(specular_tint, specular, ior, VdotH);
    half3 F_metal = F_Metal_F82_OpenPBR(base_color, specular_tint, specular, VdotH);
    half3 F = lerp(F_dielectric, F_metal, metallic);
    return F;
}