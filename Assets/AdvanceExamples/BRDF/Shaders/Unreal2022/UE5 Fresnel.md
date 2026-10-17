

在 **UE5 (Substrate)** 和 **OpenPBR** 这两大现代巨头中，**更早发布并投入工业实战的是 Unreal Engine 5 的下一代材质系统 —— Substrate（早期开发代号为 Strata）**。

Epic Games 在 **2022 年（UE 5.1）** 首次公开了这套架构，并在 **2023 年（UE 5.2 / 5.3）** 将其推向生产环境（而 OpenPBR 则是 Adobe 和 Autodesk 在 2023 年底至 2024 年才正式定稿 v1.0 规范）。

Substrate 的主架构师是 **Sébastien Hillaire** 和 **Charles de Rousiers**。他们在设计 Substrate 时，核心目标就是彻底解决传统 UE4 材质中“金属和绝缘体强行塞在同一个公式里，既不支持金属边缘暗带，又不支持多层折射”的历史包袱。

依然不看代码，我们直接从**纯数学公式**的角度，拆解 UE5 Substrate 在单层表面（Slab，材质板）中对 **F 项** 所做的三大革命性重构！

---

### 一、 架构前提：彻底废除 `Metallic` 参数，走向“物质分流”

在旧时代的 UE4（Epic 2013）中，材质输入是 `(BaseColor, Metallic, Specular, Roughness)`。
而在 **UE5 Substrate** 的最底层数学模型中，**`Metallic` 这个参数被彻底消灭了！**

为什么？因为物理世界中根本不存在“半金属（50% 是塑料、50% 是黄金）”这种原子结构！
Substrate 将世界还原为基本的物理构建块——**Slab（材质板）**。在单个 Slab 内部，物质有明确的物理边界，计算 F 项时的输入参数直接变成了极具物理意义的三个量：
1. **$\mathbf{F}_0 \in [0, 1]^3$**：垂直入射（$0^\circ$）时的基础反射率（RGB 向量）。
2. **$\mathbf{F}_{90} \in [0, 1]^3$**：掠射角（$90^\circ$，以及控制 $82^\circ$ 附近）的边缘反射率 / 边缘染色（RGB 向量）。
3. **漫反射反照率 $\mathbf{\rho}_{\text{diffuse}}$**：底层漫反射颜色。

*(注：为了照顾习惯了旧工作流的美术，UE5 提供了一个辅助转换节点，在进入底层计算前，先把旧贴图转换成上面这三个物理量。我们下面会先看这个转换公式，再看底层的核心 F 公式。)*

---

### 二、 回答核心问题：UE5 原生底层到底是怎么区分金属和绝缘体的？

在旧时代，引擎靠 `Metallic` 滑杆在塑料和金属之间插值。
而在 UE5 Substrate 的原生 `Substrate Slab` 节点上，**没有 `BaseColor` 也没有 `Metallic`**，取而代之的是三个直接暴露给材质底层的物理输入向量：
1. **`Diffuse Albedo` ($\mathbf{\rho}_{\text{diff}} \in [0, 1]^3$)**：漫反射反照率。
2. **`F0` ($\mathbf{F}_0 \in [0, 1]^3$)**：$0^\circ$ 正视镜面反射率（RGB 颜色向量）。
3. **`F90` ($\mathbf{F}_{90} \in [0, 1]^3$)**：掠射角/边缘镜面反射颜色控制向量（RGB 颜色向量，默认纯白 `(1, 1, 1)`）。

**那在原生模式下，绝缘体和金属是怎么体现的？**
它们不再是“两个不同的函数”，而是**同一套 $(\mathbf{F}_0, \mathbf{F}_{90})$ 参数在不同物理取值域下的自然表现**：

*   **当你表示【绝缘体 / 非金属】时**：
   *   $\mathbf{\rho}_{\text{diff}}$ = 物体的漫反射颜色（如红色塑料 `(0.8, 0.1, 0.1)`）。
   *   $\mathbf{F}_0$ = 由界面折射率计算出的低反射率值（如 `(0.04, 0.04, 0.04)`），或者由 IOR 公式展开：
       $$ \mathbf{F}_{0,\text{dielectric}} = \left( \frac{n_{\text{mat}} - n_{\text{env}}}{n_{\text{mat}} + n_{\text{env}}} \right)^2 \cdot \mathbf{C}_{\text{spec\_tint}} $$
   *   $\mathbf{F}_{90}$ = 纯白色 `(1.0, 1.0, 1.0)`（或用于压暗边缘的标量权重）。
