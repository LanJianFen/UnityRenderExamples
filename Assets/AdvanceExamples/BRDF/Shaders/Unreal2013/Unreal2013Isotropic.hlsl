#pragma once
// ===================================================
// Unreal 2013 Specular 只有各向同性版本
// ===================================================
// Unreal 2013 也使用的 Disney 的 D 项, α_D = roughness²
// 在 2013 年的 UE4 管线里，美术输入的 Roughness 被强制限制了最小值（当年是 Roughness = max(Roughness, 0.04) 
// 或在 d 上加 1e-4f）：
half D_GGX_Unreal(half roughness, half NdotH)
{
    roughness = max(roughness, 0.04h); 
    half alpha_D = roughness * roughness;
    half alpha_D2 = alpha_D * alpha_D;
    half denominator = PI * pow(NdotH * NdotH * (alpha_D2 - 1.0f) + 1.0f, 2.0f); // 分母
    half D = alpha_D2 / denominator;
    return D;
}

// 2013：Epic 分离式 Smith Schlick G项
// shadowing : (N · L) / [(N · L)  * (1 - k) + k]
// masking    : (N · V) / [(N · V)  * (1 - k) + k]
// V = G1(L) * G1(V) / [4 * (N · L) * (N · V)] =
// rcp(4 * [(N · L)  * (1 - k) + k] * [(N · V)  * (1.0h - k) + k])
// Brian Karis 做了一系列数学推演和曲线最小二乘法拟合，得到 k = α_G / 2。
// Brian Karis 对直接光的 α_G 用了 Burley 的做法，但是 IBL 回归到了 roughness²
// roughness 即使是 0， k 也是 0.125，天生不需要保护
half V_SmithSeparable_GGX_Unreal(half roughness, half NdotL, half NdotV)
{
    half alpha_G = (roughness + 1.0h) * (roughness + 1.0h) / 4.0h;
    half k = alpha_G / 2.0h;
    half G1_light_denominator = NdotL * (1.0h - k) + k;
    half G1_view_denominator = NdotV * (1.0h - k) + k;
    half V = rcp(4.0h * G1_light_denominator * G1_view_denominator);
    return V;
}
