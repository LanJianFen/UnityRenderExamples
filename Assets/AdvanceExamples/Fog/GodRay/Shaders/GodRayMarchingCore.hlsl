struct Attributes
{
    float4 position_os : POSITION;
};

struct Varyings
{
    float4 position_cs : SV_POSITION;
    float3 position_os : TEXCOORD0;
    float4 position_ss : TEXCOORD1;
    float3 ray_ori_os : TEXCOORD2;
};

CBUFFER_START(UnityPerMaterial)
    half4 _FogColor;
    half _Intensity;
    //half _Contrast;
    half _HorizontalFade;
    half _VerticalFade;
    half _FoggyIntensity;
    half _Bias;
CBUFFER_END

TEXTURE2D(_CookieMask);
SAMPLER(sampler_PointClamp);

#define EPIC_SAMPLES_COUNT   4
#define HIGH_SAMPLES_COUNT   3
#define MEDIUM_SAMPLES_COUNT 2
#define LOW_SAMPLES_COUNT    1

void DataNormalization()
{
    _VerticalFade = _VerticalFade * 10.0h;
    _HorizontalFade = _HorizontalFade * 45.0h;
    _Intensity = _Intensity * 3.0f;
}
void AABB(Varyings i, out float t_near, out float t_far)
{
    // Object Space 下的视线起点和视线方向
    float3 ray_ori_os = i.ray_ori_os;
    float3 ray_dir_os = normalize(i.position_os - ray_ori_os);
    
    float3 inv_ray_dir_os = 1.0f / (ray_dir_os + 1e-5f);
    float3 abs_inv_dir_os = abs(inv_ray_dir_os);

    float3 center = float3(0.0f, 0.5f, 0.0f);
    float3 extent = float3(1.0f, 0.5f, 1.0f);
    float3 t_center = (center - ray_ori_os) * inv_ray_dir_os;
    float3 t_extent = extent * abs_inv_dir_os;
    
    float3 t_in  = t_center - t_extent;
    float3 t_out = t_center + t_extent;

    t_near = max(t_in.x, max(t_in.y, t_in.z));
    t_far  = min(t_out.x, min(t_out.y, t_out.z));
}

void Dist2Scene(Varyings i, float3 ray_ori_os, out float t_scene)
{
    /* ============= Scene Depth Clamp========================
    // ZTest Always 已经绕过硬件遮挡；这里用 scene depth 手动 clamp t_far
    // 保证 ray march 只在"相机 → 遮挡物"之间累积，无论相机在光柱内外都正确
    //               把三点合起来看 clamp 的逻辑
    //
    //                 ● 遮挡物在这（eye_depth = D）
    //                ╱│
    //               ╱ │
    //              ╱  │
    //             ╱   │ D（沿 forward 的分量）
    //            ╱    │
    //           ╱     │
    //      ↖ 沿 ray   │
    //         走      │
    //      ┌ t_ws →  ─┼─    ← 想求 t_ws
    //     /           /
    //    ●────────────╱
    //   相机  ← forward
    //
    // 从相似三角形：D / t_ws = cos(θ)，其中 θ 是 ray 和 forward 的夹角。
    //
    // - cos(θ) = dot(ray_dir_ws, cam_forward_ws)（两者都是单位向量）
    // - 所以 t_ws = D / cos(θ) = scene_eye_depth / dot(ray_dir_ws, cam_forward_ws)*/
    
    float2 screen_uv = i.position_ss.xy / i.position_ss.w;
    float scene_eye_depth = LinearEyeDepth(SampleSceneDepth(screen_uv), _ZBufferParams);

    //float3 ray_dir_ws = TransformObjectToWorldDir(ray_dir_os, false); // 可以从 C#传过来 / 走VS
    //float3 cam_forward_ws = GetViewForwardDir();
    //float t_scene = scene_eye_depth / max(dot(ray_dir_ws, cam_forward_ws), 1e-4);

    // 进一步优化  视线到侧壁的 os 距离 / 视线到遮挡物的 os 距离 = 侧壁的深度 / 遮挡物的深度
    t_scene = scene_eye_depth * length(i.position_os - ray_ori_os) / i.position_ss.w;
}

