struct Attributes
{
    float4 positionOS : POSITION;
    float2 uv         : TEXCOORD0;
};
            
struct Varyings
{
    float4 positionCS : SV_POSITION;
    float2 uv   : TEXCOORD0;
};

TEXTURE2D(_MainTex);
SAMPLER(sampler_PointClamp);
SAMPLER(sampler_LinearClamp);

float4 _MainTex_TexelSize;
float4 _MainTex_ST;

#include "UpsampleFiltering.hlsl"

Varyings Vert(Attributes input)
{
    Varyings output = (Varyings)0;
                
    // 标准空间转换，消灭对角线撕裂！
    output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
    output.uv = TRANSFORM_TEX(input.uv, _MainTex);

    return output;
}
            
half4 FragEpic(Varyings i) : SV_Target
{
    half4 color = AverageFilter(i.uv);

    return color;
}

half4 FragMedium(Varyings i) : SV_Target
{
    half4 color = MinAverageFilter(i.uv);
    return color;
}

half4 FragLow(Varyings i) : SV_Target
{
    half4 color = MipAverageFilter(i);
    return color;
}