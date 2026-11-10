#pragma once
// =====================================================================================
// Disney 2012 anisotropic 各向异性
// =====================================================================================
// 2012 : Disney 的 GTR2 (GGX) 各向异性版本
// 分子 : 1
// 分母 : PI * αx * αy * ((T · H / αx) ² + (B · H / αy) ² + (N · H) ²)  ²
// αx = roughness² / aspect , αy = roughness² * aspect
// αx 和 αy 的设计在高光正中心（即 N · H = 1, T ⋅ H = 0, B ⋅ H = 0), D = rcp (PI * αx * αy),  最亮点的峰值强度永远不会随着各向异性强度改变变
// 椭圆的宽高比: αy / αx = aspect², Burley 希望美术手里的滑杆 anisotropic （0-1） 直接线性地控制宽高比
// 所以 aspect² = 1 - 0.9 * anisotropic, 现实中最极端的拉丝不锈钢的粗糙度长宽比也最多 10 : 1, 所以系数是 0.9；避免 aspect 是 0，计算安全范围
// 守恒的量：αx * αy
half D_GTR2_Anisotropic_Disney(half Roughness, half Anisotropic, half NdotH, half TdotH, half BdotH)
{
    half Aspect = sqrt(1.0h - 0.9h * Anisotropic);
    half AlphaD = Roughness * Roughness;
    half AlphaX = max(AlphaD / Aspect, 0.001h);
    half AlphaY = max(AlphaD * Aspect, 0.001h);
    
    half d = (TdotH * TdotH) / (AlphaX * AlphaX) + (BdotH * BdotH) / (AlphaY * AlphaY) + (NdotH * NdotH);
    half Denominator = PI * AlphaX * AlphaY * d * d;
    return rcp(Denominator);
}