void RayMarching(int k, float step, float base_jitter, float3 base_pos_os, float3 step_dir_os, inout half accumulation)
{
    // 黄金分割累加：1/φ = 0.6180339887... 是所有无理数里"最无理"的
    float step_jitter = frac(base_jitter + k * 0.6180339887498949f);
    float3 sample_point = base_pos_os + (k - 1 + step_jitter) * step_dir_os;
    //float3 sample_point = ray_ori_os + (t_current + step_jitter * step) * ray_dir_os;

    // horizontal_fade * vertical_fade
    half center_dist = sample_point.x * sample_point.x + sample_point.z * sample_point.z;
    half falloff = exp(-(_HorizontalFade * saturate(center_dist) + _VerticalFade * sample_point.y));
    half mask_x = saturate(1.0h - center_dist);
    falloff *= (mask_x * mask_x);
    //half horizontal_fade = pow(saturate(1.0h - center_dist), _HorizontalFade);
    //half vertical_fade = pow(saturate(1.0h - sample_point.y), _VerticalFade);

    float2 cookie_uv = sample_point.xz * 0.5f + 0.5f;
    float cookie_01_depth = SAMPLE_TEXTURE2D(_CookieMask, sampler_PointClamp, cookie_uv).r;
    float sample_01_depth = sample_point.y;
    
    float shadow_bias = step * _Bias; 
    half cookie_mask = (sample_01_depth >= cookie_01_depth - shadow_bias) ? 0.0h : 1.0h;
    cookie_mask = max(cookie_mask, _FoggyIntensity);
    accumulation += cookie_mask * falloff * step;
}

/*void Contrast(inout half3 color)
{
    color = pow(color, _Contrast);
}*/

Varyings Vert(Attributes i)
{
    Varyings o = (Varyings)0;

    o.position_cs = TransformObjectToHClip(i.position_os.xyz);
    o.position_os = i.position_os.xyz;
    o.position_ss = ComputeScreenPos(o.position_cs);

    o.ray_ori_os = TransformWorldToObject(_WorldSpaceCameraPos);

    return o;
}

half4 FragEpic(Varyings i) : SV_TARGET
{
    DataNormalization();

    //return half4(_FogColor, 1);
    // ============= AABB:计算和CUBE的交点 (Cylinder 是它的内切体) ========================
    float t_near, t_far, t_scene;
    
    float3 ray_ori_os = i.ray_ori_os;
    float3 ray_dir_os = normalize(i.position_os - ray_ori_os);
    
    AABB(i, t_near, t_far);

    if (t_near > t_far) return half4(0.0h, 0.0h, 0.0h, 1.0h);
    t_near = max(0.0f, t_near);

    // ============= Scene Depth Clamp========================*
    Dist2Scene(i, ray_ori_os, t_scene);
    
    t_far = min(t_far, t_scene);
    if (t_near >= t_far) return half4(0.0h, 0.0h, 0.0h, 1.0h);

    // ============= Ray Marching ========================
    float base_jitter = frac(52.9829189f * frac(dot(i.position_cs.xy, float2(0.06711056f, 0.00583715f))));

    float step = (t_far - t_near) / EPIC_SAMPLES_COUNT;
    float3 base_pos_os = ray_ori_os + t_near * ray_dir_os;
    float3 step_dir_os = ray_dir_os * step;
    half accumulation = 0.0h;
    [unroll] for (int k = 1; k <= (int)EPIC_SAMPLES_COUNT; k++)
        RayMarching(k, step, base_jitter, base_pos_os, step_dir_os, accumulation);
    
    //Contrast(color);
    half3 color = accumulation * _FogColor.rgb * _Intensity;
    return half4(color, 1);
}

