#pragma once
// ===================================================
// glTF 2017 Diffuse
// ===================================================
// 均匀漫反射，乘 (1 - F高光)
half3 Diffuse_glTF2017(half3 base_color, half metallic, half3 F_specular)
{
    half3 c_diff = base_color * (1.0h - metallic);
    return (1.0h - F_specular) * c_diff * (1.0h / PI);
}