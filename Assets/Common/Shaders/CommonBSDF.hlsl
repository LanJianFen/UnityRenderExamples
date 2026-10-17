#pragma once
#include "Assets/AdvanceExamples/BRDF/Shaders/Disney/Disney2012.hlsl"
#include "Assets/AdvanceExamples/BRDF/Shaders/Frostbite/Frostbite2014.hlsl"

float3 IBL_SpecularCustom(float3 R, float NdotV, float3 F0, float roughness)
{
    // 1. 反射方向 + mip level (UE4 mobile 近似公式)
    float mip = roughness * (1.7 - 0.7 * roughness) * 6.0;

    // 2. 采样立方体贴图并 HDR 解码
    float4 env_raw = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, R, mip);
    float3 env_color = DecodeHDREnvironment(env_raw, unity_SpecCube0_HDR);

    // 3. Split-sum Fresnel: 用 NdotV, lerp 到 grazing term 让边缘不失能
    //    掠射角 (NdotV → 0) → pow(1-NdotV, 4) → 1 → F 接近 grazing → 边缘发亮
    float smoothness_val = 1.0 - roughness;
    float reflectivity = max(max(F0.r, F0.g), F0.b);
    float3 grazing = saturate(smoothness_val + reflectivity).xxx;
    float3 F_env = lerp(F0, grazing, pow(1.0 - NdotV, 4.0));

    // 4. Surface reduction: α² = perceptualRoughness⁴, 粗糙度越大能量越分散
    float alpha2 = pow(roughness, 4.0);
    float surfaceReduction = 1.0 / (alpha2 + 1.0);

    return env_color * F_env * surfaceReduction;
}

// ====================================================================
// 纯数学拟合的 DFG (Sum 2) 项，完全不需要采样 2D LUT 贴图
// 输入: f0 (基础反射率), roughness (物理粗糙度 alpha), NoV (dot(N,V))
// ====================================================================
half3 EnvBRDFApprox(half3 f0, half roughness, half NdotV)
{
    // Lazarov 2013 拟合曲线
    const half4 c0 = { -1.0h, -0.0275h, -0.572h,  0.022h };
    const half4 c1 = {  1.0h,  0.0425h,  1.040h, -0.040h };
    
    half4 r = roughness * c0 + c1;
    half a004 = min(r.x * r.x, exp2(-9.28h * NdotV)) * r.x + r.y;
    half2 AB = half2(-1.04h, 1.04h) * a004 + r.zw;

    // 直接输出合成后的高光能量：f0 * scale + bias
    return f0 * AB.x + AB.y;
}

half3 IBL_Specular_Approximation(half3 V, half3 N, half3 F0, half roughness, half occlusion = 1.0h)
{
    half3 R = reflect(-V, N);
    half NdotV = saturate(dot(N, V));
    half3 sum1 = GlossyEnvironmentReflection(R, roughness, occlusion);
    half3 sum2 = EnvBRDFApprox(F0, roughness, NdotV);
    return sum1 + sum2;
}