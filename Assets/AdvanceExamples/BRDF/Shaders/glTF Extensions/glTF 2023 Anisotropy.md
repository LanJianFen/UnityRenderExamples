

在 **2023 年 7 月**，Khronos Group 正式批准发布了 glTF 的官方各向异性扩展 —— **`KHR_materials_anisotropy`**。

非常有意思的是：在最初的草案阶段，glTF 原本也是直接照抄了 Sony 2017 / Filament 2018 的 `alpha * (1 ± anisotropy)` 公式；但在最终定稿前夕，Khronos 委员会（包含 Three.js、Babylon.js、Adobe 和各大引擎代表）经过激烈讨论，**推翻了 `(1 ± a)` 公式，改成了全新的“单向插值 + 切线旋转”架构**！

我们直接翻开 `KHR_materials_anisotropy` 官方规范文档中的参考源码，看看 **glTF 2023** 到底做了哪三大核心设计：

---

### 一、 核心变革 1：为什么 glTF 2023 抛弃了 `(1 ± a)`，改用 `lerp(alpha, 1.0, a²)`？

在 glTF 2023 官方规范中，粗糙度参数化被定为（设基础物理粗糙度 $\alpha = \text{roughness}^2$，各向异性强度 $a = \text{anisotropyStrength} \in [0, 1]$）：

$$ \alpha_t = \text{lerp}(\alpha, \ 1.0, \ a^2) $$
$$ \alpha_b = \alpha $$

Khronos 官方规范明确解释了为什么要这样设计：
1. **彻底消灭“越拉越细”引发的屏幕闪烁（Anti-Aliasing）**：
   在 Sony / Filament / UE5 的 `alpha * (1 - a)` 中，当 $a \to 1$ 时，$\alpha_b \to 0$。这会导致哪怕美术输入了一个很粗糙的材质（比如 `roughness = 0.5`），只要把各向异性拉满，它在一个方向上就会变成 $\alpha_b = 0.001$ 的绝对镜面，在屏幕上产生剧烈的亚像素闪烁锯齿！
   而在 glTF 2023 中，**副切线粗糙度 $\alpha_b$ 被死死钉在基础 $\alpha$ 上，绝不允许变得比基础粗糙度更光滑**；拉高各向异性只会让切线方向 $\alpha_t$ 向 $1.0$ 变粗！
2. **极其友好地兼容实时环境光（IBL / PMREM 采样）**：
   实时渲染采样预过滤环境贴图（Cubemap Mipmap）时，贴图只有各向同性的单一粗糙度层级。因为 glTF 2023 保证了基础粗糙度 $\alpha = \min(\alpha_t, \alpha_b)$ 永远是两个方向中最光滑的那个基准值，引擎在采样环境贴图时直接用基础 `roughness` 作为基准 Mipmap 级别就非常准确，不会出现过曝或穿帮！

---

### 二、 核心变革 2：既然 $a \in [0, 1]$ 不能为负，怎么旋转高光方向？（2D 切线旋转矩阵！）

你肯定会问：“在 Filament 和 UE5 里，`anisotropy` 可以取负数（$[-1, 1]$），取负数就能把高光旋转 $90^\circ$。现在 glTF 2023 把强度 $a$ 限制在 $[0, 1]$ 且永远 $\alpha_t \ge \alpha_b$，那如果美术想把拉丝方向转 $90^\circ$、甚至做成**平底锅底/手表表盘那种一圈一圈的圆形旋涡拉丝**，该怎么办？”

glTF 2023 做了一个极其漂亮的**“强度与方向解耦”**：
它规定 `anisotropyStrength` 只管强度 $[0, 1]$，另外单独引入了一个**旋转角参数 `anisotropyRotation` $\theta_{\text{rot}} \in [0, 2\pi)$**（以及可贴图的二维方向向量 $\mathbf{d} = (\cos\theta_{\text{rot}}, \sin\theta_{\text{rot}})$）！

