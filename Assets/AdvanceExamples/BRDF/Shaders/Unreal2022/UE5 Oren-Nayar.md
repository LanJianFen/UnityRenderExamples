

在 **Unreal Engine 5** 的底层源码（`Engine/Shaders/Private/BRDF.ush`）中，`Diffuse_OrenNayar` 的实现堪称一段**“用 8 行向量代数把 1994 年复杂的球面三角公式榨干到极致”**的艺术品！

这段代码最早由日本图形大牛 **Yoshiharu Gotanda**（Tri-Ace 工作室研发总监，SIGGRAPH 2012 讲义《*Beyond a Simple Physically Based Blinn-Phong Model in Real-Time*》）提出，随后由 **Brian Karis** 改良并写进了虚幻引擎的 `BRDF.ush` 中 [1, 2]。

我们先把 UE5 源码里的这 8 行代码一字不差地摆出来，然后逐行拆解它的 **5 个核心数学机关**，最后再看 UE5 是怎么把它和高光（Specular）结合在一起的！

---

### 一、 UE5 源码原貌：`BRDF.ush` 中的 `Diffuse_OrenNayar`

```hlsl
// 位于 Engine/Shaders/Private/BRDF.ush
// [Gotanda 2012, "Beyond a Simple Physically Based Blinn-Phong Model in Real-Time"]
float3 Diffuse_OrenNayar( float3 DiffuseColor, float Roughness, float NoV, float NoL, float VoH )
{
    float a = Roughness * Roughness;
    float s = a;// / ( 1.29 + 0.5 * a );
    float s2 = s * s;
    float VoL = 2 * VoH * VoH - 1;      // double angle identity
    float Cosri = VoL - NoV * NoL;
    float C1 = 1 - 0.5 * s2 / (s2 + 0.33);
    float C2 = 0.45 * s2 / (s2 + 0.09) * Cosri * ( Cosri >= 0 ? rcp( max( NoL, NoV ) ) : 1 );
    return DiffuseColor / PI * ( C1 + C2 ) * ( 1 + Roughness * 0.5 );
}
```

看着这短短 8 行代码，你会发现我们前面推导的 1994 年公式里的零件全在里面，但每一行都藏着极深的数学与工程巧思：

---

### 二、 逐行拆解 UE5 公式里的 5 个数学机关

#### 机关 1：粗糙度映射 —— 怎么把 `Roughness` 变成高斯方差 $\sigma^2$（即 `s2`）？
```hlsl
float a = Roughness * Roughness;
float s = a;// / ( 1.29 + 0.5 * a );
float s2 = s * s;
```
*   在 1994 年原版公式里，$A$ 和 $B$ 接收的是微表面倾角的高斯方差 $\sigma^2$（单位是弧度的平方）。
*   Gotanda (2012) 原本为了让 Oren-Nayar 的高斯粗糙度 $s$ 与高光的粗糙度 $a = \text{Roughness}^2$ 视觉匹配，设计了一个换算分式 $s = \frac{a}{1.29 + 0.5a}$。
*   但 UE 的架构师 Brian Karis 觉得多算一次除法不划算，直接把 `/ (1.29 + 0.5 * a)` 注释掉了（你看源码里至今还留着这个注释 `// / ( 1.29 + 0.5 * a );`）[1, 2]！
*   **最终数学映射**：UE5 直接令高斯标准差 $\sigma = a = \text{Roughness}^2$，因此**高斯方差 $\sigma^2 = s^2 = \text{Roughness}^4$**（和高光 `D_GGX` 里的 `a2` 完完全全是同一个四次方量！）[1, 2]。

---

