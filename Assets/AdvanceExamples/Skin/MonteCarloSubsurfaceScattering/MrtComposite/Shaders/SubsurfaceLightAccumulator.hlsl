#pragma once

struct FDirectLighting
{
    half3 diffuse;
    half3 specular;
    half3 transmission;
};

struct FLightingAccumulator
{
    half3 total_light;       // 不参与 SSS 的光照
    half3 scatterable_light; // 屏幕空间参与 SSS 的光照
};

inline FLightingAccumulator LightAccumulator_Init()
{
    FLightingAccumulator accumulator;
    accumulator.total_light       = (half3)0.0h;
    accumulator.scatterable_light = (half3)0.0h;
    return accumulator;
}

inline void LightAccumulator_Add(inout FLightingAccumulator accumulator,half3 diffuse_light,half3 specular_total,half3 scatterable_light,half3 light_color,bool  b_enable_scatter)
{
    accumulator.total_light += specular_total * light_color;
    
    if (b_enable_scatter)
        accumulator.scatterable_light += scatterable_light * light_color;
    else
        accumulator.total_light += diffuse_light * light_color;
}

inline void LightAccumulator_Add(inout FLightingAccumulator accumulator, half3 specular_total, half3 scatterable_light, half3 light_color = 1.0h, half attenuation = 1.0h)
{
    accumulator.total_light += specular_total * light_color * attenuation;
    accumulator.scatterable_light += scatterable_light * light_color * attenuation;
}

inline void LightAccumulator_Add(inout FLightingAccumulator accumulator, half3 specular_total, half3 scatterable_light)
{
    accumulator.total_light += specular_total;
    accumulator.scatterable_light += scatterable_light;
}