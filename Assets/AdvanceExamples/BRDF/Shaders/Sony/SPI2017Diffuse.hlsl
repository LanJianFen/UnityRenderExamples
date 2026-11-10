#pragma once
// ===================================================
// Sony Pictures Imageworks (SPI) 2017 Diffuse
// ===================================================

TEXTURE2D(_SpecularLut); SAMPLER(sampler_SpecularLut);
// 从 LUT 中同时采样并还原出 E(μ_i), E(μ_o) 以及 E_avg
void SampleSpecularEnergyTerms_LUT(
    half Roughness, half F0_dielectric, half F90_dielectric, 
    half NdotL, half NdotV,
    out half E_i, out half E_o, out half E_avg)
{
    // 第一次采样：U = NdotL, V = roughness -> 获取入射方向 (A_i, B_i, A_avg, B_avg)
    half4 lut_i = SAMPLE_TEXTURE2D_LOD(_SpecularLut, sampler_SpecularLut, half2(NdotL, Roughness), 0);
    // 第二次采样：U = NdotV, V = roughness -> 获取出射视线方向 (A_o, B_o)
    half2 lut_o = SAMPLE_TEXTURE2D_LOD(_SpecularLut, sampler_SpecularLut, half2(NdotV, Roughness), 0).rg;
    // 线性还原特定 F0 / F90 下的高光定向反照率 E(μ_i), E(μ_o) 与半球平均值 E_avg
    E_i   = F0_dielectric * lut_i.r + F90_dielectric * lut_i.g;
    E_o   = F0_dielectric * lut_o.r + F90_dielectric * lut_o.g;
    E_avg = F0_dielectric * lut_i.b + F90_dielectric * lut_i.a;
}


// 版本 A：SPI 2017 线性基底版 (分母为 1 - E_avg，满足漫反射与 base_color 纯线性正比)
// 公式：f_diff = (c / PI) * (1 - E(μ_i)) * (1 - E(μ_o)) / (1 - E_avg)
half3 Diffuse_Coupled_SPI2017_LUT(
    half3 base_color, half roughness, half ior, half metallic, 
    half NdotL, half NdotV)
{
    // 由绝缘体折射率 IOR 计算基础反射率 F0 (例如 IOR=1.5 时 F0=0.04, F90=1.0)
    half r = (ior - 1.0h) / (ior + 1.0h);
    half F0_dielectric  = r * r;
    half F90_dielectric = 1.0h;
    // 查表获取三个能量积分项
    half E_i, E_o, E_avg;
    SampleSpecularEnergyTerms_LUT(roughness, F0_dielectric, F90_dielectric, NdotL, NdotV, E_i, E_o, E_avg);
    // 计算耦合漫反射
    half3 c_diff = base_color * (1.0h - metallic);
    half norm_factor = rcp(max(1.0h - E_avg, 1e-5h));
    
    return c_diff * (1.0h / PI) * (1.0h - E_i) * (1.0h - E_o) * norm_factor;
}
// 版本 B：SPI 2017 完全体内反射吸收版 (分母为 1 - c * E_avg，考虑每次内壁挡回时被基底色素再次吸收)
// 公式：f_diff = (c / PI) * (1 - E(μ_i)) * (1 - E(μ_o)) / (1 - c * E_avg)
half3 Diffuse_CoupledMulti_SPI2017_LUT(
    half3 base_color, half roughness, half ior, half metallic, 
    half NdotL, half NdotV)
{
    half r = (ior - 1.0h) / (ior + 1.0h);
    half F0_dielectric  = r * r;
    half F90_dielectric = 1.0h;
    half E_i, E_o, E_avg;
    SampleSpecularEnergyTerms_LUT(roughness, F0_dielectric, F90_dielectric, NdotL, NdotV, E_i, E_o, E_avg);
    half3 c_diff = base_color * (1.0h - metallic);
    // 注意：这里的分母是 RGB 三通道向量 1 - c_diff * E_avg，会自动产生内反射色彩加深效应！
    half3 norm_factor = rcp(max(half3(1.0h, 1.0h, 1.0h) - c_diff * E_avg, 1e-5h));
    return c_diff * (1.0h / PI) * ((1.0h - E_i) * (1.0h - E_o)) * norm_factor;
}