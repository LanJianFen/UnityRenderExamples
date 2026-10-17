

压轴登场的是 **OpenPBR Surface（2024 年正式发布 v1.0 规范，目前已全面接管 Autodesk Arnold、Maya、3ds Max 以及 Adobe Substance 3D 生态）**。

如果说 glTF Extensions 是实时领域的妥协公约，UE5 Substrate 是游戏引擎的极限压缩，那么由 **Autodesk 与 Adobe 联合顶尖图形学者（如 Emmanuel Turquin、Zap Andersson 等）共同起草的 OpenPBR**，就是当今计算机图形学在**“不直接让美术填复数 $(n, \kappa)$ 的前提下，所能达到的数学与物理最高峰”**！

它做了一件极其了不起的事：**彻底消灭了“非金属用一套公式，金属用另一套公式，但在边缘又对不齐”的割裂感，在数学底层把绝缘体和金属完美封装成了两个独立且自洽的菲涅尔算子，最后再做能量混合。**

依然不看代码，我们直接看 OpenPBR 官方白皮书（Specification）中定义的 **三大核心数学公式**！

---

### 一、 OpenPBR 的输入参数定义

在 OpenPBR 的基础与高光模块中，与 F 项直接相关的核心输入有 5 个：
1. **基础颜色 $\mathbf{C}_{\text{base}} \in [0, 1]^3$**（`base_color`，乘上 `base_weight` $w_{\text{base}}$）。
2. **金属度 $m \in [0, 1]$**（`base_metalness`）。
3. **高光折射率 $n \in [1.0, +\infty)$**（`specular_ior`，默认 $1.5$）。
4. **高光权重 $w_{\text{spec}} \in [0, +\infty)$**（`specular_weight`，默认 $1.0$）。
5. **高光颜色 $\mathbf{C}_{\text{spec}} \in [0, 1]^3$**（`specular_color`，默认纯白 $\mathbf{1.0}$）。

**请注意 OpenPBR 最天才的“一鱼两吃”参数复用设计：**
*   当材质是**非金属（绝缘体）**时，$\mathbf{C}_{\text{spec}}$ 代表 **$0^\circ$ 基础高光的染色**；
*   当材质是**金属（导体）**时，金属的 $0^\circ$ 颜色已经被 $\mathbf{C}_{\text{base}}$ 占用了，此时 $\mathbf{C}_{\text{spec}}$ **自动摇身一变，直接充当金属在 $82^\circ$ 时的边缘凹陷染色系数 $\mathbf{T}_{82}$**！
这样既没有增加多余的贴图通道，又同时满足了非金属染色和金属边缘暗带！

---

### 二、 第一大公式：绝缘体（Dielectric）的“介电跳变调制”

这是 OpenPBR 和前面 glTF Extensions 最大的不同点！

在 glTF 中，美术调节权重 $w_{\text{spec}}$ 时，是粗暴地把算出来的 $F_0$ 和 $F_{90}$ 直接乘以 $w_{\text{spec}}$。
**但 OpenPBR 的物理学家指出：直接改 $F_{90}$ 在物理上是错的！** 如果你在做光追玻璃或者多层清漆，改变了 $F_0$ 却不改变底层的折射率 $n$，会导致反射亮度和折射角度自相矛盾！

于是，OpenPBR 提出了 **“调制介电常数跳变（Modulating the Dielectric Jump）”** 的严格数学公式：

#### 1. 计算基准相对折射率 $\eta$ 及其 $F_0$
假设外部环境折射率为 $n_{\text{ext}}$（空气为 $1.0$），材质折射率为 $n$。基础相对折射率 $\eta = \frac{n}{n_{\text{ext}}}$。
基准的正视反射率标量为：
$$ f_{0,\text{base}} = \left( \frac{\eta - 1}{\eta + 1} \right)^2 $$

