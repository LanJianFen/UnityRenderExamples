#pragma once
// ===================================================
// Unreal 2022 Diffuse 尚未区分开金属和非金属的老版本函数
// ===================================================
half Pow5(half x)
{
    half x2 = x * x;
    return x2 * x2 * x;
}

// UE5 默认漫反射: Diffuse_Lambert
half3 DiffuseLambert_Unreal2022(half3 BaseColor, half Metallic)
{
    half3 DiffuseColor = BaseColor * (1.0h - Metallic);
    return DiffuseColor * (1.0h / PI);
}

// UE5 内置的 Disney 2012 漫反射: Diffuse_Burley
// 用的也是未平方的 Roughness
half3 DiffuseBurley_Unreal2022(half3 BaseColor, half Roughness, half Metallic, half NoV, half NoL, half VoH)
{
    half3 DiffuseColor = BaseColor * (1.0h - Metallic);
    
    half FD90 = 0.5h + 2.0h * VoH * VoH * Roughness;
    half FdV  = 1.0h + (FD90 - 1.0h) * Pow5(1.0h - NoV);
    half FdL  = 1.0h + (FD90 - 1.0h) * Pow5(1.0h - NoL);
    
    return DiffuseColor * ((1.0h / PI) * FdV * FdL);
}