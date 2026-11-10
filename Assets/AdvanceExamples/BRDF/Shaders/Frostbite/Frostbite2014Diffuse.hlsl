#pragma once
// =====================================================================================
// Frostbite 2014 Diffuse
// =====================================================================================
// Disney 2014 Diffuse 在 Disney 2012的基础上改进

// Disney 在 r = 1， N · V = 0 的情况下，半球积分 是 1.51，能量超标了
//          在 r = 0,  N · V = 0的情况下，半球积分 是 0.46，加上高光反射的 1, 能量超标了
// 要么对整体进行控制，要么对 FD90 进行控制
//
// 对于 Disney 的漫反射，Frostbite 增加了 2 个新参数分布控制整体和 FD90
// FD90         = B(roughness) + 2 * roughness * (L · H)²
// Diffuse_Brdf = K(roughness) * c / PI * light_scatter * view_scatter

// r = 1，N · V = 0，能量多了 51%, K(1) = 1 / 1.51; 从 N · V = 1 -> 0 的逆反射曲线保留, B(1) = 0.5
// r = 0，N · V = 0 的时候，高光占了 100 %, 但是 K(0) 显然不能是 0， 所以 B(0) = 0; 
//          N · V = 1 的时候，能量大概是 0.95，加上高光的 0.04，差不多是1，所以 K(0) = 1
half F_Schlick_Scalar(half f90, half cosTheta)
{
    return lerp(1.0h, f90, pow(saturate(1.0h - cosTheta), 5.0h));
}

half3 Diffuse_Frostbite2014(half3 base_color, half roughness, half metallic, half NdotL, half NdotV, half LdotH)
{
    half energy_bias = lerp(0.0h, 0.5h, roughness);
    half energy_factor = lerp(1.0h, 1.0h / 1.51h, roughness);
    
    half FD90 = energy_bias + 2.0h * roughness * (LdotH * LdotH);
    
    half light_scatter = F_Schlick_Scalar(FD90, NdotL);
    half view_scatter  = F_Schlick_Scalar( FD90, NdotV);
    
    half3 diffuse_color = base_color * (1.0h - metallic);
    return energy_factor * diffuse_color * INV_PI * light_scatter * view_scatter;
}
