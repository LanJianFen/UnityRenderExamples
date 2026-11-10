#pragma once
#include "Frostbite2014Isotropic.hlsl"
#include "Frostbite2014Anisotropic.hlsl"
#include "Frostbite2014Fresnel.hlsl"
#include "Frostbite2014Diffuse.hlsl"
// ===================================================
// Frostbite 2014
// ===================================================



// 向量都是 normalization 的
// Frostbite 使用 abs() 镜像处理法线贴图导致的负 NdotV，并加 1e-5h 严格防 0
// 在光栅化中，三角形如果背对相机，早在 背面剔除（Back-face Culling） 阶段就被硬件扔掉了，根本不进入 Pixel Shader！
// 凡是能活着走到 BRDF 代码里的像素，它的真实几何表面法线 N与视线 V 的点乘必然是大于 0 的
// 那为什么代码里的 dot(N, V) 会变成负数（比如 -0.3 甚至 -0.5）？
// 凶手有两个：
// 1. 强烈的法线贴图：当以比较倾斜的角度观察时，宏观表面是朝向你的。但是，法线贴图记的虚拟法线往远离你的方向再倾斜了 
// 结果：宏观上你能看到这个像素，但法线贴图算出来的虚拟法线 却偏转到了视线之下，算出来的 dot(N, V) 瞬间变成了负数！
// 2. 低模边缘的平滑顶点法线插值（Smooth Vertex Normals）：
// 一个低多边形球体的边缘，三角面本身朝向相机，但为了平滑过渡，边缘顶点的法线被插值指向了背对相机的方向。
// 这就是渲染管线里著名的“着色法线越界悖论（Shading Normal Invalidity）”：
//如果我们按常规直觉写：half NdotV = max(dot(N, V), 0.0001h);
// 会发生两场极其丑陋的视觉灾难：
// 1：高光與环境反射出现“死黑刀切黑斑（Black Artifacts）”
// 一旦所有 < 0 的区域全部被一刀切压死在 0.0001（极度掠射角）：
// 像素在计算环境反射（IBL）和直接光时，连续变化被瞬间斩断，在粗糙金属或水面波纹的边缘，你会看到一块块极其突兀的“死黑斑块”或者“纯白亮斑镶边”。
//灾难 2：
// V 项分母在 NdotL 也很小时引发数值爆炸
// 当 NdotV 被强行压在 0.0001，如果此时光线也接近边缘（NdotL 也很小），代入 
// NdotV * Al + NdotL * Av 会变成一个极其接近 0 的微小数字，它的倒数 rcp() 会飙升到几千倍，在物体轮廓边缘炸出一圈刺眼的亮线！
// 在离线路径追踪器（如 Disney Hyperion / Arnold）中，正规的做法是“法线弯曲修正（Normal Bending / Clamp）”——花十几条指令把法线向量重新旋转拉回到视线平面之上。
// 但在实时渲染里，旋转向量太贵了！Lagarde 发现，直接对点乘取绝对值等价于：以视线 V 的垂直平面为镜面，将那个越界到背面的法线（或视线）做了一次完美的【对称镜像反弹（Mirror Reflection）】！
half3 DirectSpecularBrdfFrostbite(half roughness, half3 N, half3 L, half3 V, half3 H, half3 base_color, half reflectance, half metallic)
{
    half NdotV = abs(dot(N, V)) + 1e-5h;
    half NdotL = saturate(dot(N, L));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));
    half3 specular_brdf = 
        D_GGX_Frostbite(roughness, NdotH) *  V_SmithJoint_GGX_Frostbite(roughness, NdotL, NdotV) *
        F_Schlick_Frostbite(base_color, reflectance, metallic, VdotH);
    return specular_brdf;
}



// Frostbite 2014 各向异性直接光高光主函数
half3 DirectSpecularBrdfAnisotropicFrostbite(half roughness, half anisotropy,
    half3 N, half3 T, half3 B, half3 L, half3 V, half3 H,half3 base_color, half reflectance, half metallic)
{
    half NdotV = abs(dot(N, V)) + 1e-5h;
    half NdotL = saturate(dot(N, L));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));
    // 切线与副切线点乘保留正负号，不可 saturate
    half TdotH = dot(T, H);
    half BdotH = dot(B, H);
    half TdotV = dot(T, V);
    half BdotV = dot(B, V);
    half TdotL = dot(T, L);
    half BdotL = dot(B, L);
    half alphax, alphay;
    GetAnisotropicAlpha_Frostbite2014(roughness, anisotropy, alphax, alphay);

    half3 specular_brdf = D_GGX_Anisotropic_Frostbite(alphax, alphay, TdotH, BdotH, NdotH) * 
            V_SmithJoint_GGX_Anisotropic_Frostbite(alphax, alphay, TdotV, BdotV, NdotV, TdotL, BdotL, NdotL) *
            F_Schlick_Frostbite(base_color, reflectance, metallic, VdotH);
    
    return specular_brdf;
}