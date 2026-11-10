#pragma once
// ===================================================
// UE 5 Anisotropic
// 出处: Unreal2022 Whitepaper Section 4.9 (Listing 15 & Listing 16)
// ===================================================

// UE5 各向异性粗糙度转换 (采纳 Kulla & Conty 2017 线性映射)
// anisotropy ∈ [-1.0, 1.0]：正值沿切线 T 变粗，负值沿副切线 B 变粗
// 下限强制锁死在 0.001h，防止 anisotropy = ±1.0 时粗糙度归零引发除零崩溃
void GetAnisotropicAlpha_Unreal2022(float Roughness, float Anisotropy, out float AlphaX, out float AlphaY)
{
    half Alpha = Roughness * Roughness;
    // Anisotropic parameters: ax and ay are the roughness along the tangent and bitangent
    // Kulla 2017, "Revisiting Physically Based Shading at Imageworks"
    AlphaX = max(Alpha * (1.0 + Anisotropy), 0.001f);
    AlphaY = max(Alpha * (1.0 - Anisotropy), 0.001f);
}

//  Unreal2022 各向异性 D 项
// 数学原式: 1 / [ π * αx * αy * ( (T·H / αx)² + (B·H / αb)² + (N·H)² )² ]
// 通过构造向量 vec = (αy * (T·H), αx * (B·H), αx*αy * (N·H))，将分母内的两次除法转化为一次点乘 dot(v, v)
half D_GGX_Anisotropic_Unreal2022(float AlphaX, float AlphaY, float NoH, float XoH, float YoH )
{
    float Alpha2 = AlphaX * AlphaY;
    float3 Vec = float3(AlphaY * XoH, AlphaX * YoH, Alpha2 * NoH);
    float Vec2 = dot(Vec, Vec);
    return (1.0f / PI) * Alpha2 * (Alpha2 / Vec2) * (Alpha2 / Vec2);
}

// Unreal2022 各向异性 V 项 (Listing 16: V_SmithGGXCorrelated_Anisotropic)
// 高度相关各向异性 Smith G 项 (Heitz 2014 Exact)
// 数学原式: 0.5 / [ (N · L) * sqrt(αx² * (T · V)² + αy² * (B · V)² + (N · V)²) + (N · V) * sqrt(αx² * (T · L)² + αy² * (B · L)² + (N · L)²) ]
half V_SmithJointGGX_Anisotropic_Unreal2022(float AlphaX, float AlphaY, float NoV, float NoL, float XoV, float XoL, float YoV, float YoL)
{
    float Vis_SmithV = NoL * length(float3(AlphaX * XoV, AlphaY * YoV, NoV));
    float Vis_SmithL = NoV * length(float3(AlphaX * XoL, AlphaY * YoL, NoL));
    return 0.5f * rcp(Vis_SmithV + Vis_SmithL);
}