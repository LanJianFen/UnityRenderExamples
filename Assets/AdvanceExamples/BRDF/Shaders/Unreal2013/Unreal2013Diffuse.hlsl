#pragma once
// ===================================================
// Unreal 2013 Diffuse
// ===================================================

// 均匀漫反射, N · V = 0，能量溢出
half3 Diffuse_Unreal(half3 base_color, half metallic)
{
    half3 diffuse_color = base_color * (1.0h - metallic);
    return diffuse_color * (1.0h / PI);
}