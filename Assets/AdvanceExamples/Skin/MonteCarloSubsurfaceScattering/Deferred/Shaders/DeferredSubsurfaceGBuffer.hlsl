#pragma once
#define kMaterialFlagSpecularSetup   8
#define kMaterialFlagSkin 16
struct FGBufferData
{
    float3 WorldNormal;
    half3  BaseColor;
    half3  DiffuseColor;     // 派生
    half3  SpecularColor;    // 派生：F0
    half   Metallic;
    half   Specular;
    half   Roughness;
    half   GBufferAO;
    half4  CustomData;       // 暂不使用（SSS 以后用）
    uint   ShadingModelID;
};

struct FragmentGBufferOutput
{
    half4 GBuffer0 : SV_Target0; // [Albedo.rgb, MaterialFlags]
    half4 GBuffer1 : SV_Target1; // [Specular/F0.rgb, Occlusion]
    half4 GBuffer2 : SV_Target2; // [Normal.rgb, Smoothness]
    half4 GBuffer3 : SV_Target3; // [BakedGI / Lighting.rgb, Unused]
};

inline half DielectricSpecularToF0(half Specular) { return 0.08h * Specular; }

inline half3 ComputeF0(half Specular, half3 BaseColor, half Metallic)
{
    return lerp(DielectricSpecularToF0(Specular).xxx, BaseColor, Metallic);
}

// ===================== ShadingModelsMaterial.ush =====================
inline void SetGBufferForShadingModel(inout FGBufferData GBuffer, inout FMaterialPixelParameters MaterialParameters,
    const float Opacity, const half3 BaseColor, const half  Metallic, const half  Specular, const float Roughness, const float Anisotropy,
    const float3 SubsurfaceColor, const float SubsurfaceProfile, const float Dither, const uint  ShadingModel)
{
    GBuffer.WorldNormal    = MaterialParameters.WorldNormal;
    GBuffer.BaseColor      = BaseColor;
    GBuffer.Metallic       = Metallic;
    GBuffer.Specular       = Specular;
    GBuffer.Roughness      = Roughness;
    GBuffer.ShadingModelID = ShadingModel;
    if (ShadingModel == SHADINGMODELID_DEFAULT_LIT)
    {
        // DefaultLit 不写 CustomData
    }
    // 以后：else if (ShadingModel == SHADINGMODELID_SUBSURFACE_PROFILE) { GBuffer.CustomData.a = Opacity; ... }
    GBuffer.SpecularColor = ComputeF0(Specular, BaseColor, Metallic);
    GBuffer.DiffuseColor  = BaseColor - BaseColor * Metallic;
}

// ===================== EncodeGBuffer：UE 数据 → URP 布局 =====================
inline half3 EncodeNormal(float3 N)
{
#if defined(_GBUFFER_NORMALS_OCT)
    float2 Oct = PackNormalOctQuadEncode(N);                   // [-1, 1]
    return half3(PackFloat2To888(saturate(Oct * 0.5 + 0.5)));  // [0, 1]
#else
    return half3(N);   // 非 Accurate 模式下 GBuffer2 是 SNorm 格式，直接写 [-1, 1]
#endif
}

inline void EncodeGBuffer(FGBufferData GBuffer, half3 SceneColor, out FragmentGBufferOutput Out)
{
    uint MaterialFlags = kMaterialFlagSpecularSetup;
    
    if (GBuffer.ShadingModelID == SHADINGMODELID_SUBSURFACE_PROFILE)
        MaterialFlags |= kMaterialFlagSkin;
    
    Out.GBuffer0 = half4(GBuffer.BaseColor,  PackMaterialFlags(MaterialFlags));   // URP: PackMaterialFlags
    Out.GBuffer1 = half4(GBuffer.SpecularColor, GBuffer.GBufferAO);
    Out.GBuffer2 = half4(EncodeNormal(GBuffer.WorldNormal), 1.0h - GBuffer.Roughness);
    Out.GBuffer3 = half4(SceneColor, 1.0h);
}