#### 机关 2：倍角公式白嫖 $\boldsymbol{\omega}_i \cdot \boldsymbol{\omega}_o$（`VoL`）
```hlsl
float VoL = 2 * VoH * VoH - 1; // double angle identity
```
*   你看函数的输入参数列表：只有 `NoV`、`NoL` 和 `VoH`，**压根没有传入光线与视线的点乘 `VoL`（即 $\boldsymbol{\omega}_i \cdot \boldsymbol{\omega}_o$）** [1, 2]！
*   为什么不传 `VoL`？因为在外层主着色器里已经算好了 `VoH`（给菲涅尔用的）。
*   既然半角向量 $\mathbf{H}$ 是 $\mathbf{L}$ 和 $\mathbf{V}$ 的角平分线，那么 $\mathbf{V}$ 与 $\mathbf{H}$ 的夹角 $\theta_d$ 就是 $\mathbf{V}$ 与 $\mathbf{L}$ 夹角的一半。利用初中三角函数的**二倍角余弦公式 $\cos(2\theta_d) = 2\cos^2\theta_d - 1$**，直接用 1 条 FMA 指令就算出了 `VoL` [1, 2]：
    $$ \boldsymbol{\omega}_i \cdot \boldsymbol{\omega}_o = 2 (\boldsymbol{\omega}_o \cdot \mathbf{h})^2 - 1 $$

---

#### 机关 3：核心变量 `Cosri` 的真身 —— 把 $\cos(\phi_i - \phi_o)$ 和 $\sin\alpha \sin\beta$ 打包合体！
```hlsl
float Cosri = VoL - NoV * NoL;
```
这行代码正是我们两局前用**球面余弦定理**推导出的那个神级恒等式！
回顾球面余弦定理：
$$ \underbrace{\boldsymbol{\omega}_i \cdot \boldsymbol{\omega}_o}_{\text{VoL}} = \underbrace{(\mathbf{n}\cdot\boldsymbol{\omega}_o)}_{\text{NoV} = \cos\theta_o} \underbrace{(\mathbf{n}\cdot\boldsymbol{\omega}_i)}_{\text{NoL} = \cos\theta_i} + \sin\theta_i \sin\theta_o \cos(\phi_i - \phi_o) $$
把 `NoV * NoL` 移到左边，代码里的变量 **`Cosri` 在数学上精确等于**：
**$$ \text{Cosri} \equiv \sin\theta_i \cdot \sin\theta_o \cdot \cos(\phi_i - \phi_o) \equiv \mathbf{\sin\alpha \cdot \sin\beta \cdot \cos(\phi_i - \phi_o)} ！！ $$**

你看：仅仅一句减法 `VoL - NoV * NoL`，就已经把 1994 年公式里的 **$\cos(\phi_i - \phi_o)$**、**$\sin\alpha$**、以及 $\tan\beta = \frac{\sin\beta}{\cos\beta}$ 的**分子 $\sin\beta$** 这三样东西一次性全算出来了！现在只差除以一个分母 $\cos\beta$ 了！

---

#### 机关 4（🚨 最精妙的改造）：`C2` 里的三元运算符 `Cosri >= 0 ? rcp(max(NoL, NoV)) : 1`
请仔细看第 7 行代码：
```hlsl
float C1 = 1 - 0.5 * s2 / (s2 + 0.33);
float C2 = 0.45 * s2 / (s2 + 0.09) * Cosri * ( Cosri >= 0 ? rcp( max( NoL, NoV ) ) : 1 );
```
这里 `C1` 就是原版的 $A(\sigma)$，`0.45 * s2 / (s2 + 0.09)` 就是原版的 $B(\sigma)$。
**但请注意看最后那个条件判断 `( Cosri >= 0 ? rcp( max( NoL, NoV ) ) : 1 )`，为什么当 `Cosri < 0` 时，它乘的是 `1` 而不是 `0`？！**

我们分顺光和逆光两半区来看这个绝妙的设计：