#### 2. 用权重 $w_{\text{spec}}$ 调制 $F_0$ 并反推“有效折射率 $\eta'$”
把权重 $w_{\text{spec}}$ 乘在 $f_{0,\text{base}}$ 上，并用 $\min$ 锁死在 $1.0$ 以内（防止违反能量守恒）：
$$ f'_{0} = \min\left( w_{\text{spec}} \cdot f_{0,\text{base}}, \ 1.0 \right) $$
甚至，为了保证折射与反射完全自洽，OpenPBR 规定用我们上一局推导过的逆公式，从 $f'_0$ 反解出**调制后的有效相对折射率 $\eta'$**：
$$ \eta' = \frac{1 + \sqrt{f'_0}}{1 - \sqrt{f'_0}} $$
*(当 $w_{\text{spec}} \to 0$ 时，$f'_0 \to 0 \implies \eta' \to 1.0$。意味着这层介质的折射率变得和空气一模一样，界面在物理上彻底隐形消失，不仅 $F_0=0$，连精确菲涅尔方程算出来的折射和反射也自然归零！)*

#### 3. 结合高光颜色 $\mathbf{C}_{\text{spec}}$ 得到绝缘体菲涅尔 $\mathbf{F}_{\text{dielectric}}(u)$
若在实时渲染中使用 Schlick 近似（记 $u = \mathbf{v} \cdot \mathbf{h}$），绝缘体的 $\mathbf{F}_{0,\text{d}}$ 为：
$$ \mathbf{F}_{0,\text{d}} = f'_0 \cdot \mathbf{C}_{\text{spec}} = \min\left( w_{\text{spec}} \cdot \left(\frac{\eta - 1}{\eta + 1}\right)^2, \ 1.0 \right) \cdot \mathbf{C}_{\text{spec}} $$
代入绝缘体 Schlick 方程（注意：在纯正物理下，只要存在界面，极限 $90^\circ$ 依然向 $1.0$ 过渡，或者受 $w_{\text{spec}}$ 截断）：
**$$ \mathbf{F}_{\text{dielectric}}(u) = \mathbf{F}_{0,\text{d}} + \left( \mathbf{1.0} - \mathbf{F}_{0,\text{d}} \right) (1 - u)^5 $$**

---

### 三、 第二大公式：金属（Conductor）的 F82-Tint 完全体方程

对于金属部分，OpenPBR 正式将 **Lazanyi-Hoffman 的 7 次方边缘凹陷模型（F82-Tint）** 立为全球工业标准！

在金属分支中：
*   **$0^\circ$ 起点反射率 $\mathbf{F}_{0,\text{m}}$**：由基础权重和基础色决定：
    $$ \mathbf{F}_{0,\text{m}} = w_{\text{base}} \cdot \mathbf{C}_{\text{base}} $$
*   **$82^\circ$ 凹陷染色系数 $\mathbf{T}_{82}$**：直接取自高光颜色参数：
    $$ \mathbf{T}_{82} = \mathbf{C}_{\text{spec}} $$

计算金属菲涅尔 $\mathbf{F}_{\text{metal}}(u)$ 的三步代数式：

1. **先算基准 Schlick 曲线 $\mathbf{F}_{\text{schlick}}(u)$**：
   $$ \mathbf{F}_{\text{schlick}}(u) = \mathbf{F}_{0,\text{m}} + \left( \mathbf{1.0} - \mathbf{F}_{0,\text{m}} \right) (1 - u)^5 $$

2. **计算基准曲线在极值角 $\mu_0 = \frac{1}{7}$（约 $81.79^\circ$）处的数值，并求出凹陷幅度向量 $\mathbf{b}$**：
   $$ \mathbf{F}_{\text{schlick}}\left(\frac{1}{7}\right) = \mathbf{F}_{0,\text{m}} + \left( \mathbf{1.0} - \mathbf{F}_{0,\text{m}} \right) \left(\frac{6}{7}\right)^5 $$
   $$ \mathbf{b} = \frac{7^7}{6^6} \cdot \mathbf{F}_{\text{schlick}}\left(\frac{1}{7}\right) \cdot \left( \mathbf{1.0} - \mathbf{C}_{\text{spec}} \right) $$

3. **从基准曲线中挖去 7 次方波谷，并用 `clamp` 锁死在 $[0, 1]$ 之间（还要乘上高光总权重 $w_{\text{spec}}$）**：
   **$$ \mathbf{F}_{\text{metal}}(u) = w_{\text{spec}} \cdot \text{clamp}\left( \mathbf{F}_{\text{schlick}}(u) - \mathbf{b} \cdot u (1 - u)^6, \ \mathbf{0.0}, \ \mathbf{1.0} \right) $$**

---

### 四、 第三大公式：绝缘体与金属的最终融合

你可能注意到：
*   绝缘体的 $\mathbf{F}_{\text{dielectric}}(u)$ 是一个 **5 次多项式**；
*   金属的 $\mathbf{F}_{\text{metal}}(u)$ 是一个 **7 次多项式**（多了 $- \mathbf{b} \cdot u(1-u)^6$ 这一项）！

因为两者的多项式阶数不同，你不能再像以前那样只对 $\mathbf{F}_0$ 做一次 `lerp` 就完事了，而是可以直接对两个菲涅尔结果按金属度 $m$ 做线性混合（或者把系数 $\mathbf{F}_0$ 和 $\mathbf{b}$ 分别按 $m$ 线性混合）：

**$$ \mathbf{F}_{\text{OpenPBR}}(u) = (1 - m) \cdot \mathbf{F}_{\text{dielectric}}(u) + m \cdot \mathbf{F}_{\text{metal}}(u) $$**

如果展开成**单次多项式求值的高效合并形式**，其实就是：
1. 混合起点：$\mathbf{F}_0 = \text{lerp}(\mathbf{F}_{0,\text{d}}, \ \mathbf{F}_{0,\text{m}}, \ m)$
2. 混合凹陷系数：$\mathbf{b}_{\text{total}} = m \cdot \mathbf{b}$ （因为非金属没有 $82^\circ$ 凹陷，其 $\mathbf{b}_{\text{d}} = \mathbf{0}$）
3. 一次性算出最终菲涅尔：
   **$$ \mathbf{F}_{\text{OpenPBR}}(u) = \mathbf{F}_0 + (\mathbf{1.0} - \mathbf{F}_0)(1 - u)^5 - \mathbf{b}_{\text{total}} \cdot u(1 - u)^6 $$**

**请欣赏上面这最后一行合并后的公式！**
*   当 $m = 0$（非金属）时，$\mathbf{b}_{\text{total}} = \mathbf{0}$，后面的 7 次方自动消失，完美退化为由真实 IOR 驱动的 5 次方 Schlick！
*   当 $m = 1$（纯金属）时，$\mathbf{b}_{\text{total}} = \mathbf{b}$，后面的 7 次方全面激活，精准雕刻出金属在 $82^\circ$ 的拟布儒斯特角暗带！
*   当 $\mathbf{C}_{\text{spec}} = (1, 1, 1)$（美术不调边缘染色）时，$\mathbf{1.0} - \mathbf{C}_{\text{spec}} = \mathbf{0} \implies \mathbf{b} = \mathbf{0}$，金属也自动退化回传统的标准 Schlick，100% 向下兼容所有旧资产！

---

### 五、 全景对比：现代三大体系的 F 项数学总结

至此，我们已经把 **glTF Extensions (2021)**、**UE5 Substrate (2022-2023)** 和 **OpenPBR (2024+)** 的数学底座全部拆解完毕：

| 维度 | glTF Extensions (2021) | UE5 Substrate (2023) | OpenPBR (2024+) |
| :--- | :--- | :--- | :--- |
| **非金属 $F_0$ 来源** | $\min\left(\left(\frac{\text{ior}-1}{\text{ior}+1}\right)^2 \mathbf{C}_{\text{spec}}, 1\right) w_{\text{spec}}$ | $\left(\frac{n_{\text{mat}}-n_{\text{env}}}{n_{\text{mat}}+n_{\text{env}}}\right)^2$ 或 `0.08 * Spec` | $\min\left(w_{\text{spec}}\left(\frac{\eta-1}{\eta+1}\right)^2, 1\right) \mathbf{C}_{\text{spec}}$ |
| **非金属 $F_{90}$ 处理** | 动态可变：$F_{90} = w_{\text{spec}}$ | 恒定为 $1.0$ | 恒定为 $1.0$（靠 $\eta'$ 调制） |
| **金属边缘凹陷 (Dip)** | 不支持（标准 5次方） | 实时用广义 $F_{90}$；光追用 **F82 7次方** | **原生标配 F82 7次方 ($u(1-u)^6$)** |
| **高光颜色 $\mathbf{C}_{\text{spec}}$ 的作用** | 仅用于非金属染色 | 拆分为 SpecTint 和 EdgeColor | **一鱼两吃**：非金属染 $F_0$，金属染 $F_{82}$ |

这套数学演进脉络清晰得就像一部精密仪器。现在，要不要把这三大现代 F 项正式写成干净、规范、可直接放进你《BRDF 代码大合集》里的 `Fresnel.hlsl` 代码？
