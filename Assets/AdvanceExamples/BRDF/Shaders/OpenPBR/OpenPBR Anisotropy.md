

在 **OpenPBR (2024+)** 的官方规范（Section 2.2 / Specular Anisotropy）与 MaterialX 官方源码（`open_pbr_anisotropy` 节点）中，Autodesk 和 Adobe 的物理学家们对前面所有流派（Disney、Sony、glTF）做了一次终极审视，最后推导出了一个**在微表面统计学上最严密的参数化公式**。

我们先看它是怎么用**两条第一性原理约束**把这个公式推导出来的，再看它的完整代码！

---

### 一、 OpenPBR 各向异性公式的 3 行推导（为什么它是物理学的终极答案？）

设基础物理粗糙度为 $\alpha = \text{roughness}^2$，各向异性滑杆为 $\text{anisotropy} \in [0, 1]$。
OpenPBR 委员会提出了两条不可妥协的数学要求：

#### 要求 1：长宽比（Aspect Ratio）必须与滑杆完全线性对应！
Disney 当年为了凑面积不变，加了个 `0.9` 的魔数上限，导致拉满时最多只能到 $10:1$，做不出绝对锐利的刀锋高光。
OpenPBR 规定：短轴 $\alpha_y$ 与长轴 $\alpha_x$ 的比值，必须直接等于 $1 - \text{anisotropy}$（记作 $a = 1 - \text{anisotropy} \in [0, 1]$）：
**$$ \frac{\alpha_y}{\alpha_x} = 1 - \text{anisotropy} = a \implies \mathbf{\alpha_y = a \cdot \alpha_x} $$**
*(当 $\text{anisotropy} = 0$ 时，$\alpha_y = \alpha_x$ 为正圆；当 $\text{anisotropy} = 1$ 时，$\alpha_y = 0$，允许压成无限锐利的 1D 刀锋线！)*

#### 要求 2：斜率空间的总方差（均方根斜率平方和）必须严格守恒！
这是 OpenPBR 最硬核的一步！
还记得 $\alpha$ 在微表面物理学里的真身是什么吗？它是**微表面斜率的均方根（RMS Slope，即标准差 $\sigma$）**，而 **$\alpha^2$ 才是真正的方差（Variance，即二阶统计矩）**！
在概率论中，两个正交独立方向上的总方差，等于各自**方差的平均值**（而不是 Sony 那种一阶标准差的平均值 $\frac{\alpha_x + \alpha_y}{2}$）！

因此，OpenPBR 规定：无论你怎么拉扯各向异性，X 轴和 Y 轴的**粗糙度平方平均值（平均方差）必须恒等于各向同性时的 $\alpha^2$**：
**$$ \frac{\alpha_x^2 + \alpha_y^2}{2} = \alpha^2 $$**

#### 联立求解（见证公式诞生）：
把要求 1 的 $\alpha_y = a \cdot \alpha_x$ 代入要求 2 的方程中：
$$ \frac{\alpha_x^2 + (a \cdot \alpha_x)^2}{2} = \alpha^2 \implies \alpha_x^2 (1 + a^2) = 2 \alpha^2 $$
两边同时开根号，直接解出 OpenPBR 官方源码（`open_pbr_anisotropy`）中的精确公式：

**$$ \alpha_x = \text{roughness}^2 \cdot \sqrt{\frac{2}{1 + (1 - \text{anisotropy})^2}} $$**
**$$ \alpha_y = (1 - \text{anisotropy}) \cdot \alpha_x $$**

---

### 二、 这个公式带来了哪三大神仙好处？

1. **长轴绝不失控爆炸（封顶 $\sqrt{2}\alpha$）**：
   * 在 Disney 公式里，当 $\text{anisotropy} \to 1$ 时，$\alpha_x$ 会冲向 $+\infty$（所以被迫加了 `0.9` 锁死）。
   * 而在 OpenPBR 公式里，当 $\text{anisotropy} = 1$（即 $a = 0$）时，$\alpha_x$ 最大只会温和地增长到 **$\sqrt{2} \alpha \approx 1.414 \alpha$**，同时 $\alpha_y = 0$！高光既能聚集成极细的刀锋，又绝对不会在长轴方向过度发散！
2. **与多层材质（Coat 方差传递）100% 数学兼容**：
   我们在前面讲过，当表面涂了清漆（Coat）时，光线穿过粗糙清漆会让底层粗糙度变大，传递规律正是四次方/方差叠加（$\alpha_{\text{eff}}^2 = \alpha_{\text{base}}^2 + s \cdot \alpha_{\text{coat}}^2$）。因为 OpenPBR 守恒的就是 $\alpha_x^2 + \alpha_y^2 = 2\alpha^2$（二阶方差矩），所以多层材质叠加时能量和模糊度严丝合缝！
3. **多重散射查表（Turquin 补偿）零误差**：
   计算多重散射补偿 `comp` 时，需要输入一个等效的各向同性粗糙度去查 2D LUT 表。因为 $\sqrt{\frac{\alpha_x^2 + \alpha_y^2}{2}} \equiv \alpha$，直接拿原始的 `roughness` 去查表在二阶矩意义上是**绝对精确**的！

---

### 三、 OpenPBR 的切线旋转与 D、V、F 源码实现

在方向控制上，OpenPBR 的主节点直接接收三维切线向量 `geometry_tangent`（$\mathbf{T}$），如果美术使用旋转角，则同样通过二维旋转矩阵在切平面上旋转 $(\mathbf{T}, \mathbf{B})$。