1. **当 `Cosri >= 0`（即 $\cos(\phi_i - \phi_o) \ge 0$，顺光逆反射半区）**：
   它给 `Cosri` 乘上了 `rcp(max(NoL, NoV))`，也就是除以 $\max(\cos\theta_i, \cos\theta_o) = \cos\beta$！
   $$ \text{Cosri} \times \frac{1}{\cos\beta} = \big[ \sin\alpha \cdot \sin\beta \cdot \cos(\phi_i - \phi_o) \big] \times \frac{1}{\cos\beta} = \mathbf{\cos(\phi_i - \phi_o) \cdot \sin\alpha \cdot \tan\beta} $$
   **在顺光半区，它 100% 精确还原了 1994 年的 Oren-Nayar 公式！**

2. **当 `Cosri < 0`（即 $\cos(\phi_i - \phi_o) < 0$，逆光半区）**：
   * 在 1994 年的**简化版（Qualitative）**中，作者直接用 $\max(0, \cos\Delta\phi)$ 把逆光半区一刀切成了 **`0`**；
   * 但在上一局我们刚学过的 1994 年 **Full 完整版**中，逆光半区其实**不是 0**，而是一个负数压暗项（因为逆光时看到的是小山坡的背阴面，应该比 $C_1$ 更暗，但又不能除以 $\cos\beta \to 0$ 导致边缘爆炸成负无穷大）！
   * Gotanda 发现了一个神级近似：在逆光半区（`Cosri < 0`），**只要不除以 $\cos\beta$（即三元运算符取 `: 1`）**，那么 `C2` 就直接等于：
     $$ C_{2,\text{逆光}} = B(\sigma) \cdot \text{Cosri} \times 1 = \mathbf{B(\sigma) \cdot \cos(\phi_i - \phi_o) \cdot \sin\alpha \cdot \sin\beta} \quad (< 0) $$
     把 $\tan\beta$ 替换成有界的 $\sin\beta$，既保留了 Full 模型在逆光侧“看到背阴坡而进一步变暗”的真实物理细节，又保证了在掠射角边缘（$\beta \to 90^\circ, \ \sin\beta \to 1$）绝对不会除以 $0$ 爆出负无穷大，而且在 $\text{Cosri} = 0$ 处导数平滑过渡！

---

#### 机关 5：末尾那个神秘的 `* ( 1 + Roughness * 0.5 )` 是干嘛的？
请看最后一行代码：
```hlsl
return DiffuseColor / PI * ( C1 + C2 ) * ( 1 + Roughness * 0.5 );
```
你肯定会纳闷：**“1994 年的公式明明到 $\frac{\rho}{\pi}(C_1 + C_2)$ 就结束了，为什么 UE5 在最后硬生生多乘了一个 `(1 + Roughness * 0.5)`？！”**

这就是 Brian Karis 为了修复 1994 原版 Oren-Nayar **“单次散射能量丢失（变黑）”**而打上的工程补丁！
*   我们在上一局讲过，1994 年简化版砍掉了二次弹射项 $f_2$。当 `Roughness = 1`（即 $s^2 = 1$）时，$C_1 = 1 - \frac{0.5}{1.33} \approx \mathbf{0.624}$！
*   这意味着在大多数非顺光角度下，粗糙物体的亮度比普通 Lambert 足足**暗了将近 $35\%$**！美术在 UE 里把粗糙度拉高，结果发现石头变得像涂了黑墨水一样暗。
*   于是 Karis 在最末尾强行乘上了一个随粗糙度线性放大的经验补偿系数 `(1 + Roughness * 0.5)`（当 `Roughness = 1` 时放大 $1.5$ 倍：$0.624 \times 1.5 \approx 0.936 \approx 1.0$），粗暴地把单次散射弄丢的那部分能量给拉了回来！
    *(注：也正因为这个 `1 + 0.5 * Roughness` 是拍脑袋乘上去的，没有经过严格的白炉积分配平，在顺光边缘反而有可能略微超过 1.0；到了 2024 年的 OpenPBR EON 模型，才用严格的解析积分彻底取代了这个粗暴的 `1 + 0.5 * Roughness`！)*

