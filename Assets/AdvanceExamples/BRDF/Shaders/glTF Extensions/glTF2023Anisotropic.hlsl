#pragma once
// ===================================================
// glTF 2.0 Extensions 2023 Anisotropic
// ===================================================
// glTF 的各向异性只接受 y 方向的变粗
// αt = lerp(α, 1.0h, anisotropy * anisotropy) = α *  ( 1 - anisotropy²) + anisotropy²
// 守恒的量：αb = α
// αt * αb = α² *  ( 1 - anisotropy²) + α * anisotropy²  ，随着 anisotropy 增加，中心亮度降低
void GetAnisotropicAlpha_glTF2023(half roughness, half anisotropy, out half at, out half ab)
{
    half alpha = roughness * roughness;
    at = max(lerp(alpha, 1.0h, anisotropy * anisotropy), 1e-3h);
    ab = max(alpha, 1e-3h);
}

// 因为 αy 守恒，所以为了实现2个方向的各向异性，glTF 2023旋转旋转 T 和 B
// T = cosθ * T_geom + sinθ * B_geom
// B = -sinθ * T_geom + cosθ * B_geom 或者是 N * T
void RotateAnisotropicTangent_glTF2023(
    half3 N, half3 T_geom, half3 B_geom, half rotation, 
    out half3 T_aniso, out half3 B_aniso)
{
    half cosRot = cos(rotation);
    half sinRot = sin(rotation);
    T_aniso = normalize(cosRot * T_geom + sinRot * B_geom);
    B_aniso = normalize(cross(N, T_aniso));
}

// glTF 2023 各向异性 D 项 (官方规范原版实现，与 Filament / UE5 完全同构)
half D_GGX_Anisotropic_glTF2023(half alphat, half alphab, half TdotH, half BdotH, half NdotH)
{
    half alpha2 = alphat * alphab;
    float3 f = float3(alphab * TdotH, alphat * BdotH, alpha2 * NdotH);
    float w2 = alpha2 / max(dot(f, f), 1e-7f);
    return alpha2 * w2 * w2 * (1.0h / PI);
}

//  glTF 2023 各向异性 V 项 (官方规范原版实现，末尾使用 clamp(v, 0, 1) 保护)
half V_SmithJoint_GGX_Anisotropic_glTF2023(
    half alphat, half alphab,
    half TdotV, half BdotV, half NdotV,
    half TdotL, half BdotL, half NdotL)
{
    half GGXV = NdotL * length(half3(alphat * TdotV, alphab * BdotV, NdotV));
    half GGXL = NdotV * length(half3(alphat * TdotL, alphab * BdotL, NdotL));
    half v = 0.5h / max(GGXV + GGXL, 1e-5h);
    return saturate(v);
}