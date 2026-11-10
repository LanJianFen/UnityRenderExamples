#pragma once
// =====================================================================================
// Disney 2012 Diffuse
// =====================================================================================
// Disney 2012 Diffuse 是纯经验模型
// 1.  极其光滑的材质（如光滑塑料、台球），在 V · H = 0 的掠射角表面的高光菲涅尔反射率 F 接近 100%
//     既然光子在表面几乎全被当成高光弹飞了，根本没有光子能钻进物体内部，边缘漫反射会变暗！
// 2. 极其粗糙的材质（如干泥土、粉笔、天鹅绒、月球表面)，粗糙表面布满了高低起伏的微观小山峰。
//    在 N · L  = 0  极平的掠射角，虽然宏观视线和地面平行，但你的视线其实是垂直正对着那些微观小山峰的迎光侧壁
//    如果此时光源刚好在你眼睛附近（顺光），光线垂直钻进小山峰侧壁发生散射，并直接原路弹回你的眼睛，边缘漫反射反而会剧烈变亮

//   Disney 2012 Diffuse 的基底是 c / PI；金属性越强，漫反射越弱 乘 ( 1 - metallic)
//   
//   传统漫反射能量模型：(1 - F(L)) * (1 - F(V))
//   单项 = 1 - [F0  + (1 - F0) * (1 - cos θ) ⁵] = (1 - F0) * [1 - (1 - cos θ) ⁵]
//   对 Disney 的默认绝缘体来说 (1 - F0) = 0.96，数值不小，Disney 省略了
//    [1 - (1 - N · L) ⁵] * [1 - (1 - N · L) ⁵] 的基础上，构造 [1 - (FD90 - 1) * (1 - N · L) ⁵] * [1 - (FD90 - 1) * (1 - N · L) ⁵]
//   light_scatter : lerp(1.0, FD90, (1 - N · L)⁵) ， 1 和 FD90 负责描述 0 度 和 90 度时的进入难度，根据夹角在两个难度基准之间插值
//   view_scatter : lerp(1.0, FD90, (1 - N · V)⁵) ， 1 和 FD90 负责描述 0 度 和 90 度时的出射难度，根据夹角在两个难度基准之间插值
//   
//   FD90 统一描述光滑物体和粗糙物体在 N 和 L(V) 在夹角接近 90 度时的光线进(出)表面的难易度，光滑物体小，粗糙物体大：包含粗糙度
//   逆反射基于微表面模型，L(V) 和 H 的夹角越小，越容易反射：包含 L(V) · H, （L · H 和 V · H 是相等的) 
//   加上平方时， (L · H)² = 0.5 + 0.5 * (L · V)，导数更平滑并且曲线更自然
//   比较光滑时，Disney 并没有把 FD90 完全认为是 0
//   FD90 = 0.5 + 2 * roughness * (L · H)²
//   
// 数学公式：1 + (fD90 - 1) * (1 - N · L)^5 = lerp(1, FD90, (1 - N · L)^5)
half F_Schlick_Scalar(half f90, half cosTheta)
{
    return lerp(1.0h, f90, pow(saturate(1.0h - cosTheta), 5.0h));
}

// 注意传递的是没平方的 roughness
half3 Diffuse_Disney2012(half3 base_color, half roughness, half metallic, half NdotL, half NdotV, half LdotH)
{
    half3 diffuse_color = base_color * (1.0h - metallic);
    half FD90 = 0.5h + 2.0h * roughness * (LdotH * LdotH);
    
    half light_scatter = F_Schlick_Scalar(FD90, NdotL);
    half view_scatter  = F_Schlick_Scalar( FD90, NdotV);
    
    return diffuse_color * INV_PI * light_scatter * view_scatter;
}
