#pragma once

inline FDirectLighting EvaluateDirectLighting(FSubstrateBSDF bsdf, FBxDFContext bxdf_ctx)
{
    FDirectLighting lighting = (FDirectLighting) 0;
    // 主高光 Lobe 1
    // todo: 后续考虑改成 alpha 而不是 roughness 的版本
    half3 DFV = D_GGX(bxdf_ctx.NoH, bsdf.roughness) * 
        F_Schlick(bsdf.f0_dielectric, bxdf_ctx.VoH) * 
            V_SmithJointGGX(bxdf_ctx.NoL, bxdf_ctx.NoV, bsdf.roughness);
    
    // todo: 高光 Lobe 2
    
    lighting.diffuse = bxdf_ctx.NoL * INV_PI; // 暂时不考虑能量守恒，缺少 Ft_in
    lighting.specular = DFV * bxdf_ctx.NoL;
    lighting.transmission = 0.0h;
    return lighting;
}

inline void EvaluateIndirectLighting(FSubstrateBSDF bsdf, half3 view_dir_ws, out half3 diffuse, out half3 specular, out half3 scatterable)
{

    half3 sh_irradiance = SampleSH(bsdf.normal_ws);

    diffuse = sh_irradiance * bsdf.occlusion;
    specular = IBL_Specular_Approximation(view_dir_ws, bsdf.normal_ws, bsdf.f0_dielectric, bsdf.roughness, bsdf.occlusion);
    scatterable = sh_irradiance * bsdf.occlusion;
}

FLightingAccumulator EvaluateAllLighting(FSubstrateBSDF bsdf, FMaterialPixelParameters pixel_params)
{
    FLightingAccumulator accumulator = LightAccumulator_Init();

    float4 main_shadow_coord = TransformWorldToShadowCoord(pixel_params.AbsoluteWorldPosition);
    Light main_light = GetMainLight(main_shadow_coord);
    FBxDFContext main_ctx = InitBxDFContext(bsdf.normal_ws, pixel_params.CameraVector, main_light.direction);
    
    FDirectLighting main_lighting = EvaluateDirectLighting(bsdf, main_ctx);
    LightAccumulator_Add(accumulator,main_lighting.specular, main_lighting.diffuse, main_light.color, main_light.shadowAttenuation * main_light.distanceAttenuation);
    #if defined(_ADDITIONAL_LIGHTS)
        uint additional_lights_count = GetAdditionalLightsCount();
        
        for (uint light_index = 0u; light_index < additional_lights_count; ++light_index)
        {
            Light additional_light = GetAdditionalLight(light_index, pixel_params.AbsoluteWorldPosition);
            FBxDFContext additional_ctx = InitBxDFContext(bsdf.normal_ws, pixel_params.CameraVector, additional_light.direction);
            
            FDirectLighting additional_lighting = EvaluateDirectLighting(bsdf, additional_ctx);
            LightAccumulator_Add(accumulator, additional_lighting.specular, additional_lighting.diffuse, additional_light.color, additional_light.distanceAttenuation * additional_light.shadowAttenuation);
        }
    #endif

    half3 indirect_diffuse, indirect_specular, indirect_scatterable;
    EvaluateIndirectLighting(bsdf, pixel_params.CameraVector, indirect_diffuse, indirect_specular, indirect_scatterable);
    LightAccumulator_Add(accumulator, indirect_specular, indirect_scatterable);
    
    return accumulator;
}