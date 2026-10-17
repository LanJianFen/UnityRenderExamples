#pragma once
#define PreViewTranslation (-_WorldSpaceCameraPos.xyz)
#define NUM_TEX_COORD_INTERPOLATORS 4
#define MATERIAL_TANGENTSPACENORMAL         1
#define SHADINGMODELID_SUBSURFACE_PROFILE   5
#define SHADINGMODELID_DEFAULT_LIT   1


struct FVertexFactoryInput
{
    float4 Position  : POSITION;
    half4  TangentX  : TANGENT;     // xyz: 切线, w: 切线符号
    half3  TangentZ  : NORMAL;
    half4  Color     : COLOR;
    float2 TexCoords[NUM_TEX_COORD_INTERPOLATORS] : TEXCOORD0;   // 占 TEXCOORD0~2
};

struct FVertexFactoryInterpolantsVSToPS
{
    half3  TangentToWorld0 : TEXCOORD0;   // xyz: WorldTangent
    half4  TangentToWorld2 : TEXCOORD1;   // xyz: WorldNormal, w: 切线符号
    half4  Color           : COLOR0;
    #if NUM_TEX_COORD_INTERPOLATORS
    float4 TexCoords[(NUM_TEX_COORD_INTERPOLATORS + 1) / 2] : TEXCOORD2;   // 占 TEXCOORD2~3
    #endif
};

// ---------------- BasePass 插值器 (BasePassCommon.ush) ----------------
struct FBasePassInterpolantsVSToPS
{
    float3 PixelPosition : TEXCOORD7;    // 世界坐标 (相当于 UE 移动端的做法)
};


struct FBasePassVSToPS
{
    // PC 端暂时没有 BasePass 插值数据（雾、速度都还没做），所以先不放 BasePassInterpolants 成员。
    // 以后做 Velocity 时再加回来，位置放在 FactoryInterpolants 和 Position 之间。
    FVertexFactoryInterpolantsVSToPS FactoryInterpolants;
    float4 Position : SV_POSITION;
};

FVertexFactoryInterpolantsVSToPS VertexFactoryGetInterpolantsVSToPS(FVertexFactoryInput Input)
{
    FVertexFactoryInterpolantsVSToPS Interpolants = (FVertexFactoryInterpolantsVSToPS)0;
    half3 WorldTangent = TransformObjectToWorldDir(Input.TangentX.xyz);
    half3 WorldNormal  = TransformObjectToWorldNormal(Input.TangentZ);
    half  TangentSign  = Input.TangentX.w * GetOddNegativeScale();   // 负缩放时翻转
    Interpolants.TangentToWorld0 = WorldTangent;
    Interpolants.TangentToWorld2 = half4(WorldNormal, TangentSign);
    Interpolants.Color           = Input.Color;
    #if NUM_TEX_COORD_INTERPOLATORS
    [unroll] for (int CoordinateIndex = 0; CoordinateIndex < NUM_TEX_COORD_INTERPOLATORS; CoordinateIndex += 2)
    {
        float2 UVA = Input.TexCoords[CoordinateIndex];
        int SafeNextIndex = min(CoordinateIndex + 1, NUM_TEX_COORD_INTERPOLATORS - 1); // 避免越界：三目运算符不是短路的，两个分支的下标都会被求值
        float2 UVB = (CoordinateIndex + 1 < NUM_TEX_COORD_INTERPOLATORS) ? Input.TexCoords[SafeNextIndex] : 0;
        Interpolants.TexCoords[CoordinateIndex / 2] = float4(UVA, UVB);
    }
    #endif
    return Interpolants;
}

