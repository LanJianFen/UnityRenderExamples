#pragma once
struct Attributes
{
    float4 positionOS : POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float4 positionCS : SV_POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID // GPU Instancing 相关
};

Varyings DepthOnlyVert(Attributes input)
{
    Varyings output = (Varyings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);

    // 必须和 Diffuse / Composite Pass 的顶点变换完全一致
    output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
    return output;
}

half DepthOnlyFrag(Varyings input) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(input);
    return input.positionCS.z;
}