
// ====================================================================
//  BSDF 数据结构体
// ====================================================================
struct FSubstrateBSDFSlab
{
    half3 WorldNormal;      // todo: 应该放在这里吗
    half3 BaseColor;
    half3 DiffuseColor;
    half3 F0;        // 非电介质，跳过电介质的计算
    half3 F90;
    half  Roughness;
    half  Alpha;
    //half occlusion;             // todo: occlusion 本是材质属性，会写在这里吗
    half  Metallic;
    //half  subsurface_intensity;
};

inline FSubstrateBSDFSlab SetupSubstrateBSDF(FMaterialPixelParameters Parameters, FPixelMaterialInputs PixelMaterialInputs)
{
    FSubstrateBSDFSlab bsdf = (FSubstrateBSDFSlab)0;
    bsdf.WorldNormal = Parameters.WorldNormal;
    bsdf.BaseColor = PixelMaterialInputs.BaseColor;
    bsdf.DiffuseColor = PixelMaterialInputs.BaseColor * (1.0h - PixelMaterialInputs.Metallic);
    bsdf.F0 = (half3)0.08h * PixelMaterialInputs.Specular;
    bsdf.F90 =(half3)1.0h;
    bsdf.Roughness       = PixelMaterialInputs.Roughness;
    bsdf.Alpha = PixelMaterialInputs.Roughness * PixelMaterialInputs.Roughness;
    //bsdf.specular = material_inputs.specular;
    bsdf.Metallic = PixelMaterialInputs.Metallic;
    //bsdf.subsurface_intensity = material_inputs.subsurface_intensity;

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
    half LoH;
    half VoL;
};

inline FBxDFContext InitBxDFContext(half3 N, half3 V, half3 L)
{
    FBxDFContext ctx = (FBxDFContext)0;

    ctx.NoL     = saturate(dot(N, L));
    ctx.NoV = saturate(abs(dot(N, V)) + 1e-5h);

    half3 H       = normalize(V + L);
    ctx.NoH     = saturate(dot(N, H));
    ctx.VoH     = saturate(dot(V, H));
    ctx.LoH     = saturate(dot(L, H));
    ctx.VoL     = saturate(dot(V, L));

    return ctx;
}