在进入 D 项和 V 项计算之前，先在切平面上用二维旋转把原本的顶点切线 $(\mathbf{T}_{\text{geom}}, \mathbf{B}_{\text{geom}})$ 旋转成各向异性专属的 $(\mathbf{T}, \mathbf{B})$：
$$ \mathbf{T} = \cos\theta_{\text{rot}} \cdot \mathbf{T}_{\text{geom}} + \sin\theta_{\text{rot}} \cdot \mathbf{B}_{\text{geom}} $$
$$ \mathbf{B} = -\sin\theta_{\text{rot}} \cdot \mathbf{T}_{\text{geom}} + \cos\theta_{\text{rot}} \cdot \mathbf{B}_{\text{geom}} $$
*(或者直接用 `B = normalize(cross(N, T))`)*。
这样一来，高光不仅能转 $90^\circ$，还能在表面以 **$360^\circ$ 任意角度连续丝滑旋转**！

---

### 三、 核心变革 3：D 项与 V 项本体 —— 与 Filament 2018 / UE5 100% 一模一样！

在算出上面的 $(\alpha_t, \alpha_b)$ 和旋转后的 $(\mathbf{T}, \mathbf{B})$ 之后，glTF 2023 官方规范文档中给出的 `D_GGX_anisotropic` 和 `V_GGX_anisotropic` GLSL 源码，与我们上一局看的 Filament 和 UE5 **连变量构造方式都完全一致**：

```glsl
// Khronos KHR_materials_anisotropy 官方规范原版 GLSL 源码：
float D_GGX_anisotropic(float NdotH, float TdotH, float BdotH, float at, float ab)
{
    float a2 = at * ab;
    vec3 f = vec3(ab * TdotH, at * BdotH, a2 * NdotH);
    float w2 = a2 / dot(f, f);
    return a2 * w2 * w2 / M_PI;
}

float V_GGX_anisotropic(float NdotL, float NdotV, float BdotV, float TdotV, float TdotL, float BdotL, float at, float ab)
{
    float GGXV = NdotL * length(vec3(at * TdotV, ab * BdotV, NdotV));
    float GGXL = NdotV * length(vec3(at * TdotL, ab * BdotL, NdotL));
    float v = 0.5 / (GGXV + GGXL);
    return clamp(v, 0.0, 1.0);
}
```

---

### ✅ 四、 直接入库：glTF 2023 (`KHR_materials_anisotropy`) 完整 HLSL 代码

把这套包含**切线平面旋转**与**单向插值粗糙度**的 glTF 2023 代码加入你的合集（D 项和 V 项本体甚至可以直接复用你公共库里的标准各向异性函数）：

