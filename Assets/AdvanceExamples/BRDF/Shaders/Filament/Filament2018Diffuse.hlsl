#pragma once
// ===================================================
// Filament 2018 Diffuse
// ===================================================

// 低配移动端 (Lambert 漫反射)
// Filament 官方白皮书 Section 4.4 (Listing 7)
half3 Diffuse_Lambert_Filament2018(half3 base_color, half metallic)
{
    half3 diffuse_color = base_color * (1.0h - metallic);
    return diffuse_color * (1.0h / PI);
}

// Filament 用的是 Alpha
half3 Diffuse_Filament2018(half3 base_color, half roughness, half metallic, half NdotL, half NdotV, half LdotH)
{
    half3 diffuse_color = base_color * (1.0h - metallic);
    half alpha = roughness * roughness;
    half FD90 = 0.5h + 2.0h * alpha * (LdotH * LdotH);
    
    half light_scatter = F_Schlick_Approximation(1.0h, FD90, NdotL);
    half view_scatter = F_Schlick_Approximation(1.0h, FD90, NdotV);
    
    return diffuse_color * (1.0h / PI) * light_scatter * view_scatter;
}