至于底层的 `D` 项和 `V` 项本体，正如我们在 MaterialX 源码里看到的，依然是全行业通用的 **`D_GGX_Anisotropic`** 和 **`V_SmithJoint_GGX_Anisotropic`**！

下面为你整理好可直接入库的 **OpenPBR (2024+) 各向异性完整代码**：

```hlsl
#pragma once
#include "../Fresnel.hlsl"

// ===================================================
// OpenPBR Surface Anisotropic (v1.0 / v1.1 Official Specification, 2024+)
// ===================================================

// 1. OpenPBR 官方各向异性粗糙度转换 (源自 MaterialX: open_pbr_anisotropy)
// 核心物理守恒律：
//   (1) 长宽比线性控制: ay / ax = 1 - anisotropy
//   (2) 斜率方差平方和守恒: (ax² + ay²) / 2 = α² (其中 α = roughness²)
void GetAnisotropicRoughness_OpenPBR2024(half roughness, half anisotropy, out half ax, out half ay)
{
    half alpha = roughness * roughness;
    half a = 1.0h - saturate(anisotropy); // a ∈ [0, 1]
    
    ax = alpha * sqrt(2.0h / (1.0h + a * a));
    ay = a * ax;
    
    // 防除零安全底线
    ax = max(ax, 1e-3h);
    ay = max(ay, 1e-3h);
}

// 2. 各向异性 D 项 (与 Frostbite / Filament / UE5 / glTF 完全通用)
half D_GGX_Anisotropic_OpenPBR(half ax, half ay, half TdotH, half BdotH, half NdotH)
{
    half a2 = ax * ay;
    float3 v = float3(ay * TdotH, ax * BdotH, a2 * NdotH);
    float v2 = max(dot(v, v), 1e-7f);
    half d = a2 / v2;
    return a2 * d * d * (1.0h / PI);
}

// 3. 各向异性 V 项 (Heitz 2014 高度相关各向异性精确版)
half V_SmithJoint_GGX_Anisotropic_OpenPBR(
    half ax, half ay,
    half TdotV, half BdotV, half NdotV,
    half TdotL, half BdotL, half NdotL)
{
    half Al = length(half3(ax * TdotL, ay * BdotL, NdotL));
    half Av = length(half3(ax * TdotV, ay * BdotV, NdotV));
    return 0.5h * rcp(NdotV * Al + NdotL * Av + 1e-5h);
}

// 4. OpenPBR 2024 各向异性直接光高光主函数
// (结合 OpenPBR 的绝缘体精确 IOR 调制菲涅尔与金属 F82-Tint 菲涅尔)
half3 DirectSpecularBrdfAnisotropicOpenPBR2024(
    half roughness, half anisotropy,
    half3 N, half3 T, half3 B, half3 L, half3 V, half3 H,
    half3 base_color, half3 specular_tint, half specular, half ior, half metallic)
{
    half NdotV = saturate(abs(dot(N, V)) + 1e-5h);
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

    // 第一步：使用 OpenPBR 斜率方差守恒公式计算 ax, ay
    half ax, ay;
    GetAnisotropicRoughness_OpenPBR2024(roughness, anisotropy, ax, ay);

    // 第二步：评估 D * V * F
    half  D = D_GGX_Anisotropic_OpenPBR(ax, ay, TdotH, BdotH, NdotH);
    half  V_vis = V_SmithJoint_GGX_Anisotropic_OpenPBR(ax, ay, TdotV, BdotV, NdotV, TdotL, BdotL, NdotL);
    half3 F = F_OpenPBR2024(base_color, specular_tint, specular, ior, metallic, VdotH);

    return (D * V_vis) * F;
}
```

---

### 四、 各向异性篇大圆满总结！

回看我们走过的整个各向异性（Anisotropic）演进史，你会发现一个极其清晰的架构结论：
1. **底层微积分方程（`D_GGX_Anisotropic` 和 `V_SmithJoint_GGX_Anisotropic`）**：自从 2012 年 Burley 写出椭球 D 项、2014 年 Heitz 用线性拉伸变换写出高度相关 V 项之后，**全宇宙的引擎用的全都是同一套函数**！
2. **十几年来各大标准的唯一分歧**：全在于 `GetAnisotropicRoughness` 这短短 3 行代码——即**在拖动滑杆把正圆压成椭圆时，究竟应该守恒椭圆的哪个几何属性**：
   * **Disney 2012 / Frostbite 2014**：守恒**椭圆面积** $\pi \alpha_x \alpha_y = \pi \alpha^2$（中心亮度不变）；
   * **SPI 2017 / Filament 2018 / UE5**：守恒**半轴算术平均** $\frac{\alpha_x + \alpha_y}{2} = \alpha$（零开方零除法，支持 $[-1, 1]$ 正交翻转與锐利刀锋）；
   * **glTF 2023**：守恒**短轴最小粗糙度** $\alpha_y = \alpha$（单向变粗，零闪烁，极度利好实时 IBL）；
   * **OpenPBR 2024**：守恒**二阶斜率方差平均** $\frac{\alpha_x^2 + \alpha_y^2}{2} = \alpha^2$（物理统计最严密，完美契合多层粗糙度传递与多重散射查表）。

至此，你的《BRDF 代码大合集》在 **Specular（各向同性 + 各向异性）** 上已经从 2012 完整贯穿到了 2026！接下来我们是不是该把各家的 **Diffuse（漫反射）** 也像这样系统地梳理合并进来？
