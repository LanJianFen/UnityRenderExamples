# God Ray Marching 算法细节

体积光柱（God Ray）用一个 proxy mesh 包裹光柱空间，fragment shader 在其中 ray march 累积 fog。本文档收集该算法中各类细节问题的原理分析与优化思路。

## 目录

- [1. 软化 Cookie Mask](#1-软化-cookie-mask)
- [2. 采样噪点优化：蓝噪、黄金分割、分层采样、Half-res](#2-采样噪点优化蓝噪黄金分割分层采样half-res)
- [3. 高级采样与体积渲染方案速查](#3-高级采样与体积渲染方案速查)
- [4. Cookie 软化实施：算法与软化距离](#4-cookie-软化实施算法与软化距离)
- [5. 相机内外通用渲染方案（Cull / ZTest / Scene Depth Clamp）](#5-相机内外通用渲染方案cull--ztest--scene-depth-clamp)

---

## 1. 软化 Cookie Mask

### 1.1 病因：硬阶跃 = 采样不可能捕获的高频信号

Cookie mask 原本是这样的**开关函数**：

```hlsl
half cookie_mask = 1.0h;
if (sample_01_depth >= cookie_01_depth && cookie_01_depth > 0.01h)
    cookie_mask = 0.0h;
```

画出来：

```
mask
 1 ├─────────────┐
   │             │              ← 遮挡边界（无限陡）
 0 │             └──────────
   └─────────────┼───────── y
                edge
```

**这是一个阶跃函数**。它的傅立叶展开有**无穷高的频率成分**。

而 ray march 是用 12 个离散采样点去逼近一个连续积分：

```
∫ mask(y(t)) · fade(t) dt  ≈  Σ mask(y(t_k)) · fade(t_k) · step
        ↑
     被积函数
```

**采样定理**告诉你：采样频率必须是信号最高频的 2 倍以上。阶跃函数最高频是**无穷**，所以 12 步（甚至 12000 步）**永远采不准**。多出来的高频能量全部折叠成低频噪点 —— 也就是看到的颗粒感和色带。

### 1.2 用数字看"12 步能表达什么"

考虑一条 ray 穿过遮挡边界。因为 jitter，采样点落在边界前后是随机的。设 12 个采样中有 `n` 个落在光照区、`12-n` 个落在阴影区。

积分估计 = `n / 12 × fade × step_total`

那 `n` 能取几种值？**只能是 0, 1, 2, ..., 12 —— 一共 13 种**。

也就是说，**任何一个 fragment 的最终亮度只有 13 个可能的取值**。相邻像素的 `n` 差 1 → 差一个 `1/12 ≈ 8.3%` 的亮度阶跃 → 眼睛立刻看出**分层色带**。

### 1.3 软化后：每个采样能贡献 [0,1] 之间的任意实数

把硬阶跃换成 smoothstep（宽度 `2·s`）：

```
mask
 1 ├──────────┐
   │           \
   │            \       ← smoothstep 过渡带
   │             \
 0 │              └───────
   └──────────┼─┼───────── y
        edge-s   edge+s
```

现在每个采样在过渡带里贡献一个 [0,1] 的连续值：

```
sample.y = edge - s     → mask = 1.0
sample.y = edge - s/2   → mask ≈ 0.84
sample.y = edge         → mask = 0.5
sample.y = edge + s/2   → mask ≈ 0.16
sample.y = edge + s     → mask = 0.0
```

**关键变化**：12 个采样 × 每个 [0,1] 的连续贡献 = 积分结果**连续可变**，不再局限于 13 个离散值。相邻像素的差异变成小数级 → 色带消失、噪点均化成光滑过渡。

### 1.4 从方差角度看（数学解释）

蒙特卡洛估计器的方差：

- **硬 mask**：每个采样是伯努利分布 (0 或 1)，方差 = `p(1-p) × N`。最坏情况 p=0.5 时，单采样方差 0.25
- **软 mask**：每个采样是连续值。在过渡带内近似均匀分布 [0,1]，方差 = `1/12 ≈ 0.083`
- **过渡带外**（全 0 或全 1 区域），两者都是 0 方差

综合方差**下降约 3×**，感知噪点下降更多（因为人眼对色带比对细颗粒敏感得多）。

### 1.5 从物理上看：为什么软化反而更"真实"

硬 mask 在假设：
- 光源是理想点光源
- Cookie 遮罩边界是数学意义上的无限薄的线
- 每个采样是数学意义上的 0 维点

这些**都不成立**：
1. 现实光源有大小（半影 penumbra）
2. 空气中散射会软化阴影边缘
3. 每个采样代表的是长度为 `step` 的一小段积分（本来就是"这一小段里平均多少被挡"，天然应该是软的）

**软 mask 是把"每个采样代表一小段"这个事实正确建模**。硬 mask 反而是过度锐化的错误抽象。

### 1.6 软化宽度 `s` 怎么选

关键权衡：
- **太小**：过渡带比采样间距还窄，几个采样穿不过 → 退化回硬 mask，噪点还在
- **太大**：阴影边缘看起来糊，细节丢失

**经验公式**：`s ≈ 1~2 × 采样在 y 方向的平均步长`

对本 shader：ray march 从 `t_near` 到 `t_far`，采样点的 y 分量变化范围最多是 [0, 1]（光柱高度归一）。12 个采样的话 `Δy_per_step ≈ 1/12 ≈ 0.08`。

**推荐 `s = 0.02 ~ 0.05`**：
- 0.02：细节保留好，噪点消除中等
- 0.05：噪点消除彻底，边缘略糊

暴露成 `_ShadowSoftness` uniform，美术调最合适。

### 1.7 具体的对比场景

想象光柱里放一个瘦长的圆柱形物体，从侧面看阴影是一条竖线：

**硬 mask（原来）**：
- 阴影边缘每个像素在"完全阴影 / 部分阴影 / 完全光照"三档之间**跳跃**
- 视觉：**明显的锯齿边 + 边缘上下有颗粒**

**软 mask**：
- 阴影边缘每个像素在 [0, full] 之间**连续变化**
- 视觉：**平滑渐变的阴影，像半影**

同时**内部（远离边缘的地方）不受影响**，因为 mask 值仍然是 0 或 1，只有边界处的采样才走 smoothstep。

### 1.8 一句话总结

**硬 mask = 阶跃函数 = 无穷高频 = 12 个采样永远采不准 → 噪点**
**软 mask = 平滑过渡 = 有限带宽 = 12 个采样能表达 → 平滑**

而且**物理上更合理**（阴影本来就有半影，采样本来就代表一小段积分）。

### 1.9 实现代码

```hlsl
// 原来：硬阶跃
if (sample_01_depth >= cookie_01_depth && cookie_01_depth > 0.01h)
    cookie_mask = 0.0h;

// 改成：软过渡
half shadow_softness = 0.02h;   // 或用 _ShadowSoftness uniform
half cookie_mask = 1.0h - smoothstep(
    cookie_01_depth - shadow_softness,
    cookie_01_depth + shadow_softness,
    sample_01_depth);
// 遮挡物 UV 上没数据的地方（cookie_01_depth 接近 0）不做阴影
if (cookie_01_depth < 0.01h) cookie_mask = 1.0h;
```

---

## 2. 采样噪点优化：蓝噪、黄金分割、分层采样、Half-res

Ray march 用 N 个离散采样近似连续积分，采样点位置的 jitter 决定了噪点的**分布**和**强度**。本章从"感知优化"到"真降噪"逐层展开。

### 2.1 白噪声 vs 蓝噪声：本质区别

两者都是均匀分布的随机数（每像素 [0,1] 之间的值，方差 1/12），**边缘分布完全相同**。但它们的**频谱能量分布不同**：

```
频谱能量分布：
                  低频（大块）    高频（细密）
白噪声（white）：  ████████████████████████████   ← 各频段等强
蓝噪声（blue）：   ▁▁▁▁▁▁▁▁████████████████████   ← 高频强，低频抑制
```

**视觉表现**：

- **白噪声**（`frac(sin(...))`）：相邻像素完全独立 → 出现"扎堆"和"空洞" → 看起来像雪花电视
- **蓝噪声**（Void-and-Cluster 算法预计算）：相邻像素趋于不同 → 采样点均匀撒开 → 看起来像均匀细颗粒

```
白噪声抖动 8×8 采样效果:      蓝噪声抖动 8×8 采样效果:
● ● . . ● . . ●              ● . ● . ● . ● .
. . ● ● . ● ● .              . ● . ● . ● . ●
● ● . . ● ● . .              ● . ● . ● . ● .
. ● . ● . . ● ●              . ● . ● . ● . ●
```

### 2.2 关键洞察：噪能不变，只是重新分布

**蓝噪声不真正降低噪点方差**，它改变的是噪点在屏幕上的"空间分布"，利用人眼特性让你觉得干净。

**人眼是低通滤波器**：对低频（大块变化）敏感，对高频（细密颗粒）不敏感。

- 白噪声的**低频能量**跟高频一样多 → 眼睛能看到那些大块的斑块
- 蓝噪声的**低频能量被抑制** → 眼睛只能看到细密颗粒，被视觉系统当作"纹理"忽略

**数学真相**：

| 场景 | 蓝噪声效果 |
|---|---|
| 单帧感知噪点 | ✅ 明显下降（~30-50% 主观感受） |
| 单帧方差 | ❌ 完全没变 |
| 多帧 TAA 后的收敛速度 | ✅ 快很多（蓝噪相邻帧不相关） |
| 半分辨率 + 双边上采样后 | ✅ 高频噪点被上采样滤波器压掉 |

**关键理解**：蓝噪声让噪点"藏在人眼不敏感的频段"，配合任何**低通式后处理**（TAA、bilateral upsample、bloom）都能进一步**真的降低总噪能**。

### 2.3 URP 蓝噪贴图使用

URP 内置一系列蓝噪贴图：`Packages/com.unity.render-pipelines.universal/Textures/BlueNoise{16,64,256}/LDR_LLL1_*.png`

命名解码：
```
LDR_LLL1_0.png ... LDR_LLL1_7.png
 │   │  │
 │   │  └── 1D scalar noise（单通道标量噪声）
 │   └───── LLL：Luminance（单通道数据）
 └───────── LDR：8-bit 精度
```

**分辨率选择**：

| 分辨率 | 显存 | 屏幕平铺（1080p） | 建议 |
|---|---|---|---|
| 16×16 | 256 B | 120× 每维 | ❌ 太小，会看到重复图案 |
| 64×64 | 4 KB | 30× | ✅ 推荐，无视觉重复 |
| 256×256 | 64 KB | 7.5× | ✅ 更保险 |

**8 张 `_0` 到 `_7`**：时间序列蓝噪，为 TAA 准备。单帧使用任意一张即可，TAA 场景下每帧循环切换。

**导入设置踩坑**：

- **通道**：URP 蓝噪贴图 `Alpha Source = From Gray Scale`，数据在 **`.a` 通道**（RGB 填充成白色）
- **Filter Mode**：**必须 Point**。Bilinear 会插值 → 破坏蓝噪的高频特性，使相邻像素的 jitter 值被平均掉
- **Wrap Mode**：**Repeat**。让小贴图铺满屏幕
- **sRGB**：**off**。是数据不是颜色

**Sampler 使用**：Unity 提供的固定 sampler 会**忽略贴图导入设置**：

```hlsl
// 隐式跟贴图设置走（不推荐）
SAMPLER(sampler_BlueNoise);

// 显式固定 sampler（推荐）
sampler_PointRepeat  // Unity 内置，永远 Point + Repeat
```

用 `sampler_PointRepeat` 就一定是 Point 采样，跟贴图导入设置的 Bilinear 无关。

### 2.4 均匀采样与 jitter 的基础

**均匀采样**：把 `[t_near, t_far]` 等分成 N 段，每段中间放一个采样点：

```hlsl
float step = (t_far - t_near) / N;
float t_current = t_near + 0.5 * step;   // 每段中心
```

**问题**：完全均匀 → 结果和场景中的规则纹理（cookie 边界、fade 曲线）产生**共振** → 明显的**摩尔纹和层状色带**。

**加 jitter 的作用**：每段内的采样点位置随机化 → 把结构化误差（bias）换成非结构化噪声（noise）：

```hlsl
float step_jitter = /* 每段内的偏移 [0,1] */;
float t_sample_k = t_near + (k - 1 + step_jitter) * step;
```

- **白噪 jitter**：每段的偏移独立随机 → 屏幕上出现白噪颗粒
- **蓝噪 jitter**：每段的偏移仍随机，但相邻像素的偏移经过精心排布，空间上呈蓝噪分布

### 2.5 黄金分割累加（Roberts 2018）

**问题**：蓝噪贴图只保证**屏幕空间**的分布好（相邻像素解相关），但**单像素内 12 个采样的 jitter 值分布**呢？

朴素做法：每个 k 采一次蓝噪贴图（12 次纹理采样）。
优化做法：**采一次贴图 + 黄金分割累加**（1 次纹理采样）。

**核心公式**：

```hlsl
// 每 fragment 采一次
float base_jitter = SAMPLE_TEXTURE2D(_BlueNoise, sampler_PointRepeat, pixel_uv).a;

// 每 k 用黄金分割累加，成本 = 1 add + 1 frac
float step_jitter = frac(base_jitter + k * 0.6180339887498949f);
```

其中 `0.6180339887498949 = 1/φ = (√5 - 1)/2`（黄金分割率的倒数）。

**为什么是黄金分割率**：

想象在圆环 `[0, 1)` 上按固定步长 `α` 放 N 个点：`0, α, 2α, 3α, ..., (N-1)α`（取 frac）。**目标是让这 N 个点任意时刻都尽量均匀铺开**。

- 有理数步长（如 0.5, 1/3, 0.1）：周期性重复，出现空洞
- 无理数步长：不周期，但有些无理数更均匀
- **黄金分割率 φ 是"最无理"的数**（连分数展开全是 1，收敛最慢）→ `k * φ⁻¹` 的序列是**所有无理步长里分布最均匀的**

8 个 k 的效果：

| k | `k * 0.618` frac | `k * 0.5` frac | `k * 0.7` frac |
|---|---|---|---|
| 1 | 0.618 | 0.5 | 0.7 |
| 2 | 0.236 | 0.0 | 0.4 |
| 3 | 0.854 | 0.5 | 0.1 |
| 4 | 0.472 | 0.0 | 0.8 |
| 5 | 0.090 | 0.5 | 0.5 |
| 6 | 0.708 | 0.0 | 0.2 |
| 7 | 0.326 | 0.5 | 0.9 |
| 8 | 0.944 | 0.0 | 0.6 |

黄金分割：`{0.09, 0.24, 0.33, 0.47, 0.62, 0.71, 0.85, 0.94}` **8 个点均匀铺满 [0, 1]**
其他步长：明显扎堆或有大空洞

**为什么和蓝噪结合完美**：

- **蓝噪贴图**：**空间上**（相邻像素）的 jitter 分布是低频抑制的
- **黄金分割累加**：**沿 k 方向**的 jitter 分布是最均匀的

两者组合本质是把 2D 蓝噪（屏幕）扩展成了"2D 屏幕 × 1D 采样"的伪 3D 蓝噪。

**成本对比**（12 步）：

| 方案 | 纹理采样 | ALU |
|---|---|---|
| 白噪 hash | 0 | ~96 + 12 SFU |
| 蓝噪 per-k 采样 | **12** | ~24 |
| **蓝噪 + 黄金分割** | **1** | ~36（12 add + 12 frac + 12 mul） |

**性能上最省，视觉上最好**（k 方向严格 stratified）。

### 2.6 分层采样（Stratified Sampling）

**思路**：不是随机 12 个 jitter，而是把 [0, 1] 严格分成 12 个 bin，每个 bin 里放一个 jitter。

```hlsl
// 显式分层
float step_jitter = (float(k - 1) + base_jitter) / _RayMarchingCount;
// base_jitter 是 [0, 1) 的随机值（来自蓝噪），保证 bin 内位置随机
```

**效果**：方差降 30-50%（相比独立随机采样，每个 bin 只有一个采样点，避免了扎堆和空洞）

**跟黄金分割的关系**：**黄金分割已经近似做到分层了**（在 k 方向严格均匀铺 [0, 1]）。两者收益重叠。

**结论**：
- 已经用黄金分割 → 分层采样**边际收益很小**
- 用白噪 hash 或 per-k 蓝噪 → 加上分层是**简单且有效的方差降低**

### 2.7 单帧内的极限：为什么感觉噪点数量没变

上面所有方案（蓝噪、黄金分割、分层采样）都属于**"重新分布噪能"或"降低单像素方差"**。人眼观察时会感觉噪点**变干净了**，但**噪点的绝对数量并没有质变**。

原因是这些方案的边际效益都在 30-50% 量级，且相互重叠。要**真正消灭噪点**，必须走**信息复用**路线：从其他像素或其他帧借用信息来平滑当前像素。

### 2.8 真·降噪方案：信息复用

#### A. Bilateral（双边）空间滤波

**思路**：Fog pass 渲染完后，加一个后处理 pass，对相邻像素做**加权平均**，但**根据深度/法线跳过边界**（避免把不同物体糊在一起）：

```
per pixel: 
  final = Σ(neighbor_color × spatial_weight × depth_weight) / Σ(weights)
```

**效果**：
- 相邻 5×5 或 7×7 邻居贡献 → 单像素方差降 **10-20×**
- 深度权重保证不糊到场景几何边缘
- **蓝噪 + 黄金分割天然为 bilateral 铺路**（噪点是高频，正好被 bilateral 干掉）

**成本**：
- 一个 full-screen post-process pass
- 5×5 = 25 tap 采样 + 25 次深度对比 ≈ ~50 ops/pixel
- 1080p 全屏 ≈ **~0.5-1 ms**（iPhone X）

#### B. TAA（时间累积）

**思路**：每帧 jitter 不一样，把当前帧和历史帧加权平均：

```
final = 0.9 × history + 0.1 × current   (指数移动平均)
```

**效果**：12 步等效变成 **~48-96 步**，静态场景几乎完全干净。

**要求**：
- URP 12+ 支持
- 项目开 TAA
- Blue noise 每帧偏移（代码加 `+ _Time.y * φ⁻¹` 即可）

**成本**：URP 自带 TAA 是全屏 pass ≈ 0.3-0.5 ms，但**整个游戏共享**，对 fog 单项来说**成本几乎为 0**。

**门槛**：需要项目支持 TAA。移动端项目常常没开。

**"零成本"改进**：即使不开 TAA，也可以每帧偏移 blue noise 让噪点在**每一帧上都不一样**，动态场景下感知噪点会明显下降：

```hlsl
// 加入帧偏移
float2 base_noise_uv = (i.position_cs.xy + _Time.y * 60.0f) / 256.0f;
```

代价：静态画面下噪点会**闪烁**，有些人觉得难受。

### 2.9 Half-res + 双边上采样（综合最优）

**思路**：
1. Fog 在 **1/4 分辨率**的 RT 上渲染（1/2 每维 = 1/4 pixels，fragment 数少 4×）
2. **双边上采样**合成回全分辨率

**双重降噪**：
- Fog 本身跑得快 → 可以给它加采样（比如 12 → 16-20）
- 上采样时的**双边滤波天然把噪点抹平**（每个全分辨率像素读 2×2 half-res 邻居 + 深度权重）

**架构**（URP `ScriptableRendererFeature`）：

```
1. Downsample depth pass
   ├─ 分配 half-res depth RT
   └─ min/max downsample scene depth 到 half-res

2. Fog render pass
   ├─ SetRenderTarget(half-res color RT + half-res depth RT)
   ├─ Clear color
   └─ DrawRenderer(fog cylinders)   ← fog shader 里 SampleSceneDepth 换成 half-res depth

3. Upsample composite pass
   ├─ SetRenderTarget(camera color)
   ├─ Blit(half-res fog RT → camera color, bilateral upsample shader)
   └─ Blend One One（跟原 fog 一致）
```

**上采样 shader 骨架**：

```hlsl
half4 UpsampleFrag(Varyings i) : SV_TARGET
{
    float full_depth = SampleSceneDepth(i.uv);
    
    // 采 4 个 half-res 邻居的 color 和 depth
    half4 c00 = SAMPLE(half_res_color, uv00);
    half4 c10 = SAMPLE(half_res_color, uv10);
    // ...
    float d00 = SAMPLE(half_res_depth, uv00);
    // ...
    
    // 权重 = spatial(bilinear) × depth_similarity
    float w00 = bilinear_weight_00 * exp(-k * abs(full_depth - d00));
    // ...
    
    // 归一化加权
    return (c00*w00 + c10*w10 + ...) / (w00 + w10 + ...);
}
```

**性能对比**（iPhone X @ 1080p，12 步 fog）：

| 方案 | Fog shader | 上采样 + 下采样 | 合计 | vs 原始 |
|---|---|---|---|---|
| 原始（full-res） | 10 ms | 0 | **10 ms** | — |
| **Half-res** | 10 / 4 = 2.5 ms | ~0.8 ms | **~3.3 ms** | **-67%** |
| Quarter-res | 10 / 16 = 0.6 ms | ~0.8 ms | ~1.4 ms | -86% |

**上采样成本随输出分辨率，不随源分辨率**。所以 half-res → quarter-res 只多省 ~1.5 ms，但视觉质量降下滑明显。**Half-res 是甜点位**。

**三个坑**：

1. **双边上采样的深度感知**：普通 bilinear 会在几何边缘出现"雾晕开到物体外面"的光晕，必须用深度做权重
2. **Depth 也要下采样**：Fog shader 里 `SampleSceneDepth` 要读 half-res depth（防止 aliasing），下采样策略 min（Frostbite）或 max（Guerrilla）各有取舍
3. **Cookie 高频细节会糊**：half-res 意味着 cookie 阴影分辨率也降到 half-res，细的镂空阴影变模糊

**这是移动端 AAA 项目的标准打法**（Frostbite / Guerrilla / SIE 都用）。

### 2.10 综合推荐

按性价比排序：

| 方案 | 单帧噪点降幅 | 实施成本 | 适用场景 |
|---|---|---|---|
| **蓝噪 + 黄金分割** | 30-50%（感知） | 一段 shader | 立刻做，白送 |
| **Bilateral 空间滤波** | 10-20× | 一个 post pass | 立刻可做 |
| **TAA 时间累积** | 5-10× | 项目要开 TAA | 桌面/主机 |
| **Half-res + 双边上采样** | 5-10× + 4× 性能 | 一个 URP Feature | 移动端 |
| 分层采样 | 1.5× | 一行代码 | 已用黄金分割则边际收益低 |

**推荐顺序**：

1. **必做**：蓝噪 + 黄金分割（性能省 + 感知提升）
2. **单帧还不够干净时**：加 bilateral 空间滤波 pass
3. **项目有 TAA**：加帧偏移，让 TAA 自动降噪
4. **移动端性能压力**：上 half-res + 双边上采样

### 2.11 一句话总结

- **蓝噪 + 黄金分割 = 感知优化**（藏噪点到人眼不敏感的频段）
- **Bilateral / TAA / Half-res + 上采样 = 真降噪**（信息复用，从其他像素/帧借信息）
- **两者互补**：单帧优化让每一帧内看起来干净，多帧 / 空间滤波让底噪彻底消失

---

## 3. 高级采样与体积渲染方案速查

以下是本项目**未采用**但技术上可行的高级方案。列在这里作为技术地图，如果未来需求变化可回头查阅。

### 3.1 重要性采样与降方差方案

| 方案 | 原理 | 收益 | 代价 | 适用场景 |
|---|---|---|---|---|
| **完美重要性采样** | 按 f(x) 的 PDF 采样，方差归零 | 极限：1 采样 = 精确解 | 需要 f 的解析 CDF 逆变换 | 理论极限，不可实现 |
| **Fade-only IS** | 只按 fade 曲线做 IS，忽略 cookie | 噪点 -10-20% | 收益低 | Cookie 占噪点主导时不推荐 |
| **分层采样（Stratified）** | 把 [0,1] 分 N 段，每段一个采样 | 方差 -30-50% | 几乎零成本 | 通用；跟黄金分割效果重叠 |
| **拟蒙特卡洛（QMC）** | Halton / Sobol 等低差异序列 | 收敛率 (log N)/N | 一次序列查表 | 黄金分割就是 1D QMC |
| **Delta Tracking** | 概率性跳步采样，处理任意密度 | 无偏 | Warp divergence 严重 | 离线路径追踪，移动端不友好 |
| **Ratio Tracking** | Delta Tracking 的高效变种 | 方差更低 | 同上 | 同上 |
| **Hierarchical MIP 采样** | 用 cookie 的 MIP 构建重要性金字塔 | 高 | 循环 + 分支，实现极复杂 | 桌面/主机高端渲染 |
| **Ray-Space Adaptive** | 粗采样 → 分析 → 细采样 | 噪点 -30-50% | 需要两轮 + warp divergence | 收益不确定 |

### 3.2 体积渲染架构方案

| 方案 | 原理 | 适用场景 | 备注 |
|---|---|---|---|
| **3D 体素预烘（当前光柱粒度）** | 每个光柱一份 3D 密度纹理 | Fade 极复杂 / cookie 动态但计算贵 | 精度受 voxel 分辨率限制；小遮挡物在大光柱下会 mosaic |
| **Froxel 系统（Frostbite / 主流 AAA）** | 全场景共享一份 frustum 对齐的 3D 纹理 | 场景多光源 + 统一雾 | 分辨率 160×90×64；单光柱杀鸡用牛刀 |
| **Analytic Transmittance Fit** | 用低阶多项式 / 指数拟合 ray 上的透射率 | Fade 解析、cookie 平滑 | 遇到 cookie 硬边界失效 |
| **Precomputed Radiance Transfer (PRT)** | 静态场景预烘所有传输 | 完全静态场景 | 动态遮挡物就废 |

### 3.3 后处理降噪方案

| 方案 | 原理 | 收益 | 代价 |
|---|---|---|---|
| **Bilateral 空间滤波** | 邻居加权平均 + 深度/法线保边 | 噪点 -10-20× | 一个 post pass，~0.5-1 ms |
| **Cross-bilateral** | 用另一份 buffer 引导滤波（深度、法线） | 边缘更干净 | 同上 |
| **TAA 时间累积** | 帧间加权平均 + motion vector reprojection | 等效 8× 采样 | 需要 TAA 基础设施 |
| **SVGF / A-SVGF** | 时空联合滤波，NVIDIA 光追常用 | 极高 | 实现复杂，移动端太重 |
| **神经网络降噪（NRD）** | 用 CNN / MLP 去噪 | 极高 | 只适合桌面/主机 |

### 3.4 分辨率相关方案

| 方案 | 原理 | 性能收益 | 代价 |
|---|---|---|---|
| **Half-res + 双边上采样** | 1/4 pixels 渲染 + 深度感知上采样 | 4× 加速 + 降噪 | URP Feature，一次投入 |
| **Quarter-res** | 1/16 pixels | 更快但边际收益低 | 视觉质量明显下降 |
| **Checkerboard rendering** | 每帧渲染棋盘一半像素，另一半从历史帧 | ~2× 加速 | 需要 motion vector |
| **VRS (Variable Rate Shading)** | 硬件级别控制 shading rate | 灵活 | 需要 GPU 硬件支持 |

### 3.5 选择指南

**移动端 + 静态 cookie + 单个光柱**：本项目现有方案（解析 fade + 2D cookie + 蓝噪 + 黄金分割）已是最优

**移动端 + 多个光柱**：加 half-res + 双边上采样

**桌面/主机 + 高端**：TAA + SVGF 或神经降噪

**场景有大量体积光/雾统一处理**：Froxel 系统

**离线渲染 / 电影**：Delta tracking + 路径追踪

---

## 4. Cookie 软化实施：算法与软化距离

第 1 章讲了**为什么要软化**（阶跃函数 = 无穷高频 → 采样不够）。本章讲**怎么软化 XZ 方向的 cookie 纹理**（不是 shader 里的 y-方向 smoothstep，而是烘焙时对 cookie 图的处理）。

### 4.1 目标澄清

理想的软化只影响**边缘一小圈**，不动内部：

| 区域 | 期望 |
|---|---|
| 物体内部（cookie > 0） | 保持原值（硬阴影核心） |
| 物体外部远处（cookie = 0） | 保持 0 |
| **物体边缘附近**（cookie 从 X 突变到 0） | **从 X 平滑过渡到 0** |

"从物体中心径向向外软化"这个直觉正确，但实现上不用显式找中心 —— **"距边缘的距离"就是等价描述**。

### 4.2 四种软化算法对比

| 方案 | 原理 | 优点 | 缺点 | 适用 |
|---|---|---|---|---|
| **A. Uniform Gaussian Blur** | 整张 cookie 高斯模糊 | 一行代码；任意形状 | **细小物体被糊掉** | 快速验证 |
| **B. SDF-Based Softening** ⭐ | 距离场 + smoothstep 只软化"距边 s 内"的一圈 | 保留内部硬核；细小物体存活；自适应 | 需要距离场生成 | **推荐** |
| **C. Per-Object Radial** | 检测连通分量 + 质心 + 径向模糊 | 美术控制最强 | 非凸物体无定义；实现复杂 | 极致美术需求 |
| **D. Runtime Multi-tap PCF** | Shader 里采 9-tap 求平均 | 不改贴图；实时可调 | **108 次纹理采样/frag**，性能自杀 | 不推荐 |

**SDF 方案代码骨架**（Unity AssetPostprocessor）：

```csharp
public class CookieSDFSoftener : AssetPostprocessor
{
    void OnPostprocessTexture(Texture2D tex)
    {
        if (!assetPath.Contains("Cookie")) return;
        var pixels = tex.GetPixels();
        int softness_texel = 8;   // 软化半径（texel 单位）
        // 1. 生成距离场（Chamfer / Euclidean distance transform）
        // 2. mask = original × smoothstep(0, softness_texel, distance_to_edge)
        tex.SetPixels(pixels);
        tex.Apply();
    }
}
```

### 4.3 软化距离的两个约束

**下限**（够降噪）：来自方差分析，`s ≥ step / 2` 才有明显效果

```
s_min = (ray_length / 2) / N
```

**上限**（不吃物体）：`s ≤ 最小要保护的物体半径`

```
s_max = min_object_radius
```

**两个约束经常打架**。以 4m 光柱、12 步为例：
- `s_min ≈ 16cm`（世界空间）
- `s_max ≈ 5cm`（0.1 scale cube 半径）
- **打架** → 必须做取舍

### 4.4 三种立场

| 立场 | s 取值 | 效果 | 代价 |
|---|---|---|---|
| **A. 保全物体** | s = s_max | 所有物体阴影清晰 | 噪点降幅有限（~2×），靠其他手段补 |
| **B. 激进降噪** | s = s_min | 噪点降 5-8× | 小于 2·s_min 的物体阴影消失 |
| **C. 约束美术** | s = s_min，美术约定最小物体 ≥ 2·s_min | 两全其美 | 需要美术流程配合 |

**推荐 C，其次 A**。B 只在没有小物体的场景用。

### 4.5 数字参考表

假设 cookie 512×512 映射到 4m × 4m，1 texel = 0.78 cm：

| s（世界） | Texel | 保住 ≥ N cm 物体 | 降噪倍率 | 建议场景 |
|---|---|---|---|---|
| 2 cm | 3 texel | 4 cm+ | 1.2× | 只去锯齿 |
| **5 cm** | **6 texel** | **10 cm+** | **2×** | **保护 0.1 scale cube** |
| 10 cm | 13 texel | 20 cm+ | 3.5× | 中庸 |
| **16 cm** | **20 texel** | **32 cm+** | **5-8×** | **激进降噪，10cm 物体消失** |
| 30 cm | 38 texel | 60 cm+ | 15× | 只有大物体的场景 |

### 4.6 自适应软化半径值不值得

**统一 s（SDF 单参数）**：**够用**。因为 SDF 的 smoothstep 天然让距边缘近的软、远的硬，已经是隐式自适应。

**per-object 自适应 s**：需要连通分量检测 + 内接半径计算，复杂度高，收益边际。**不推荐**。

### 4.7 y-方向 vs XZ-方向软化的关系

- **第 1 章的 shader smoothstep**：软化的是 **y 方向**（sample.y 跨过 cookie_depth 的过渡）→ 治**顶边噪点**（glancing rays）
- **本章的 cookie 贴图预处理**：软化的是 **XZ 方向**（cookie silhouette 的空间分布）→ 治**侧边噪点**（through-passing rays）

**两者独立且互补**，可以同时做。噪点来源不同：

| 噪点类型 | 治法 |
|---|---|
| 视线擦过物体顶部 | shader smoothstep（y 方向） |
| 视线穿过物体侧面 | cookie 预处理软化（XZ 方向） |

### 4.8 决策流程

```
1. 用第 1 章的 shader smoothstep 治 y 方向噪点
   → shadow_softness = 0.02-0.05

2. 场景里有"视线穿过物体侧面"的噪点吗？
   ├─ 没有（罕见）→ 跳过 XZ 软化
   └─ 有 → 进入下一步

3. 场景最小遮挡物是多大？
   ├─ ≥ 30cm → 立场 C：s = 16cm，激进降噪
   ├─ 10-30cm → 立场 A：s = 半径值，保物体
   └─ < 10cm → 检查美术流程能否约束到 30cm+，否则接受立场 A 的有限降噪

4. 用哪种软化算法？
   ├─ 快速验证 → 方案 A（Gaussian blur，Photoshop 手动）
   ├─ 上线使用 → 方案 B（SDF-based，AssetPostprocessor）
   └─ 美术强需求 → 方案 C（per-object，工程量大）
```

### 4.9 一句话总结

- **软化算法首选 SDF-based**：保内部硬核，只软化边缘一圈
- **软化距离 = min(降噪需求 step/2, 最小物体半径)**
- **两者矛盾时**：先按最小物体半径给（保物体），噪点不够再考虑其他方案（bilateral / TAA）
- **和第 1 章 y-方向 smoothstep 互补**，两个方向都要做

---

## 5. 相机内外通用渲染方案（Cull / ZTest / Scene Depth Clamp）

### 5.1 问题背景

体积光用一个 proxy mesh（比如圆柱、Box）包裹光柱空间，fragment shader 里做 ray marching 累积 fog 颜色。

**核心难题**：相机可能在 proxy mesh 的**外部**（正常观察），也可能在**内部**（人物走进光柱）。两种情况都要正确渲染 fog，且**遮挡物要正确处理**。

**假设前提**：mesh 使用外法线（outward normals，标准 mesh）。

### 5.2 三种方案总览

| 方案 | Cull 模式 | ZTest | 需要 C# | 遮挡物处理 |
|---|---|---|---|---|
| **A** 动态 Cull | 相机在内→Front，外→Back | LEqual | ✅ 每帧更新 | 靠硬件 ZTest（软过渡） |
| **C** 全 shader 处理 | Cull Front（固定） | Always | ❌ | Shader 手动 clamp（精确） |
| **D** 混合最优 | 动态 Cull | 动态 ZTest | ✅ | 精确 + 硬件加速 |

### 5.3 方案 A：动态 Cull

#### 原理

C# 每帧检查相机是否在 mesh 的 AABB 内，动态切换 material 的 Cull 模式：
- 相机**外部** → Cull Back（画近壁）
- 相机**内部** → Cull Front（画远壁 / 从内部看是"包围墙"）

依赖硬件 ZTest LEqual 处理遮挡。

#### Shader 状态

```hlsl
Cull [_Cull]
ZWrite Off
Blend One One
// ZTest 用默认 LEqual
```

#### C# 脚本

```csharp
using UnityEngine;
using UnityEngine.Rendering;

public class VolumetricCullSwitcher : MonoBehaviour
{
    static readonly int _cull = Shader.PropertyToID("_Cull");
    Renderer _renderer;
    Material _mat;

    void Awake()
    {
        _renderer = GetComponent<Renderer>();
    }

    void LateUpdate()
    {
        var cam = Camera.main;
        if (cam == null) return;

        // 相机位置转到 mesh 本地坐标
        Vector3 camLocal = transform.InverseTransformPoint(cam.transform.position);

        // AABB 判断（跟 shader 里的 AABB 对应）
        const float padding = 0.01f;
        bool insideAABB =
            camLocal.x > -1f + padding && camLocal.x < 1f - padding &&
            camLocal.y >  0f + padding && camLocal.y < 1f - padding &&
            camLocal.z > -1f + padding && camLocal.z < 1f - padding;

        _mat = _renderer.material;   // 首次会创建 instance
        _mat.SetInt(_cull, (int)(insideAABB ? CullMode.Front : CullMode.Back));
    }

    void OnDestroy()
    {
        if (_mat != null) Destroy(_mat);
    }
}
```

#### 遮挡物行为

**相机外部 + 遮挡物在光柱内**（fragment 在近壁）：
```
相机 ── 近壁 ── 遮挡物 ── 远壁
         ↑ fragment 在这
         Ray march t_near 到 t_far（穿过遮挡物继续算）
```
- Ray march 累积**整个光柱空间**的 fog
- 遮挡物后的 fog 也算进去（**多算了**）
- 结果：fog 完整叠在遮挡物上，看起来"雾蒙蒙"

**相机外部 + 巨大物体完全挡住光柱**：
- 近壁深度 > 巨物深度 → ZTest 失败
- **Fragment 完全不执行**（硬件剔除）
- 性能：**0**

**相机内部 + 物体在相机和墙之间**（❌ 有 bug）：
- 远壁深度 > 物体深度 → ZTest 失败
- Fragment 不跑
- 相机和物体间的 fog **消失**（错误）

#### 优缺点

**优点**：
- ✅ 完全遮挡时硬件剔除，性能最优
- ✅ Shader 逻辑简单，几乎不改

**缺点**：
- ❌ 遮挡物穿越 fog 效果不物理准确（只靠 `depth_blend_fade` 软过渡）
- ❌ 相机内部 + 近距离物体时 fog 会消失
- ⚠️ AABB 边界切换 Cull 可能有 1 帧闪烁
- ⚠️ 需要 C# 每帧更新，多相机场景（VR、反射）复杂

### 5.4 方案 C：Cull Front + ZTest Always + Shader Clamp

#### 原理

固定 Cull Front，禁用硬件 ZTest（Always），fragment 强制执行。Shader 内部读 scene depth 手动 clamp ray march 终点，精确截断被遮挡的部分。

#### Shader 状态

```hlsl
Cull Front
ZWrite Off
ZTest Always   // ← 关键：绕过硬件 ZTest
Blend One One
```

#### Shader 关键代码

```hlsl
// 在 ray march 之前
float sceneEyeDepth = LinearEyeDepth(SampleSceneDepth(screen_uv), _ZBufferParams);

// 转换到"沿当前 ray 的距离"（object space）
float3 rayDirWs = normalize(mul(unity_ObjectToWorld, float4(ray_dir_os, 0)).xyz);
float3 camForwardWs = -UNITY_MATRIX_V._m20_m21_m22;
float t_scene_ws = sceneEyeDepth / max(dot(rayDirWs, camForwardWs), 1e-4);
float osToWsScale = length(mul(unity_ObjectToWorld, float4(ray_dir_os, 0)).xyz);
float t_scene = t_scene_ws / osToWsScale;

// Clamp ray march 终点
t_far = min(t_far, t_scene);

// 早退：整段被挡
if (t_near >= t_far) return half4(0, 0, 0, 1);

// ... ray march loop 保持不变 ...
```

#### 遮挡物行为

**所有场景**：ray march 精确从 `t_near` 到 `min(t_far, t_scene)`。
- 遮挡物精确截断 fog
- 相机内外一致行为
- 无边界切换问题

**性能特殊情况**：
- **完全遮挡**（巨物挡住整个光柱）：Fragment 都进入 shader（~1.4M），全部早退。每个 fragment ~30-40 ops 的浪费。
- **桌面 GPU**：约 0.01 ms 浪费，忽略不计
- **中端手机**：约 0.2 ms，可接受
- **低端手机**：可能 0.5-1 ms，肉痛

#### 优缺点

**优点**：
- ✅ 遮挡物精确截断（物理正确）
- ✅ 相机内外一致行为，无边界问题
- ✅ 无需 C# 更新，天然多相机兼容
- ✅ 相机内部近距离物体处理正确

**缺点**：
- ⚠️ 完全遮挡时浪费 fragment 入口成本
- ⚠️ Shader 复杂度略高（+10-30 行 HLSL）
- ⚠️ 依赖 `_CameraDepthTexture`（大多 URP 项目默认可用）

### 5.5 方案 D：混合方案（推荐移动端）

#### 原理

**根据相机内外，同时切换 Cull 和 ZTest**：
- **外部**：Cull Back + ZTest LEqual + shader clamp
  - 硬件 ZTest 剔除完全遮挡 → 高效
  - Shader clamp 处理光柱内部遮挡物 → 精确
- **内部**：Cull Front + ZTest Always + shader clamp
  - ZTest Always 保证近距离物体前的 fog 能被渲染
  - Shader clamp 处理内部遮挡物

#### Shader 状态

```hlsl
Cull [_Cull]
ZWrite Off
ZTest [_ZTest]
Blend One One
```

Shader 主体带 scene depth clamp（跟方案 C 相同）。

#### C# 脚本

```csharp
using UnityEngine;
using UnityEngine.Rendering;

public class VolumetricCullSwitcherHybrid : MonoBehaviour
{
    static readonly int _cull = Shader.PropertyToID("_Cull");
    static readonly int _zTest = Shader.PropertyToID("_ZTest");
    Renderer _renderer;
    Material _mat;

    void Awake() { _renderer = GetComponent<Renderer>(); }

    void LateUpdate()
    {
        var cam = Camera.main;
        if (cam == null) return;

        Vector3 camLocal = transform.InverseTransformPoint(cam.transform.position);
        const float padding = 0.01f;
        bool insideAABB =
            camLocal.x > -1f + padding && camLocal.x < 1f - padding &&
            camLocal.y >  0f + padding && camLocal.y < 1f - padding &&
            camLocal.z > -1f + padding && camLocal.z < 1f - padding;

        _mat = _renderer.material;

        if (insideAABB)
        {
            _mat.SetInt(_cull, (int)CullMode.Front);
            _mat.SetInt(_zTest, (int)CompareFunction.Always);
        }
        else
        {
            _mat.SetInt(_cull, (int)CullMode.Back);
            _mat.SetInt(_zTest, (int)CompareFunction.LessEqual);
        }
    }

    void OnDestroy() { if (_mat != null) Destroy(_mat); }
}
```

#### 遮挡物行为

**相机外部 + 巨物完全挡光柱**：ZTest 硬件剔除，**0 fragment**（跟方案 A 一样高效）
**相机外部 + 光柱内有遮挡物**：ZTest 过，shader clamp 精确截断（跟方案 C 一样准确）
**相机内部**：ZTest Always，shader clamp 正确处理（跟方案 C 一样）
**罕见场景（相机在光柱内且巨物挡住整个屏幕）**：会有方案 C 的浪费，但极少发生

#### 优缺点

**优点**：
- ✅ 完全遮挡时硬件剔除（性能优）
- ✅ 部分遮挡精确截断（正确）
- ✅ 相机内部近物处理正确
- ✅ 覆盖所有场景的最优组合

**缺点**：
- ⚠️ 需要 C# 每帧更新
- ⚠️ 复杂度略高（三个动态属性：Cull、ZTest、clamp）
- ⚠️ 边界切换仍可能有 1 帧闪烁

### 5.6 三方案性能对比

假设 1080p，光柱覆盖屏幕 70%（外部）/ 100%（内部），~1.4M / 2M fragments。

#### 每 fragment 成本

| 方案 | 完整 ray march（无遮挡） | 早退（完全遮挡） |
|---|---|---|
| A | 16 iters | 0（硬件剔除） |
| C | 16 iters + scene depth sample | ~40 ops（入口 + sample + 早退） |
| D | 16 iters + scene depth sample | 0（外部） / ~40 ops（内部罕见） |

#### 典型场景（部分遮挡）

三个方案的 fragment 数量和 ray march 迭代**几乎一样**。C/D 多一次 scene depth 采样（~5-10% 开销）。

#### 极端场景（完全遮挡）

方案 A、D 硬件剔除 → 成本 0
方案 C → ~1.4M × 40 ops 浪费，桌面 ~0.01ms、中端手机 ~0.2ms

### 5.7 视觉质量对比

| 场景 | 方案 A | 方案 C | 方案 D |
|---|---|---|---|
| 遮挡物在光柱内 | ⚠️ fog 蒙住整个物体（近似） | ✅ fog 精确停在物体前 | ✅ 精确 |
| 相机内 + 近距离物体 | ❌ fog 消失（bug） | ✅ 正确 | ✅ 正确 |
| 多个遮挡物叠加 | ⚠️ 软过渡近似 | ✅ 天然正确 | ✅ 正确 |
| AABB 边界穿越 | ⚠️ 可能闪烁 | ✅ 平滑 | ⚠️ 可能闪烁 |

### 5.8 平台推荐

| 平台 | 推荐方案 | 理由 |
|---|---|---|
| **桌面 / 主机** | **方案 C** | 性能损失可忽略（<0.02ms），质量最高，代码最少 |
| **中高端手机** | **方案 C 或 D** | C 简单，D 更极致 |
| **低端手机 / 移动端极致优化** | **方案 D** | 巨物遮挡场景省电，正确性也有保证 |
| **VR / AR** | **方案 D** | 性能敏感 + 多相机友好 |

### 5.9 深层洞察

#### Scene depth clamp 的物理意义

体积光/雾的物理模型：**沿视线积分 fog 密度**。遮挡物出现时，视线终止于遮挡物，后面的 fog 相机看不到，不应累积。

- 方案 A 靠硬件 ZTest 剔除完全被挡的像素，**但没截断部分被挡的 ray march**
- 方案 C/D 用 shader 手动截断，**每个 ray march 都止于视线可达的最远点**

#### Ray march 步数不变但采样更密

当 shader clamp 使 `t_far` 变小，`step = (t_far - t_near) / _RayMarchingCount` 也变小，**16 次采样分布在更短距离**。等于遮挡物附近采样更细致，视觉质量反而更好。

#### 为什么不能用 Cull Off + Blend One One

- Cull Off 让两面都渲染
- 同一屏幕像素被前后两个 fragment 各跑一次 shader
- 每个都做完整 ray march
- 加法混合 → **fog 亮度翻倍**
- 且性能减半（fragment 数量翻倍）

**结论**：体积着色器**不能简单用 Cull Off**，必须精确控制每像素只有一个 fragment。

#### `_ZTest` / `_Cull` 都用 int + `CompareFunction` / `CullMode` 枚举

Unity 的 shader lab `ZTest [_ZTest]` 和 `Cull [_Cull]` 期望的是 int 值，对应 `UnityEngine.Rendering.CompareFunction` 和 `CullMode` 枚举的整型值。C# 端用 `SetInt` 传枚举转 int：

```csharp
mat.SetInt(_zTest, (int)CompareFunction.LessEqual);
mat.SetInt(_cull, (int)CullMode.Back);
```

### 5.10 一句话总结

- **方案 A**：简单粗暴，硬件剔除高效，但视觉近似
- **方案 C**：shader 内部搞定一切，物理正确，桌面首选
- **方案 D**：软硬件结合，覆盖所有场景，移动端首选

**默认桌面用 C，移动端用 D，简单场景 A 也够用。**