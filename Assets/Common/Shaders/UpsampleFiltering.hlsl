// sample_num = 6, 36 个 PointClamp：绝对平均，比 9 + LinearClamp 要好一些
// sample_num = 9, 81 个 PointClamp：Ground Truth
half4 AveragePointFilter(float2 center, int sample_num)
{
    half4 color = 0.0h;
    float2 d = _MainTex_TexelSize.xy;
     [unroll] for (int x = 0; x < sample_num; x++)
        [unroll] for (int y = 0; y < sample_num; y++)
        {
            float2 offset = float2(x - (sample_num * 0.5 - 0.5h), y - (sample_num * 0.5 - 0.5h)) * d;                         // 偏移严格等于 1 个物理像素整数倍
            color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_PointClamp, center + offset);
        }
    return color  / (half)(sample_num * sample_num);
}

half4 MinAverageFilter(float2 center, float range = 2.0f)
{
    half4 color = 0.0h;
    float2 d = _MainTex_TexelSize.xy * range;
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center);
    // 十字方向 上下左右
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2( d.x, 0.0));
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2(-d.x, 0.0));
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2(0.0, d.y));
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2(0.0, -d.y));

    return color * 0.25h;
}

// 9 + LinearClamp + range = 2, 实际覆盖 36 个采样点
half4 AverageFilter(float2 center, float range = 2.0f)
{
    half4 color = 0.0h;
    float2 d = _MainTex_TexelSize.xy * range;
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center);
    // 十字方向 上下左右
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2( d.x, 0.0));
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2(-d.x, 0.0));
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2(0.0, d.y));
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2(0.0, -d.y));
    // 对角线方向 四个角
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2( d.x, d.y));
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2(-d.x, d.y));
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2(-d.x, -d.y));
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2( d.x, -d.y));

    return color * rcp(9.0h);
}

// 旋转随机圆盘采样
half4 RotationAverageFilter(Varyings i, float range = 2.0f)
{
    half4 color = 0.0h;
    float2 center = i.uv;
    float2 d = _MainTex_TexelSize.xy * range;

    float noise = frac(52.9829189f * frac(dot((float2)i.positionCS.xy, float2(0.06711056f, 0.00583715f))));
    float angle = noise * 6.2831853f;
    
    // 计算旋转矩阵
    float s, c;
    sincos(angle, s, c);
    float2x2 rot = float2x2(c, -s, s, c);

    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center);
    // 十字方向 上下左右
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + mul(rot, float2(d.x, 0.0)));
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + mul(rot, float2(-d.x, 0.0)));
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + mul(rot, float2(0.0, d.y)));
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + mul(rot, float2(0.0, -d.y)));
    // 对角线方向 四个角
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + mul(rot, float2( d.x, d.y)));
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + mul(rot, float2(-d.x, d.y)));
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + mul(rot, float2(-d.x, -d.y)));
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + mul(rot, float2( d.x, -d.y)));

    return color * rcp(9.0h);
}

// 分离十字采样：用来近似全平均采样，但是容易有十字，表现一般
// SeparableFilter 本该是像 5S 一样的 全屏双 Pass，单 Pass 只能画十字
half4 SeparableFilter(float2 center, int range)
{
    half4 color = 0.0h;
    float2 d = _MainTex_TexelSize.xy;
    int half_sample_num = range * 0.5h;

    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center);
    [unroll] for(int i = 1; i <= half_sample_num; i++)
    {
        // 横向
        color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2(d.x * i, 0));
        color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2(-d.x * i, 0));
        // 纵向
        color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2(0, d.y * i));
        color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2(0, -d.y * i));
    }
    
    return color / (half)(half_sample_num * 4 + 1);
}

half4 SeparableFilter2(float2 center, int range)
{
    half4 color = 0.0h;
    float2 d = _MainTex_TexelSize.xy;
    int half_sample_num = range * 0.5h;
    
    [unroll] for(int i = -half_sample_num; i <= half_sample_num; i++)
        color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + i * float2(d.x, 0));
    [unroll] for(int j = -half_sample_num; j <= half_sample_num; j++)
        color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + j * float2(0, d.y));

    // 中心点的权重比较高，也可以减掉 1 个中心点的权重（理论上应该如此）
    return color / (half)(4 * half_sample_num + 2);
}

// 利用 Mip 免费做一次平均模糊
half4 MipAverageFilter(Varyings i, float mip = 3.0f)
{
    //float noise = frac(dot(i.positionCS.xy, float2(17.1, 23.1)));
    //float jitter = (noise - 0.5f) * 0.5f;

    // 用噪声剪碎边缘的大锯齿马赛克
    float ign = frac(52.9829189f * frac(dot(i.positionCS.xy, float2(0.06711056f, 0.00583715f))));
    float jitter = (ign - 0.5f) * 2.4f;
    half4 color = SAMPLE_TEXTURE2D_LOD(_MainTex, sampler_LinearClamp, i.uv, mip + jitter);
    return color;
}

// 高斯滤波：在这个 case 没啥用
half4 GaussianFilter(float2 center, float range)
{
    half4 color = 0.0h;
    float2 d = _MainTex_TexelSize.xy * range;
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center) * 0.25h;
    // 十字方向 上下左右
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2( d.x, 0.0)) * 0.125h;
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2(-d.x, 0.0)) * 0.125h;
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2(0.0, d.y)) * 0.125h;
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2(0.0, -d.y)) * 0.125h;
    // 对角线方向 四个角
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2( d.x, d.y)) * 0.0625h;
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2(-d.x, d.y)) * 0.0625h;
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2(-d.x, -d.y)) * 0.0625h;
    color += SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center + float2( d.x, -d.y)) * 0.0625h;

    return color * 0.125h;
}

// 双边滤波：在这个 case 没啥用
half4 BilateralFilter(float2 center, float range)
{
    half4 color = 0.0h;
    half4 weight = 0.0h;
    float2 d = _MainTex_TexelSize.xy * range;
    
    half4 center_color = SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, center);
    float2 offsets[9] = {
        float2(0, 0),
        float2( d.x, 0.0), float2(-d.x, 0.0), float2(0.0,  d.y), float2(0.0, -d.y),
        float2( d.x, d.y), float2(-d.x, d.y), float2(-d.x, -d.y), float2( d.x, -d.y)
    };

    [unroll] for(int i = 0;i < 9; i++)
    {
        float2 sample_uv = center + offsets[i];
        half4 sample_color = SAMPLE_TEXTURE2D_X(_MainTex, sampler_LinearClamp, sample_uv);

        half color_tolerance = 3.2h;
        half color_diff = length(sample_color - center_color);
        
        half sample_weight = exp(-color_diff / color_tolerance);

        color += sample_color * sample_weight;
        weight += sample_weight;
    }               
    color /= max(weight, 0.001h);
    
    return color;
}