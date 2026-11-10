#pragma once

inline BRDFData BrdfDataUrp(FSubstrateBSDFSlab Slab)
{
    BRDFData brdfData;
    half  BrdfAlpha            = 1.0h;
    half  Reflectivity         = ReflectivitySpecular(Slab.F0);
    half  OneMinusReflectivity = 1.0h - Reflectivity;
    InitializeBRDFDataDirect(Slab.DiffuseColor, Slab.DiffuseColor * OneMinusReflectivity, Slab.F0, Reflectivity, OneMinusReflectivity, 1.0h - Slab.Roughness, BrdfAlpha, brdfData);
    return brdfData;
}

inline FSubsurfaceFragOutput EvaluateIndirectLighting(FSubstrateBSDFSlab Slab, FMaterialPixelParameters Parameters, FShadingOcclusion Occ, float3 SvPosition)
{
    FSubsurfaceFragOutput lighting = (FSubsurfaceFragOutput) 0;
    // SH
    half3 DiffuseIndirectLighting = SampleSH(Parameters.WorldNormal);
    half3 diffuse = DiffuseIndirectLighting * Slab.DiffuseColor * AOMultiBounce(Slab.BaseColor, Occ.DiffOcclusion);

    // IBL
    half  NoV = max(dot(Parameters.WorldNormal, Parameters.CameraVector), 1e-4h);
    half3 prefiltered = GlossyEnvironmentReflection(Parameters.ReflectionVector, Parameters.AbsoluteWorldPosition, Slab.Roughness, 1.0h,GetNormalizedScreenSpaceUV(SvPosition));
    half3 specular = prefiltered * EnvironmentBRDFSpecular(BrdfDataUrp(Slab), Pow4(1.0h - NoV)) * Occ.SpecOcclusion;

    lighting.diffuse = diffuse;
    lighting.specular = specular;
    lighting.transmission = 0.0h;
    return lighting;
}

inline FSubsurfaceFragOutput EvaluateDirectLighting(FSubstrateBSDFSlab Slab, FBxDFContext Ctx)
{
    FSubsurfaceFragOutput lighting = (FSubsurfaceFragOutput) 0;
    // 主高光 Lobe 1
    // todo: 后续考虑改成 alpha 而不是 roughness 的版本
    half3 DFV = D_GGX(Ctx.NoH, Slab.Alpha) * 
        F_Schlick(Slab.F0, Ctx.VoH) * 
            V_SmithJointGGX(Ctx.NoL, Ctx.NoV, Slab.Alpha);
    
    // todo: 高光 Lobe 2
    
    lighting.diffuse = Ctx.NoL; // 暂时不考虑能量守恒，缺少 Ft_in
    lighting.specular = DFV * Ctx.NoL;
    lighting.transmission = 0.0h;
    return lighting;
}

FLightingAccumulator EvaluateAllLighting(FSubstrateBSDFSlab Slab, FMaterialPixelParameters Parameters)
{
    FLightingAccumulator accumulator = LightAccumulator_Init();

    float4 main_shadow_coord = TransformWorldToShadowCoord(Parameters.AbsoluteWorldPosition);
    Light main_light = GetMainLight(main_shadow_coord);
    FBxDFContext main_ctx = InitBxDFContext(Slab.normal_ws, Parameters.CameraVector, normalize(main_light.direction));
    
    FSubsurfaceFragOutput main_lighting = EvaluateDirectLighting(Slab, main_ctx);
    LightAccumulator_Add(accumulator,main_lighting.specular, main_lighting.diffuse, main_light.color, main_light.shadowAttenuation * main_light.distanceAttenuation);
    #if defined(_ADDITIONAL_LIGHTS)
        uint additional_lights_count = GetAdditionalLightsCount();
        
        for (uint light_index = 0u; light_index < additional_lights_count; ++light_index)
        {
            Light additional_light = GetAdditionalLight(light_index, Parameters.AbsoluteWorldPosition);
            FBxDFContext additional_ctx = InitBxDFContext(Slab.normal_ws, Parameters.CameraVector, additional_light.direction);
            
            FLightingAccumulator additional_lighting = EvaluateDirectLighting(Slab, additional_ctx);
            LightAccumulator_Add(accumulator, additional_lighting.specular, additional_lighting.diffuse, additional_light.color, additional_light.distanceAttenuation * additional_light.shadowAttenuation);
        }
    #endif

    half3 indirect_diffuse, indirect_specular, indirect_scatterable;
    EvaluateIndirectLighting(Slab, Parameters.CameraVector, indirect_diffuse, indirect_specular, indirect_scatterable);
    LightAccumulator_Add(accumulator, indirect_specular, indirect_scatterable);
    
    return accumulator;
}