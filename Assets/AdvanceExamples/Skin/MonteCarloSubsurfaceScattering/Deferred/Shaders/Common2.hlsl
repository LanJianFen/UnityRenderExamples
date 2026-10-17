
// ====================================================================
//  BSDF 数据结构体
// ====================================================================
struct FSubstrateBSDFSlab
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

inline FSubstrateBSDFSlab SetupSubstrateBSDF(FMaterialPixelParameters pixel_params, FPixelMaterialInputs material_inputs)
{
    FSubstrateBSDFSlab bsdf = (FSubstrateBSDFSlab)0;
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

inline FSubstrateBSDFSlab SetupSubstrateBSDF(FGBufferData buffer)
{
    FSubstrateBSDFSlab bsdf = (FSubstrateBSDFSlab)0;
    
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