#pragma once

struct FVertexInput
{
    float4 position_os : POSITION;
    float2 uv0        : TEXCOORD0;
    float2 uv1        : TEXCOORD1;
    float2 uv2        : TEXCOORD2;
    float2 uv3        : TEXCOORD3;
    half3 normal_os   : NORMAL;
    half4 tangent_os  : TANGENT;
};

#define NUM_MATERIAL_TEXCOORDS 3
struct FBasePassInterpolantsVSToPS
{
    float4 Position : SV_POSITION;
    half4 Color : COLOR0;
    float3 PixelPosition : TEXCOORD0;
    half3 TangentToWorld0  : TEXCOORD1; // xyz: tangent_ws
    half4 TangentToWorld2   : TEXCOORD2; // normal_ws, w: tangent_sign
    #if NUM_MATERIAL_TEXCOORDS > 0
        float4 TexCoords[(NUM_MATERIAL_TEXCOORDS + 1) / 2] : TEXCOORD3;
    #endif
    //float4 position_ndc :TEXCOORD4;
};

struct FragmentGBufferOutput
{
    half4 GBuffer0 : SV_Target0; // [Albedo.rgb, MaterialFlags]
    half4 GBuffer1 : SV_Target1; // [Specular/F0.rgb, Occlusion]
    half4 GBuffer2 : SV_Target2; // [Normal.rgb, Smoothness]
    half4 GBuffer3 : SV_Target3; // [BakedGI / Lighting.rgb, Unused]
};

// ====================================================================
// 几何上下文
// ====================================================================
struct FMaterialPixelParameters
{
    #if NUM_MATERIAL_TEXCOORDS > 0
        float2 TexCoords[NUM_MATERIAL_TEXCOORDS];
    #endif
    half4 VertexColor;
    
    half3 CameraVector;
    half3 WorldNormal;
    half3 ReflectionVector;
    half3  WorldTangent;
    //half3  bitangent_ws;
    half3x3 TangentToWorld;
    
    float2 ScreenPosition;
    float3 AbsoluteWorldPosition;
    float3 WorldPosition_CamRelative;
    float4 SvPosition;
    half UnMirrored;
    half  TwoSidedSign;
};

// ====================================================================
// 材质输入求值结构体
// ====================================================================
struct FPixelMaterialInputs
{
    half3 base_color;
    half3 normal_ts;
    half  roughness;
    half  specular;
    half  occlusion;
    half  subsurface_intensity;
};

inline float2 GetUV(FBasePassInterpolantsVSToPS Interpolants, uint UVIndex)
{
    float4 PackedUV = Interpolants.TexCoords[UVIndex / 2];
    return (UVIndex & 1) ? PackedUV.zw : PackedUV.xy;
}

inline half3x3 AssembleTangentToWorld(FBasePassInterpolantsVSToPS Interpolants)
{
    half3 Tangent0 = Interpolants.TangentToWorld0;
    half4 Tangent2 = Interpolants.TangentToWorld2; // normal
    
    half3 Tangent1 = cross(Tangent2.xyz, Tangent0) * Tangent2.w; // bitangent
    return half3x3(Tangent0, Tangent1, Tangent2.xyz); // tbn
}

inline FMaterialPixelParameters GetMaterialPixelParameters(FBasePassInterpolantsVSToPS Interpolants, float4 SvPosition)
{
    FMaterialPixelParameters Parameters = (FMaterialPixelParameters) 0;
    
    #if NUM_MATERIAL_TEXCOORDS > 0
    [unroll] for (int CoordinateIndex = 0; CoordinateIndex < NUM_MATERIAL_TEXCOORDS; CoordinateIndex++)
        Parameters.TexCoords[CoordinateIndex] = GetUV(Interpolants, CoordinateIndex);
    #endif
    
    Parameters.TangentToWorld = AssembleTangentToWorld(Interpolants); //tbn
    Parameters.WorldTangent = Parameters.TangentToWorld[0];
    Parameters.WorldNormal = Parameters.TangentToWorld[2];
    Parameters.UnMirrored     = Interpolants.TangentToWorld2.w;
    
    Parameters.AbsoluteWorldPosition = Interpolants.PixelPosition;
    Parameters.VertexColor = Interpolants.Color;
    Parameters.SvPosition = SvPosition;
    //Result.PrimitiveId           = 0;
    return Parameters;
}

inline void GetPixelMaterialInputs(FMaterialPixelParameters Parameters, out FPixelMaterialInputs material_inputs)
{
    // base albedo
    float2 uv0 = Parameters.uv0, uv1 = Parameters.uv1, uv2 = Parameters.uv2, uv3 = Parameters.uv3;
    half4 albedo_properties = SAMPLE_TEXTURE2D(_AlbedoMap, sampler_PointClamp, uv0);
    half3 albedo = albedo_properties.rgb;
    half self_shadow  = albedo_properties.a * _HairShadowWeight;
    half3 base_color = albedo * self_shadow;
    
    // decal
    //half3 decal_properties = SAMPLE_TEXTURE2D(_DecalMask, sampler_PointClamp, uv1).rgb;
    //half decal_albedo = decal_properties.r * _DecalMask;
    
    // normal ts
    half3 base_normal_ts       = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_PointClamp, uv0));
    half3 eyelid_close_ts = UnpackNormal(SAMPLE_TEXTURE2D(_EyelidCloseNormalMap, sampler_PointClamp, uv2));
    half3 blended_ts  = BlendNormalRNMCustom(base_normal_ts, eyelid_close_ts);
    half3 final_normal_ts   = lerp(base_normal_ts, blended_ts, _EyelidCloseWeight);
    
    // material
    half4 material_properties        = SAMPLE_TEXTURE2D(_MaterialMap, sampler_PointClamp, uv0);
    
    material_inputs.base_color   = base_color;
    material_inputs.normal_ts = normalize(final_normal_ts);
    material_inputs.roughness             = material_properties.r * _Roughness;
    material_inputs.specular              = material_properties.b * _Specular;
    material_inputs.occlusion             = 1.0h;
    material_inputs.subsurface_intensity  = material_properties.a;
}

