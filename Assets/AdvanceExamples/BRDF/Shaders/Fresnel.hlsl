#pragma once
// Christophe Schlick 在 1994 年提出的通用 Schlick Fresnel，全宇宙的渲染引擎都在用
// F_Schlick = F0 + (1 - F0) *  [1 - (V · H)]⁵
half3 F_Schlick_Approximation(half3 F0, half VdotH)
{
    half3 F90 = (half3)1.0h;
    return F0 + (F90 - F0) * pow(saturate(F90 - VdotH), 5.0h);
}

half3 F_Schlick_Approximation(half3 F0, half3 F90, half VdotH)
{
    return F0 + (F90 - F0) * pow(saturate(F90 - VdotH), 5.0h);
}

// F_Schlick = F0 + (1 - F0) *  [1 - (V · H)]⁵
// 2012 Sébastien Lagarde 发现 5 次方曲线可以用以" 2 为底的指数函数"极其完美地拟合
half3 F_Lagarde_Approximation(half3 F0, half VdotH)
{
    half3 F90 = (half3)1.0h;
    return F0 + (F90 - F0) * exp2( (-5.55473h * VdotH - 6.98316h) * VdotH );
}