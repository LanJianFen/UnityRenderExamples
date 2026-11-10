#pragma once
// ===================================================
// Unreal 2022 Diffuse
// ===================================================

TEXTURE2D(_BrdfEnergyLut);SAMPLER(sampler_BrdfEnergyLut_LinearClamp);
// 从预计算 LUT 中计算 UE5 的漫反射和多重弹射能量守恒乘数
// Diffuse : 1 - max(Espec)
// Multi : 1 + F0 * (1 - Eo) / Eo
// 暂时放在这个文件里，以后到能量补偿的时候再换地方
void ComputeGGXSpecEnergyTerms_Unreal2022(half Roughness, half NoV, half3 F0, half3 F90, out half  OutDiffEnergyPreservation, out half3 OutSpecEnergyConservation)
{
    half2 AB = SAMPLE_TEXTURE2D_LOD(_BrdfEnergyLut, sampler_BrdfEnergyLut_LinearClamp, half2(NoV, Roughness), 0).rg;
    half E_o = max(AB.x + AB.y, 1e-5h);
    // ComputeEnergyConservation (Turquin 2019): 补回高粗糙度下微表面多次弹射丢失的高光能量
    OutSpecEnergyConservation = 1.0h + F0 * ((1.0h - E_o) / E_o);
    // ComputeEnergyPreservation: 扣除被顶层高光反射走的能量 E_spec，剩余部分透射给底层漫反射
    half3 E_spec = F0 * AB.x + F90 * AB.y;
    OutDiffEnergyPreservation = 1.0h - max(E_spec.r, max(E_spec.g, E_spec.b));
}

// UE5 Oren-Nayar 漫反射
// 经典 Oren-Nayar 模型，省略了 Oren-Nayar 完整公式的多重散射和第三个基底
// Oren-Nayar 是基于高斯分布的各向同性微表面模型，但是因为没有解析解，所以中间做了很多简化，属于理论很完美，但是计算却有瑕疵
// 基底 A : 1 - 0.5 * σ² / (σ² + 0.33)
// 基底 A 是母积分方程对方位角积分后的第一部分I1，再和高斯分布（各向同性只和天顶角有关）进行天顶角积分，近似为一个均匀基底（但是严格的结果并不是）
// 基底 B : B1 * B2 * B3
// B1 : 0.45h * σ² / (σ² + 0.09h) , B2 = max(0, cos(φi - Φo), B3 = sinα tanβ (α = max(θi, θo), β = min(θi, θo))
// B1 : 与基底 A 的均衡系数, B2 : 顺光程度, B3: 逆反射开关
float3 DiffuseOrenNayar_Unreal2022(float3 DiffuseColor, float Roughness, float NoV, float NoL, float VoH )
{
    float a = Roughness * Roughness;
    //Gotanda 在 2012 年通过数值拟合，找出了将高光微表面粗糙度 α ∈[0,1] 转换为 Oren-Nayar 高斯标准差 σ 的映射关系：s = a / (1.29 + 0.5 * a)
    // Brian Karis 在实现时发现：如果保留这个分母，当美术把材质面板上的 Roughness 拉满到 1.0 时，s 最大只有 0.558，s2 最大只有 0.31
    // 这会导致即便 Roughness = 1，材质看起来也只比 Lambert 稍微平一点点，粗糙度的视觉动态范围被压缩得太厉害了。所以他干脆注释掉了这个分母
    float Sigma = a;// / ( 1.29 + 0.5 * a ); 
    float Sigma2 = Sigma * Sigma;
    float VoL = 2.0h * VoH * VoH - 1.0h;  
    float Cosri = VoL - NoV * NoL;
    float A = 1.0h - 0.5h * Sigma2 / (Sigma2 + 0.33h);
    float B = 0.45h * Sigma2 / (Sigma2 + 0.09h);
    float C1 = A;
    float C2 = B * Cosri * ( Cosri >= 0.0h ? rcp( max( NoL, NoV ) ) : 1.0h );
    // 为了快速补充多重散射的能量，Brian Karis 在最后硬乘了一个随粗糙度线性增长的经验放大系数：1 + Roughness * 0.5
    return DiffuseColor / PI * ( C1 + C2 ) * ( 1.0h + Roughness * 0.5h );
}

// UE5 Chan 漫反射
// Chan 漫反射是在离线光线追踪计算出三维表，根据三维表进行拟合
// 是 GGX 漫反射分布，和高光统一；并且是多重弹射模型 
// Fd: Chan 发现在光滑和粗糙的情况下，出现了不同的特性，所以分为粗糙基底和光滑基底
// Fb: 边缘逆反射的主力，虽然Fd在边缘也能贡献逆反射，但是 Chan 是一种拟合，谁贡献逆反射其实没什么道理

half3 Diffuse_Chan(half3 DiffuseColor, half Roughness, half NoV, half NoL, half VoH, half NoH)
{
    half Alpha = Roughness * Roughness;
    half Alpha2 = max(Alpha * Alpha, 1e-5h);
    half g = saturate(0.05555556h * log2(2.0h / Alpha2 - 1.0h));
    half w = saturate(2.2h * g - 0.5h);

    half F_Roughness = VoH + Pow5(1.0h - VoH);
    half FdV = 1.0h - 0.75h * Pow5(1.0h - NoV);
    half FdL = 1.0h - 0.75h * Pow5(1.0h - NoL);
    half F_Smooth = FdV * FdL;
    half Fd = lerp(F_Roughness, F_Smooth, w);
    
    // 边缘逆反射基底
    half Fb = ((34.5h * g - 59.0h) * g + 24.5h) * VoH * exp2(-max(73.2h * g - 21.2h, 8.9h) * sqrt(NoH));
    
    return DiffuseColor * INV_PI * (Fd + Fb);
}