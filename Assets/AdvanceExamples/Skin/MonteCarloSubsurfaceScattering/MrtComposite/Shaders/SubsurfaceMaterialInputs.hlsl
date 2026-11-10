#pragma once

// ====================================================================
// 材质输入求值结构体
// ====================================================================
struct FPixelMaterialInputs
{
    half3 EmissiveColor;
    half  Opacity;              // SubsurfaceProfile: 散射强度
    half  OpacityMask;
    half3 BaseColor;
    half  Metallic;
    half  Specular;
    half  Roughness;
    half  Anisotropy;
    half3 Normal;               // 切线空间
    half3 Tangent;
    half4 Subsurface;
    half  AmbientOcclusion;
    half2 Refraction;
    half  PixelDepthOffset;
    uint  ShadingModel;
};
struct FShadingOcclusion
{
    half DiffOcclusion;
    half SpecOcclusion;
};
inline half3 GetMaterialNormal(FPixelMaterialInputs I)                              { return I.Normal; }
inline half3 GetMaterialBaseColor(FPixelMaterialInputs I)        { return saturate(I.BaseColor); }
inline half  GetMaterialMetallic(FPixelMaterialInputs I)         { return saturate(I.Metallic); }
inline half  GetMaterialSpecular(FPixelMaterialInputs I)         { return saturate(I.Specular); }
inline half  GetMaterialRoughness(FPixelMaterialInputs I)        { return I.Roughness; }
inline half  GetMaterialAmbientOcclusion(FPixelMaterialInputs I) { return saturate(I.AmbientOcclusion); }
inline half  GetMaterialOpacity(FPixelMaterialInputs I)          { return saturate(I.Opacity); }
inline half3  GetMaterialEmissive(FPixelMaterialInputs I)          { return I.EmissiveColor; }
inline uint  GetMaterialShadingModel(FPixelMaterialInputs I)     { return I.ShadingModel; }
inline float3 TransformTangentNormalToWorld(half3x3 TangentToWorld, float3 TangentNormal)
{
    return normalize(mul(TangentNormal, (float3x3)TangentToWorld));
}

inline half3 AOMultiBounce(half3 BaseColor, half AO)
{
    half3 a =  2.0404h * BaseColor - 0.3324h;
    half3 b = -4.7951h * BaseColor + 0.6417h;
    half3 c =  2.7552h * BaseColor + 0.6903h;
    return max(AO, ((AO * a + b) * AO + c) * AO);
}

inline float3 ReflectionAboutCustomWorldNormal(FMaterialPixelParameters Parameters, float3 WorldNormal, bool bNormalizeInputNormal)
{
    if (bNormalizeInputNormal) WorldNormal = normalize(WorldNormal);
    return -Parameters.CameraVector + WorldNormal * dot(WorldNormal, Parameters.CameraVector) * 2.0;
}

inline half3 DeriveNormalZ(half2 InXY)
{
    return half3(InXY, sqrt(saturate(1.0h - dot(InXY, InXY))));
}

inline half3 BlendAngleCorrectedNormals(half3 BaseNormal, half3 AdditionalNormal)
{
    half3 t = BaseNormal + half3(0, 0, 1);
    half3 u = AdditionalNormal * half3(-1, -1, 1);
    return t * dot(t, u) / t.z - u;
}


inline half3 MF_FaceNormal(FMaterialPixelParameters Parameters)
{
    float2 UV0 = Parameters.TexCoords[0];
    float2 UV2 = Parameters.TexCoords[2];
    half EyeClose = (UV0.x >= 0.5) ? _RightEyeCloseWeight : _LeftEyeCloseWeight;
    // 主法线: RG = 睁眼, BA = 闭眼
    half4 FaceNormalPack = SAMPLE_TEXTURE2D(_NormalMap, sampler_PointClamp, UV0);
    half2 OpenXY   = FaceNormalPack.rg * 2.0h - 1.0h, CloseXY  = FaceNormalPack.ba * 2.0h - 1.0h;
    half3 FaceNormal = DeriveNormalZ(lerp(OpenXY, CloseXY, EyeClose));

    // 眼皮沟槽：睁眼时显示，闭眼时淡出
    half  EyelidWeight = _EyelidIntensity * (1.0h - EyeClose);
    half3 EyelidNormal   = UnpackNormalScale(SAMPLE_TEXTURE2D(_EyelidNormalMap, sampler_PointClamp, UV2), EyelidWeight);
    return BlendAngleCorrectedNormals(FaceNormal, EyelidNormal);
}

