#pragma once
// ===================================================
// glTF  Extensions Diffuse
// ===================================================

// 因为 2021 版允许把非金属的高光染成彩色（比如染成纯红色 F_dielectric = (0.04, 0, 0)
// 如果直接用向量 (1 − F_dielectric) 去乘漫反射，会导致漫反射被扣掉红色而变成诡异的“青绿色”
// 因此 glTF 2021 规范强制规定：扣除漫反射能量时，必须取非金属菲涅尔 RGB 三个通道的最大值标量 1.0 - max3(F_dielectric)！
half3 Diffuse_glTF2021(half3 base_color, half metallic, half3 F_dielectric)
{
    half max_F_dielectric = max(F_dielectric.r, max(F_dielectric.g, F_dielectric.b));
    half3 diffuse_color = base_color * (1.0h - metallic);
    return (1.0h - max_F_dielectric) * diffuse_color * (1.0h / PI);
}