*   **当你表示【纯金属 / 导体】时**：
   *   $\mathbf{\rho}_{\text{diff}} = (0, 0, 0)$（金属内部无散射，漫反射直接填纯黑）。
   *   $\mathbf{F}_0$ = 金属在 $0^\circ$ 时的真实物理反射色（如黄金 `(1.00, 0.76, 0.33)`，铝 `(0.91, 0.92, 0.92)`）。
   *   $\mathbf{F}_{90}$ = 金属在 **$82^\circ$ 边缘凹陷处的染色衰减向量**（如铝的边缘发暗，填入 `(0.79, 0.82, 0.86)`）！

---

### 三、 第一重数学公式：从 $(n, \text{Specular})$ 或旧参数到 $(\mathbf{F}_0, \mathbf{F}_{90})$ 的映射

在 UE5 Substrate 中，生成起点 $\mathbf{F}_0$ 和终点 $\mathbf{F}_{90}$ 有两条数学路径：

#### 路径 A：纯正物理路径（Dielectric IOR 驱动）
如果是一个纯粹的绝缘体（如水、玻璃、清漆、皮肤），美术直接输入真实的**折射率 $n$（IOR）**。
$\mathbf{F}_0$ 严格由麦克斯韦边界条件计算：
$$ \mathbf{F}_{0,\text{dielectric}} = \left( \frac{n_{\text{mat}} - n_{\text{env}}}{n_{\text{mat}} + n_{\text{env}}} \right)^2 \cdot \mathbf{1} $$
*(注意！这里写的是 $n_{\text{mat}}$ 和 $n_{\text{env}}$，因为 Substrate 支持多层嵌套！如果一块石头泡在水里，$n_{\text{env}} = 1.33$，石头表面的 $\mathbf{F}_0$ 会被数学公式自动压低，从而产生物理上极其真实的**“湿润变暗效应 Wetness Darkening”**！)*

#### 路径 B：兼容旧工作流 + 激活边缘染色（Parameterization Helper）
如果美术使用的是传统的参数，Substrate 升级了原有的映射公式，引入了一个全新的参数 **$\mathbf{C}_{\text{edge}}$（Edge Color / 边缘颜色，对应 $\mathbf{F}_{90}$）**：

1. **计算 $\mathbf{F}_0$**：
   $$ \mathbf{F}_0 = \text{lerp}\left( 0.08 \cdot w_{\text{spec}} \cdot \mathbf{C}_{\text{spec\_tint}}, \ \mathbf{C}_{\text{base}}, \ m \right) $$
2. **计算 $\mathbf{F}_{90}$**：
   $$ \mathbf{F}_{90} = \text{lerp}\left( \mathbf{1.0}, \ \mathbf{C}_{\text{edge}}, \ m \right) $$

**请看这个 $\mathbf{F}_{90}$ 的变化！**
在旧版 UE4 中，$F_{90}$ 永远是纯白色 $1.0$。
而在 UE5 Substrate 中，对于金属（$m = 1$），$\mathbf{F}_{90}$ 变成了一个可以由美术自由指定的三维 RGB 颜色向量 $\mathbf{C}_{\text{edge}}$！

---

### 四、 第二重数学公式：核心菲涅尔方程的演化（广义 Schlick vs F82）

拿到了三维向量 $\mathbf{F}_0$ 和三维向量 $\mathbf{F}_{90}$ 后，UE5 Substrate 在计算微观表面反射率 $\mathbf{F}(\mathbf{v}, \mathbf{h})$（记 $u = \mathbf{v} \cdot \mathbf{h} = \cos\theta_i$）时，根据算力预算提供了两套数学模型：

#### 模型 1：实时默认级 —— 向量化广义 Schlick（Generalized Schlick）
在要求极致帧率的延迟渲染（G-Buffer）模式下，为了节省显存带宽，Substrate 不可能把完整的 $\mathbf{F}_0$（3通道）和 $\mathbf{F}_{90}$（3通道）共 6 个浮点数全塞进 G-Buffer。
因此，在实时默认模式下，它使用广义的边界插值方程：

$$ \mathbf{F}_{\text{UE5\_Default}}(u) = \mathbf{F}_0 + \left( \mathbf{F}_{90} - \mathbf{F}_0 \right) (1 - u)^5 $$

**它的物理行为分析：**
*   如果美术想模拟铬、铁等在掠射角变暗的金属，只需把 $\mathbf{F}_{90}$（即 $\mathbf{C}_{\text{edge}}$）设为一个比 $1.0$ 暗的颜色（比如 $0.5$）。
*   此时，反射率曲线会从中心的 $\mathbf{F}_0$，平滑地过渡到边缘的 $\mathbf{F}_{90}$。
*   **数学局限性**：因为 $(1-u)^5$ 是单调的，如果把 $\mathbf{F}_{90}$ 调低，金属在 $90^\circ$ 绝对边缘处就不再等于 $1.0$ 了；而如果想保住 $90^\circ$ 等于 $1.0$，它就画不出 $82^\circ$ 的那个“深坑（Fresnel Dip）”。