inline half3 SampleColorMakeup(half3 BaseColor, TEXTURE2D_PARAM(MaskTex, MaskSampler), float2 UV, half3 Tint, half Strength)
{
    half4 Pack = SAMPLE_TEXTURE2D(MaskTex, MaskSampler, UV);
    half3 Color = Pack.rgb;
    half Mask = Pack.a;
    return lerp(BaseColor, Color * Tint, saturate(Mask * Strength));
}

inline half3 SampleMaskMakeup(half3 BaseColor, TEXTURE2D_PARAM(MaskTex, MaskSampler), float2 UV, half3 Tint, half Strength)
{
    half Mask = SAMPLE_TEXTURE2D(MaskTex, MaskSampler, UV).a;
    return lerp(BaseColor, Tint, saturate(Mask * Strength));
}

inline half3 MF_FaceMakeup(FMaterialPixelParameters Parameters)
{
    float2 UV0      = Parameters.TexCoords[0];
    half3 BaseColor = SAMPLE_TEXTURE2D(_BaseColorMap, sampler_LinearClamp, UV0);
    // 腮红
    float2 UVBlush = Parameters.TexCoords[1];
    BaseColor = SampleMaskMakeup(BaseColor, TEXTURE2D_ARGS(_BlushMask, sampler_LinearClamp), UVBlush ,_BlushTint.rgb, _BlushIntensity);

    // 眼影：_MirrorUV = 1 左右镜像共用；0 左右独立
    float2 UVEyeshadow = Parameters.TexCoords[2];
    float  MirroredX = 1.0f - abs(UVEyeshadow.x * 2.0f - 1.0f); // 把左右脸的 UV 变成 0 - 1 - 0
    UVEyeshadow.x = lerp(MirroredX, UVEyeshadow.x, Parameters.UnMirrored); // 借用一下 UnMirrored
    BaseColor = SampleColorMakeup(BaseColor, TEXTURE2D_ARGS(_EyeshadowMap, sampler_LinearClamp), UVEyeshadow, _EyeshadowTint.rgb, _EyeshadowIntensity);

    // 眼线
    float2 UVEyeliner = Parameters.TexCoords[2];
    MirroredX = 1.0f - abs(UVEyeliner.x * 2.0f - 1.0f); // 把左右脸的 UV 变成 0 - 1 - 0
    UVEyeliner.x = lerp(MirroredX, UVEyeliner.x, Parameters.UnMirrored); // 借用一下 UnMirrored
    BaseColor = SampleColorMakeup(BaseColor, TEXTURE2D_ARGS(_EyelinerMap, sampler_LinearClamp), UVEyeliner, _EyelinerTint.rgb, _EyelinerIntensity);

    // 眉毛
    float2 UVEyebrow = Parameters.TexCoords[3];
    MirroredX = 1.0f - abs(UVEyebrow.x * 2.0f - 1.0f); // 把左右脸的 UV 变成 0 - 1 - 0
    UVEyebrow.x = lerp(MirroredX, UVEyebrow.x, Parameters.UnMirrored); // 借用一下 UnMirrored
    BaseColor = SampleMaskMakeup(BaseColor, TEXTURE2D_ARGS(_EyebrowMask, sampler_LinearClamp), UVEyebrow, _EyebrowTint.rgb, _EyebrowIntensity);

    // 痣
    float2 UVMole = saturate((UV0 + float2(_MoleUVX, _MoleUVY) - 0.5f) * max(100.0f - _MoleScale * 100.0f, 1.0f) + 0.5f);
    BaseColor = SampleMaskMakeup(BaseColor, TEXTURE2D_ARGS(_MoleMap, sampler_LinearClamp), UVMole, _MoleTint.rgb,  _MoleIntensity);

    // 嘴
    float2 UVLipstick = Parameters.TexCoords[3];
    BaseColor = SampleColorMakeup(BaseColor, TEXTURE2D_ARGS(_LipstickMap, sampler_LinearClamp), UVLipstick, _LipstickTint.rgb,  _LipstickIntensity);
    
    return BaseColor;
}