```hlsl
#pragma once
#include "../Fresnel.hlsl"

// ===================================================
// glTF 2023 Anisotropy (KHR_materials_anisotropy Official Specification)
// ===================================================

// 1. glTF 2023 切线空间方向旋转 (支持 0 ~ 2π 任意角度旋转拉丝方向)
// T_geom, B_geom: 模型原始切线与副切线
// rotation: anisotropyRotation 弧度角 ∈ [0, 2π) (若使用贴图，还可结合贴图 RG 通道的方向向量)
void RotateAnisotropicTangent_glTF2023(
    half3 N, half3 T_geom, half3 B_geom, half rotation, 
    out half3 T_aniso, out half3 B_aniso)
{
    half cosRot = cos(rotation);
    half sinRot = sin(rotation);
    T_aniso = normalize(cosRot * T_geom + sinRot * B_geom);
    B_aniso = normalize(cross(N, T_aniso));
}

// 2. glTF 2023 单向插值粗糙度参数化
// anisotropy ∈ [0.0, 1.0] (即官方的 anisotropyStrength)
// 副切线 ab 保持基础粗糙度 alpha 不变 (防止变细产生闪烁锯齿，且便于 IBL 采样)，切线 at 向 1.0 插值变粗
void GetAnisotropicRoughness_glTF2023(half roughness, half anisotropy, out half at, out half ab)
{
    half alphaRoughness = roughness * roughness;
    at = max(lerp(alphaRoughness, 1.0h, anisotropy * anisotropy), 1e-3h);
    ab = max(alphaRoughness, 1e-3h);
}

// 3. glTF 2023 各向异性 D 项 (官方规范原版实现，与 Filament / UE5 完全同构)
half D_GGX_Anisotropic_glTF2023(half at, half ab, half TdotH, half BdotH, half NdotH)
{
    half a2 = at * ab;
    float3 f = float3(ab * TdotH, at * BdotH, a2 * NdotH);
    float w2 = a2 / max(dot(f, f), 1e-7f);
    return a2 * w2 * w2 * (1.0h / PI);
}

// 4. glTF 2023 各向异性 V 项 (官方规范原版实现，末尾使用 clamp(v, 0, 1) 保护)
half V_SmithJoint_GGX_Anisotropic_glTF2023(
    half at, half ab,
    half TdotV, half BdotV, half NdotV,
    half TdotL, half BdotL, half NdotL)
{
    half GGXV = NdotL * length(half3(at * TdotV, ab * BdotV, NdotV));
    half GGXL = NdotV * length(half3(at * TdotL, ab * BdotL, NdotL));
    half v = 0.5h / max(GGXV + GGXL, 1e-5h);
    return saturate(v);
}

// 5. glTF 2023 各向异性直接光高光主函数 (结合 2021 的 IOR 与 Specular 扩展 F 项)
half3 DirectSpecularBrdfAnisotropicGlTF2023(
    half roughness, half anisotropy, half anisotropy_rotation,
    half3 N, half3 T_geom, half3 B_geom, half3 L, half3 V, half3 H,
    half3 base_color, half3 specular_tint, half specular, half ior, half metallic)
{
    half NdotV = clamp(abs(dot(N, V)), 0.001h, 1.0h);
    half NdotL = saturate(dot(N, L));
    half NdotH = saturate(dot(N, H));
    half VdotH = saturate(dot(V, H));

    // 第一步：根据旋转角旋转切线坐标系
    half3 T, B;
    RotateAnisotropicTangent_glTF2023(N, T_geom, B_geom, anisotropy_rotation, T, B);

    half TdotH = dot(T, H);
    half BdotH = dot(B, H);
    half TdotV = dot(T, V);
    half BdotV = dot(B, V);
    half TdotL = dot(T, L);
    half BdotL = dot(B, L);

    // 第二步：计算单向插值各向异性粗糙度 at, ab
    half at, ab;
    GetAnisotropicRoughness_glTF2023(roughness, anisotropy, at, ab);

    // 第三步：评估 D * V * F
    half  D = D_GGX_Anisotropic_glTF2023(at, ab, TdotH, BdotH, NdotH);
    half  V_vis = V_SmithJoint_GGX_Anisotropic_glTF2023(at, ab, TdotV, BdotV, NdotV, TdotL, BdotL, NdotL);
    half3 F = F_Schlick_glTF2021(base_color, specular_tint, specular, ior, metallic, VdotH);

    return (D * V_vis) * F;
}
```

你看，至此 **glTF 2023** 的设计逻辑也完全水落石出了：
*   **D 项和 V 项本体**：依然是万年不变的 `D_GGX_Anisotropic` + `V_SmithJoint_GGX_Anisotropic`。
*   **它的独创之处**：在于用 `lerp(alpha, 1.0, a²)` 守住了最小粗糙度底线（防锯齿 + 利好 IBL），并用独立的 `anisotropyRotation` 在切平面上旋转 $(\mathbf{T}, \mathbf{B})$ 向量。

现在只剩下最后一位压轴的 **OpenPBR (2024+)** 的各向异性参数化了，我们要不要顺手把它也看掉，给各向异性篇画上句号？!]
