#pragma once
// ===================================================
// Sony Pictures Imageworks (SPI) 2017 Fresnel
// ===================================================
// 绝缘体精确菲涅尔 (由相对折射率 ior 驱动，支持全反射 TIR)
half3 F_Dielectric_Exact_SPI2017(half ior, half VdotH)
{
    half c = saturate(VdotH);
    half g2 = ior * ior + c * c - 1.0h;
    if (g2 < 0.0h) return (half3)1.0h; // 全反射 (Total Internal Reflection)

    half g = sqrt(g2);
    half term1 = (g - c) / (g + c);
    half term2 = (c * (g + c) - 1.0h) / (c * (g - c) + 1.0h);
    half F = 0.5h * (term1 * term1) * (1.0h + term2 * term2);
    return (half3)F;
}

// 金属精确菲涅尔：Gulbrandsen 2014 "Artist Friendly Metallic Fresnel" (F82-Tint 的前身！)
// r 应该是 F0，指定 F0，反向算出金属折射率里的 n 和 k，代入麦克斯韦
half3 F_Metal_Gulbrandsen_SPI2017(half3 base_color, half3 edge_tint, half VdotH)
{
    // 限制 r 最高为 0.999，防止 (1 - sqrt(r)) 或 (1 - r) 触发除零
    half3 r = clamp(base_color, 0.0h, 0.999h);
    half3 g = saturate(edge_tint);
    half3 sqrt_r = sqrt(r);

    // 第一步：由 (r, g) 反推复折射率的实部 n 和 虚部平方 k²
    half3 n_min = (1.0h - r) / (1.0h + r);
    half3 n_max = (1.0h + sqrt_r) / (1.0h - sqrt_r);
    half3 n = lerp(n_max, n_min, g); // n = g * n_min + (1 - g) * n_max
    half3 k2 = ((n + 1.0h) * (n + 1.0h) * r - (n - 1.0h) * (n - 1.0h)) / (1.0h - r);

    // 第二步：代入无偏振导体菲涅尔近似方程 F = 0.5 * (Rs + Rp)
    half c = saturate(VdotH);
    half c2 = c * c;
    half3 n2_plus_k2 = n * n + k2;
    half3 two_n_c = 2.0h * n * c;

    half3 rs_num = n2_plus_k2 - two_n_c + c2;
    half3 rs_den = n2_plus_k2 + two_n_c + c2;
    half3 Rs = rs_num / rs_den;

    half3 rp_num = n2_plus_k2 * c2 - two_n_c + 1.0h;
    half3 rp_den = n2_plus_k2 * c2 + two_n_c + 1.0h;
    half3 Rp = rp_num / rp_den;

    return saturate(0.5h * (Rs + Rp));
}

// SPI 2017 统一 F 项封装
half3 F_SPI2017(half3 base_color, half3 edge_tint, half ior, half metallic, half VdotH)
{
    half3 F_dielectric =  F_Dielectric_Exact_SPI2017(ior, VdotH);
    half3 F_metal      = F_Metal_Gulbrandsen_SPI2017(base_color, edge_tint, VdotH);
    return lerp(F_dielectric, F_metal, metallic);
}