half4 FragHigh(Varyings i) : SV_TARGET
{
    DataNormalization();
    
    // ============= AABB:计算和CUBE的交点 (Cylinder 是它的内切体) ========================
    float t_near, t_far, t_scene;
    
    float3 ray_ori_os = i.ray_ori_os;
    float3 ray_dir_os = normalize(i.position_os - ray_ori_os);
    
    AABB(i, t_near, t_far);

    if (t_near > t_far) return half4(0.0h, 0.0h, 0.0h, 1.0h);
    t_near = max(0.0f, t_near);

    // ============= Scene Depth Clamp========================*
    Dist2Scene(i, ray_ori_os, t_scene);
    
    t_far = min(t_far, t_scene);
    if (t_near >= t_far) return half4(0.0h, 0.0h, 0.0h, 1.0h);

    // ============= Ray Marching ========================
    float base_jitter = frac(52.9829189f * frac(dot(i.position_cs.xy, float2(0.06711056f, 0.00583715f))));

    float step = (t_far - t_near) / HIGH_SAMPLES_COUNT;
    float3 base_pos_os = ray_ori_os + t_near * ray_dir_os;
    float3 step_dir_os = ray_dir_os * step;
    half accumulation = 0.0h;
    [unroll] for (int k = 1; k <= (int)HIGH_SAMPLES_COUNT; k++)
        RayMarching(k, step, base_jitter, base_pos_os, step_dir_os, accumulation);
    
    //Contrast(color);
    
    return half4(accumulation * _FogColor.rgb * _Intensity, 1);
}

half4 FragMedium(Varyings i) : SV_TARGET
{
    DataNormalization();
    
    // ============= AABB:计算和CUBE的交点 (Cylinder 是它的内切体) ========================
    float t_near, t_far, t_scene;
    
    float3 ray_ori_os = i.ray_ori_os;
    float3 ray_dir_os = normalize(i.position_os - ray_ori_os);
    
    AABB(i, t_near, t_far);

    if (t_near > t_far) return half4(0.0h, 0.0h, 0.0h, 1.0h);
    t_near = max(0.0f, t_near);

    // ============= Scene Depth Clamp========================*
    Dist2Scene(i, ray_ori_os, t_scene);
    
    t_far = min(t_far, t_scene);
    if (t_near >= t_far) return half4(0.0h, 0.0h, 0.0h, 1.0h);

    // ============= Ray Marching ========================
    float base_jitter = frac(52.9829189f * frac(dot(i.position_cs.xy, float2(0.06711056f, 0.00583715f))));

    float step = (t_far - t_near) / MEDIUM_SAMPLES_COUNT;
    float3 base_pos_os = ray_ori_os + t_near * ray_dir_os;
    float3 step_dir_os = ray_dir_os * step;
    half accumulation = 0.0h;
    [unroll] for (int k = 1; k <= (int)MEDIUM_SAMPLES_COUNT; k++)
        RayMarching(k, step, base_jitter, base_pos_os, step_dir_os, accumulation);
    
    //Contrast(color);
    
    return half4(accumulation  * _FogColor.rgb * _Intensity, 1);
}

half4 FragLow(Varyings i) : SV_TARGET
{
    DataNormalization();
    
    // ============= AABB:计算和CUBE的交点 (Cylinder 是它的内切体) ========================
    float t_near, t_far, t_scene;
    
    float3 ray_ori_os = i.ray_ori_os;
    float3 ray_dir_os = normalize(i.position_os - ray_ori_os);
    
    AABB(i, t_near, t_far);

    if (t_near > t_far) return half4(0.0h, 0.0h, 0.0h, 1.0h);
    t_near = max(0.0f, t_near);

    // ============= Scene Depth Clamp========================*
    Dist2Scene(i, ray_ori_os, t_scene);
    
    t_far = min(t_far, t_scene);
    if (t_near >= t_far) return half4(0.0h, 0.0h, 0.0h, 1.0h);

    // ============= Ray Marching ========================
    float base_jitter = frac(52.9829189f * frac(dot(i.position_cs.xy, float2(0.06711056f, 0.00583715f))));

    float step = (t_far - t_near) / LOW_SAMPLES_COUNT;
    float3 base_pos_os = ray_ori_os + t_near * ray_dir_os;
    float3 step_dir_os = ray_dir_os * step;
    half accumulation = 0.0h;
    [unroll] for (int k = 1; k <= (int)LOW_SAMPLES_COUNT; k++)
        RayMarching(k, step, base_jitter, base_pos_os, step_dir_os, accumulation);
    
    //Contrast(color);
    
    return half4(accumulation * _FogColor.rgb * _Intensity, 1);
}