inline void CalcMaterialParametersEx(inout FMaterialPixelParameters Parameters, inout FPixelMaterialInputs PixelMaterialInputs, float4 SvPosition, float4 ScreenPosition, float3 TranslatedWorldPosition,     bool bIsFrontFace = true
{
    Parameters.WorldPosition_CamRelative = TranslatedWorldPosition;
    Parameters.ScreenPosition = ScreenPosition;
    Parameters.TwoSidedSign   = bIsFrontFace ? 1.0h : -1.0h;
    Parameters.CameraVector = normalize(GetCameraPositionWS() - Parameters.AbsoluteWorldPosition);
    // 材质解包
    CalcPixelMaterialInputs(Parameters, PixelMaterialInputs);
    
    #if MAT_HAS_NORMAL // 如果法线来自贴图
        Parameters.WorldNormal = normalize(mul(PixelMaterialInputs.Normal, Parameters.TangentToWorld));
    #endif
    
    Parameters.ReflectionVector = reflect(-Parameters.CameraVector, Parameters.WorldNormal);
}





struct FGBufferData
{
    half3 normal_ws;
    half3 diffuse_albedo;
    half3 F0;
    half3 F90;
    half roughness;
    half alpha;
    half occlusion;
    half subsurface_intensity;
    half metallic;
    uint shading_model_id;
};

inline FGBufferData SetupGBufferData(FMaterialPixelParameters pixel_params, FPixelMaterialInputs material_inputs)
{
    FGBufferData buffer = (FGBufferData)0;

    half3x3 tbn = half3x3(pixel_params.WorldTangent, pixel_params.bitangent_ws, pixel_params.WorldNormal);
    buffer.normal_ws =SafeNormalize(mul(material_inputs.normal_ts, tbn));
    buffer.diffuse_albedo = material_inputs.base_color;
    buffer.F0 = half3(0.08h,0.08h,0.08h) * material_inputs.specular;
    buffer.roughness = material_inputs.roughness;
    buffer.alpha = max(0.001h, buffer.roughness * buffer.roughness);
    buffer.occlusion = material_inputs.occlusion;
    buffer.subsurface_intensity = material_inputs.subsurface_intensity;

    return buffer;
}


// ====================================================================
//  BSDF 数据结构体
// ====================================================================
struct FSubstrateBSDF
{
    half3 normal_ws;      // todo: 应该放在这里吗
    //half3 reflect_dir_ws;   // todo: 应该放在这里吗
    half3 diffuse_albedo;
    half3 f0_dielectric;        // 非电介质，跳过电介质的计算
    half  roughness;
    half  alpha;
    //half  specular;
    //half occlusion;             // todo: occlusion 本是材质属性，会写在这里吗
    //half  metallic;
    //half  subsurface_intensity;
};

inline FSubstrateBSDF SetupSubstrateBSDF(FMaterialPixelParameters pixel_params, FPixelMaterialInputs material_inputs)
{
    FSubstrateBSDF bsdf = (FSubstrateBSDF)0;
    half3x3 tbn = half3x3(pixel_params.WorldTangent, pixel_params.bitangent_ws, pixel_params.WorldNormal);
    bsdf.normal_ws = SafeNormalize(mul(material_inputs.normal_ts, tbn));
    //bsdf.reflect_dir_ws = reflect(-pixel_params.view_dir_ws, bsdf.normal_ws);
    bsdf.diffuse_albedo = material_inputs.base_color;
    bsdf.f0_dielectric = half3(0.08h, 0.08h, 0.08h) * material_inputs.specular;
    bsdf.roughness       = material_inputs.roughness;
    bsdf.alpha = max(0.001h, material_inputs.roughness * material_inputs.roughness); // todo: 暂时未定使用哪套标准
    //bsdf.specular = material_inputs.specular;
    //bsdf.metallic = 0.0h;
    //bsdf.subsurface_intensity = material_inputs.subsurface_intensity;

    return bsdf;
}

inline FSubstrateBSDF SetupSubstrateBSDF(FGBufferData buffer)
{
    FSubstrateBSDF bsdf = (FSubstrateBSDF)0;
    
    bsdf.normal_ws = buffer.normal_ws;
    bsdf.diffuse_albedo = buffer.diffuse_albedo;
    bsdf.f0_dielectric = buffer.F0;
    bsdf.roughness = buffer.roughness;
    bsdf.alpha = buffer.alpha;
    return bsdf;
}

// ====================================================================
// 视线与逐光源点积上下文
// ====================================================================
struct FBxDFContext
{
    half NoL; 
    half NoV;
    half NoH;
    half VoH;
    half VoL;
};

inline FBxDFContext InitBxDFContext(half3 N, half3 V, half3 L)
{
    FBxDFContext ctx = (FBxDFContext)0;

    ctx.NoL     = saturate(dot(N, L));
    ctx.NoV = max(saturate(dot(N, V)), 1e-5h); //todo: 等等看一下这里为什么要防止0？

    half3 H       = SafeNormalize(V + L);
    ctx.NoH     = saturate(dot(N, H));
    ctx.VoH     = saturate(dot(V, H));
    ctx.VoL     = saturate(dot(V, L));

    return ctx;
}