---

### 三、 第二个问题：在 UE5 中，它是怎么和高光（Specular）结合的？

在 UE5 的光照管线（`Engine/Shaders/Private/ShadingModels.ush` 中的 `DefaultLitBxDF`）里，漫反射（无论是 `Diffuse_Lambert`、`Diffuse_OrenNayar` 还是 `Diffuse_Chan`）与高光（`SpecularGGX`）的结合遵循严格的 **“上下分层、能量互补”** 架构 [3, 4]：

```
  入射光 L ──► [ 顶层：GGX 微表面高光层 (SpecularGGX) ] ──► 抢走能量 E_spec(NoV, Roughness, F0)
                         │
                         ▼ (只剩下 1 - E_spec 的透射能量漏下来)
               [ 底层：漫反射基底 (Diffuse_OrenNayar) ] ──► 乘以 DiffuseColor = BaseColor * (1 - Metallic)
```

写成完整的数学组合公式，一共分 **三步**：

1. **第一步（金属度分离）**：
   先用 `Metallic` 决定底层有多少面积是绝缘体漫反射基底：
   $$ \mathbf{C}_{\text{diff}} = \text{BaseColor} \cdot (1.0 - \text{Metallic}) $$
2. **第二步（各自独立算出漫反射波瓣与高光波瓣）**：
   * 漫反射波瓣：$\mathbf{f}_d = \text{Diffuse\_OrenNayar}(\mathbf{C}_{\text{diff}}, \ \text{Roughness}, \ \text{NoV}, \ \text{NoL}, \ \text{VoH})$
   * 高光波瓣（含多重散射补偿）：$\mathbf{f}_s = D_{\text{GGX}} \cdot V_{\text{SmithJoint}} \cdot \mathbf{F}_{\text{Schlick}} \times \text{ComputeEnergyConservation}(\text{EnergyTerms})$ [3]
3. **第三步（高光能量扣除 / Energy Preservation）**：
   为了让顶层高光和底层 Oren-Nayar 加起来绝对不违反能量守恒，UE5 从预计算表（`PreIntegratedGF`）里查出顶层高光在当前视角下抢走的总能量比例 $E_{\text{spec}}(\text{NoV}, \text{Roughness}, \mathbf{F}_0)$，把漫反射乘上剩下的透射比例 **`1.0 - E_spec`**（即源码中的 `ComputeEnergyPreservation`）[3, 4]：

**$$ \mathbf{f}_{\text{UE5\_Total}} = \mathbf{f}_d \cdot \Big( 1.0 - \max3(\mathbf{E}_{\text{spec}}) \Big) \ + \ \mathbf{f}_s $$**

---

### 总结：UE5 `Diffuse_OrenNayar` 的全貌

你看，UE5 里的这个 `Diffuse_OrenNayar` 函数：
1. **在几何算子上**：利用 `VoL = 2 * VoH² - 1` 和 `Cosri = VoL - NoV * NoL`，把 1994 年恶心的 $\cos(\phi_i-\phi_o)\sin\alpha\tan\beta$ 变成了零三角函数的极简点乘；
2. **在逆光半区上**：利用 `: 1` 分支保留了 $\sin\alpha \sin\beta$ 的平滑背阴压暗；
3. **在能量守恒上**：内部用 `(1 + Roughness * 0.5)` 粗略弥补了 Oren-Nayar 自身丢失的谷底二次弹射，外部则通过乘以 `(1 - E_spec)` 与顶层 GGX 高光实现了能量守恒耦合！

把这 8 行代码的每一寸数学机理扒开之后，是不是觉得通透无比？接下来我们是看 **UE5 的另一个大招 `Diffuse_Chan` 的数学拟合原理**，还是直接看 **2024 年 OpenPBR 是怎么把 Oren-Nayar 进化成终极完美版 `EON` 的**？