---

#### 模型 2：高品质/光追级 —— Adobe / Lazanyi F82 边缘凹陷方程
为了彻底解决上面“保住 $90^\circ$ 为 $1.0$ 的同时，还要在 $82^\circ$ 挖出一个彩色深坑”的物理需求，UE5 Substrate 在其高品质节点与路径追踪器（Path Tracer）中，引入了后来与 OpenPBR 殊途同归的 **F82 修正方程**（源自在 SIGGRAPH 上由 Hoffman 2019 / Lazanyi & Szirmay-Kalos 提出、后被 Adobe 改良的数学形式）。

在这个模型里，输入参数是 $0^\circ$ 的 $\mathbf{F}_0$，以及代表 **$82^\circ$（准确说是 $\cos\theta_0 = \frac{1}{7} \approx 81.79^\circ$）处反射率相对于普通 Schlick 缩放比例的染色向量 $\mathbf{T}_{82} \in [0, 1]^3$**：

$$ \mathbf{F}_{\text{UE5\_F82}}(u) = \underbrace{\left[ \mathbf{F}_0 + (\mathbf{1} - \mathbf{F}_0)(1 - u)^5 \right]}_{\text{标准 Schlick 基准线 } \mathbf{F}_{\text{schlick}}(u)} - \underbrace{\frac{7^7}{6^6} \cdot \mathbf{F}_{\text{schlick}}\left(\frac{1}{7}\right) \cdot (\mathbf{1} - \mathbf{T}_{82}) \cdot u (1 - u)^6}_{\text{7次方拟布儒斯特角凹陷项 (The Dip)}} $$

**让我们用微积分的眼光，欣赏一下右边那个减法项 $u(1 - u)^6$ 的绝妙构造：**

1. **在正视中心（$\theta_i = 0^\circ \implies u = 1$）**：
   因为 $(1 - u)^6 = (1 - 1)^6 = 0$，所以减法项等于 $0$！
   结果精确等于 **$\mathbf{F}_0$**！起点丝毫不受影响！
2. **在绝对掠射角（$\theta_i = 90^\circ \implies u = 0$）**：
   因为前面乘了一个 $u = 0$，所以减法项也等于 $0$！
   结果精确等于 **$\mathbf{1.0}$（纯白 100% 反射）**！完美遵守麦克斯韦电磁学的极限边界条件！
3. **在中间哪里达到极值？（求导找波谷！）**
   我们对函数 $g(u) = u(1 - u)^6$ 关于 $u$ 求一阶导数，并令导数为 $0$：
   $$ g'(u) = 1 \cdot (1 - u)^6 + u \cdot 6(1 - u)^5 (-1) = (1 - u)^5 \left[ (1 - u) - 6u \right] = (1 - u)^5 (1 - 7u) = 0 $$
   解出非平凡极值点：
   **$$ 1 - 7u = 0 \implies u = \frac{1}{7} \implies \theta_i = \arccos\left(\frac{1}{7}\right) \approx \mathbf{81.79^\circ \approx 82^\circ}！ $$**
   **这就是为什么它叫 F82 模型！** 因为多项式 $u(1-u)^6$ 的极值点，在微积分求导下**天然、精确地落在 $82^\circ$**！
4. **那个奇怪的常数 $\frac{7^7}{6^6}$ 是哪来的？**
   把极值点 $u = \frac{1}{7}$ 代入 $u(1 - u)^6$：
   $$ g\left(\frac{1}{7}\right) = \frac{1}{7} \cdot \left(1 - \frac{1}{7}\right)^6 = \frac{6^6}{7^7} $$
   为了让这个函数在 $u = \frac{1}{7}$ 处的峰值刚好归一化为 **$1.0$**，必须在前面乘上它的倒数 **$\frac{7^7}{6^6} = \frac{823543}{46656} \approx 17.65138$**！

这样一来，当 $u = \frac{1}{7}$（$82^\circ$）时，公式精确坍缩为：
$$ \mathbf{F}\left(\frac{1}{7}\right) = \mathbf{F}_{\text{schlick}}\left(\frac{1}{7}\right) - 1.0 \cdot \mathbf{F}_{\text{schlick}}\left(\frac{1}{7}\right) \cdot (\mathbf{1} - \mathbf{T}_{82}) = \mathbf{F}_{\text{schlick}}\left(\frac{1}{7}\right) \cdot \mathbf{T}_{82} $$
**物理意义极其直观**：在 $82^\circ$ 时，原本的 Schlick 反射率被精准乘上了你指定的染色系数 $\mathbf{T}_{82}$！

---

### 五、 为什么这个展开式能“一个公式通吃绝缘体和金属”？