// ====================================================================
// FMaterialPixelParameters 不全是几何上下文。它是整个像素的上下文
// 里面有三类数据：几何数据、视图数据，以及材质算完法线后写回的数据。
// ====================================================================
struct FMaterialPixelParameters
{
    #if NUM_TEX_COORD_INTERPOLATORS
    float2 TexCoords[NUM_TEX_COORD_INTERPOLATORS];
    #endif
    half4   VertexColor;
    half3   WorldNormal;
    half3   WorldTangent;
    half3   ReflectionVector;
    half3   CameraVector;
    float4  SvPosition;
    float4  ScreenPosition;              // float4
    half    UnMirrored;
    half    TwoSidedSign;
    half3x3 TangentToWorld;
    float3  AbsoluteWorldPosition;
    float3  WorldPosition_CamRelative;
};
inline FMaterialPixelParameters MakeInitializedMaterialPixelParameters()
{
    return (FMaterialPixelParameters)0;
}
inline bool   IsOrthoProjection() { return unity_OrthoParams.w == 1.0; }
inline float3 GetViewForward()    { return -UNITY_MATRIX_V[2].xyz; } // Unity 相机看向 -Z
inline float2 GetUV(FVertexFactoryInterpolantsVSToPS Interpolants, uint UVIndex)
{
    float4 PackedUV = Interpolants.TexCoords[UVIndex / 2];
    return (UVIndex & 1) ? PackedUV.zw : PackedUV.xy;
}
inline half3 GetTangentToWorld0(FVertexFactoryInterpolantsVSToPS I) { return I.TangentToWorld0; }
inline half4 GetTangentToWorld2(FVertexFactoryInterpolantsVSToPS I) { return I.TangentToWorld2; }
inline half4 GetColor(FVertexFactoryInterpolantsVSToPS I)           { return I.Color; }
inline float4 SvPositionToResolvedScreenPosition(float4 SvPosition)
{
    float2 PixelPos = SvPosition.xy;                                   // Unity 没有 ViewRectMin
    float2 NDCxy    = (PixelPos * (_ScreenParams.zw - 1.0) - 0.5) * float2(2, -2);
    return float4(NDCxy, SvPosition.z, 1.0) * SvPosition.w;
}
float3 SvPositionToResolvedTranslatedWorld(float4 SvPosition)
{
    float2 ScreenUV = SvPosition.xy / _ScaledScreenParams.xy;
    float3 WorldPos = ComputeWorldSpacePosition(ScreenUV, SvPosition.z, UNITY_MATRIX_I_VP); // 已处理 DX12 Reversed-Z 和 Y 翻转
    return WorldPos + PreViewTranslation;
}
inline half3x3 AssembleTangentToWorld(FVertexFactoryInterpolantsVSToPS Interpolants)
{
    half3 Tangent0 = Interpolants.TangentToWorld0;
    half4 Tangent2 = Interpolants.TangentToWorld2; // normal

    half3 Tangent1 = cross(Tangent2.xyz, Tangent0) * Tangent2.w; // bitangent
    return half3x3(Tangent0, Tangent1, Tangent2.xyz); // tbn
}
inline half3x3 AssembleTangentToWorld(half3 TangentToWorld0, half4 TangentToWorld2)
{
    half3 TangentToWorld1 = cross(TangentToWorld2.xyz, TangentToWorld0) * TangentToWorld2.w;
    return half3x3(TangentToWorld0, TangentToWorld1, TangentToWorld2.xyz);
}

inline FMaterialPixelParameters GetMaterialPixelParameters(FVertexFactoryInterpolantsVSToPS Interpolants, float4 SvPosition)
{
    FMaterialPixelParameters Result = MakeInitializedMaterialPixelParameters();
    #if NUM_TEX_COORD_INTERPOLATORS
    [unroll] for (int CoordinateIndex = 0; CoordinateIndex < NUM_TEX_COORD_INTERPOLATORS; CoordinateIndex++)
        Result.TexCoords[CoordinateIndex] = GetUV(Interpolants, CoordinateIndex);
    #endif
    half3 TangentToWorld0 = GetTangentToWorld0(Interpolants).xyz;
    half4 TangentToWorld2 = GetTangentToWorld2(Interpolants);
    //Result.UnMirrored     = TangentToWorld2.w;
    Result.UnMirrored     = 1.0h; // todo: 这个地方有点奇怪，TangentToWorld2的w被tangentSign占用了
    Result.VertexColor    = GetColor(Interpolants);
    Result.TangentToWorld = AssembleTangentToWorld(TangentToWorld0, TangentToWorld2);
    Result.TwoSidedSign   = 1.0h;
    return Result;
}