inline void CalcPixelMaterialInputs(inout FMaterialPixelParameters Parameters, inout FPixelMaterialInputs PixelMaterialInputs)
{
    // The Normal is a special case as it might have its own expressions and also be used to calculate other inputs, so perform the assignment here
    PixelMaterialInputs.Normal = MF_FaceNormal(Parameters);
    // 面部法线恒为切线空间：直接转换到世界空间并写回 Parameters
    float3 MaterialNormal = normalize(GetMaterialNormal(PixelMaterialInputs));
    Parameters.WorldNormal = TransformTangentNormalToWorld(Parameters.TangentToWorld, MaterialNormal) * Parameters.TwoSidedSign; // 单面材质
    Parameters.ReflectionVector = ReflectionAboutCustomWorldNormal(Parameters, Parameters.WorldNormal, false);

    half4 RASC = SAMPLE_TEXTURE2D(_MaterialMap, sampler_PointClamp, Parameters.TexCoords[0]);

    // Now the rest of the inputs (从这里开始，节点读到的 Parameters.WorldNormal 已是扰动后的法线)
    PixelMaterialInputs.EmissiveColor    = 0;
    PixelMaterialInputs.Opacity          = saturate(RASC.a * _Subsurface);
    PixelMaterialInputs.OpacityMask      = 1;
    PixelMaterialInputs.BaseColor        = MF_FaceMakeup(Parameters);
    PixelMaterialInputs.Metallic         = 0;
    PixelMaterialInputs.Specular         = saturate(RASC.b * _Specular);
    PixelMaterialInputs.Roughness        = saturate(RASC.r * _Roughness);
    PixelMaterialInputs.Anisotropy       = 0;
    PixelMaterialInputs.Tangent          = half3(1, 0, 0);
    PixelMaterialInputs.Subsurface       = 0;
    PixelMaterialInputs.AmbientOcclusion = saturate(RASC.g * (1.0h - _Occlusion));
    PixelMaterialInputs.Refraction       = 0;
    PixelMaterialInputs.PixelDepthOffset = 0;
    PixelMaterialInputs.ShadingModel     = SHADINGMODELID_SUBSURFACE_PROFILE;
}



inline void CalcMaterialParametersEx(inout FMaterialPixelParameters Parameters, inout FPixelMaterialInputs PixelMaterialInputs,
    float4 SvPosition, float4 ScreenPosition, FRONT_FACE_TYPE bIsFrontFace, float3 TranslatedWorldPosition, float3 TranslatedWorldPositionExcludingShaderOffsets)
{
    Parameters.WorldPosition_CamRelative = TranslatedWorldPosition.xyz;
    Parameters.AbsoluteWorldPosition     = TranslatedWorldPosition.xyz - PreViewTranslation;
    #if USE_WORLD_POSITION_EXCLUDING_SHADER_OFFSETS  // 开启前需要先在结构体里加上这两个字段
    Parameters.WorldPosition_NoOffsets_CamRelative = TranslatedWorldPositionExcludingShaderOffsets;
    Parameters.WorldPosition_NoOffsets             = TranslatedWorldPositionExcludingShaderOffsets - PreViewTranslation;
    #endif
    Parameters.SvPosition     = SvPosition;
    Parameters.ScreenPosition = ScreenPosition;
    Parameters.CameraVector = IsOrthoProjection()? -GetViewForward():normalize(-Parameters.WorldPosition_CamRelative);

    Parameters.TwoSidedSign = 1.0h;
    #if MATERIAL_TWOSIDED
    Parameters.TwoSidedSign *= IS_FRONT_VFACE(bIsFrontFace, 1.0h, -1.0h);
    #endif

    // 材质解包
    CalcPixelMaterialInputs(Parameters, PixelMaterialInputs);
}