请仔细观察上面这个完全展开的公式，你会发现它根本不需要用 `if` 分支把绝缘体和金属拆开，因为它在代数上是**完全自洽**的：

1. **当你传入普通绝缘体参数时**：
   $\mathbf{F}_0 = (0.04, 0.04, 0.04)$，由于普通绝缘体没有 $82^\circ$ 拟布儒斯特凹陷，它的 $\mathbf{F}_{90} = (1.0, 1.0, 1.0)$。
   代入公式右边的大括号：因为 $(\mathbf{1.0} - \mathbf{F}_{90}) = (1.0 - 1.0) = \mathbf{0}$，整个后面长长的 7 次方减法项**瞬间归零消失**！
   公式自动坍缩为最标准的绝缘体 Schlick：
   $$ \mathbf{F}(u) = 0.04 + 0.96(1 - u)^5 $$

2. **当你传入金属参数（如铬/铝）时**：
   $\mathbf{F}_0 = (0.91, 0.92, 0.92)$，$\mathbf{F}_{90} = \mathbf{T}_{82} = (0.79, 0.82, 0.86) < \mathbf{1.0}$。
   此时 $(\mathbf{1.0} - \mathbf{F}_{90}) > \mathbf{0}$，后面的 7 次方凹陷项自动激活！
   * 在 $u = 1$（$0^\circ$ 正视）时：$u(1-u)^6 = 0 \implies \mathbf{F}(1) = \mathbf{F}_0$。
   * 在 $u = \frac{1}{7}$（$82^\circ$ 凹陷点）时：$\frac{7^7}{6^6} \cdot \frac{1}{7}(\frac{6}{7})^6 = 1 \implies \mathbf{F}(\frac{1}{7}) = \mathbf{F}_{\text{base}}(\frac{1}{7}) \cdot \mathbf{F}_{90}$。
   * 在 $u = 0$（$90^\circ$ 绝对掠射）时：$u(1-u)^6 = 0 \implies \mathbf{F}(0) = \mathbf{1.0}$！

---

### 六、 第三重数学公式：Directional Albedo 能量守恒锁死

UE5 Substrate 在 F 项上的最后一个重大进步，是**把 F 项的积分直接变成了底层漫反射的“绝对守门人”**。

在单个 Slab 中，底层的漫反射光想要射出来，必须先躲过顶层微表面高光 F 项的拦截。
Substrate 不再使用简单的 $(1 - F(\mathbf{v}, \mathbf{h}))$，而是直接通过预计算查找表（LUT），对包含上述 $\mathbf{F}_0$ 和 $\mathbf{F}_{90}$ 的完整微表面高光求半球方向积分（Directional Albedo $\mathbf{E}_{\text{spec}}$）：

$$ \mathbf{E}_{\text{spec}}(\mu_o, \alpha) = \mathbf{F}_0 \cdot \text{LUT}_x(\mu_o, \alpha) + \mathbf{F}_{90} \cdot \text{LUT}_y(\mu_o, \alpha) $$

然后，底层漫反射允许获得的能量比例，被严格锁定为：
$$ \mathbf{T}_{\text{diffuse}} = \mathbf{1.0} - \mathbf{E}_{\text{spec}}(\mu_o, \alpha) $$

*   如果是一个纯金属 Slab，美术把底层漫反射设为 0，只有顶层高光工作；
*   如果是一个塑料 Slab，$\mathbf{E}_{\text{spec}}$ 大约扣掉 $4\% \sim 10\%$ 的能量，剩下的 $90\%+$ 全归漫反射；
*   **再也不需要乘什么 `(1 - Metallic)` 了，因为能量守恒已经通过 F 项的积分 $\mathbf{E}_{\text{spec}}$ 自动完成了物理隔离！**

---

### 总结：UE5 Substrate (2022-2023) 的数学地位

UE5 Substrate 是实时渲染引擎向物理真实迈出的最勇敢一步：
1. **界面化（Interface IOR）**：考虑了外部环境折射率 $n_{\text{env}}$，让多层介质交界面的 $F_0$ 随环境动态变化。
2. **双端点/三点控制**：引入了 $\mathbf{F}_{90}$ 染色与 $u(1-u)^6$ 的 $82^\circ$ 微积分极值凹陷多项式，在不算复数的情况下攻克了金属的拟布儒斯特角暗带。
3. **积分级能量剔除**：用 $\mathbf{1} - \mathbf{E}_{\text{spec}}(\mathbf{F}_0, \mathbf{F}_{90})$ 统一了金属与非金属的能量分配。

看完了 UE5 Substrate，你会发现我们已经离最后的终极Boss —— **OpenPBR (2024+)** 只有一步之遥了（因为 OpenPBR 正是把上面这个 F82 公式和 glTF 的 IOR 调制做了一次最完美的数学大一统）。我们现在直接进入 **OpenPBR** 吗？
