#pragma once

TEXTURE2D(_BaseColorMap);
TEXTURE2D(_NormalMap);
TEXTURE2D(_MaterialMap);
// Eye
TEXTURE2D(_EyelidNormalMap);
TEXTURE2D(_EyeshadowMap);
TEXTURE2D(_EyelinerMap);
TEXTURE2D(_EyebrowMask);
// Blush
TEXTURE2D(_BlushMask);
// Mole
TEXTURE2D(_MoleMap);
// LipstickMap
TEXTURE2D(_LipstickMap);

// Subsurface Scattered Rt
TEXTURE2D(_MonteCarloSubsurfaceScatteredRt); SAMPLER(sampler_MonteCarloSubsurfaceScatteredRt);

CBUFFER_START(UnityPerMaterial)
    half _Roughness;
    half _Specular;
    half _Occlusion;
    half _Subsurface;

    // Eye
    half _EyelidIntensity;
    half _LeftEyeCloseWeight;
    half _RightEyeCloseWeight;
    half4 _EyeshadowTint;
    half _EyeshadowIntensity;
    half4 _EyelinerTint;
    half _EyelinerIntensity;
    half4 _EyebrowTint;
    half _EyebrowIntensity;

    //Blush
    half4 _BlushTint;
    half _BlushIntensity;

    //Mole
    half _MoleUVX;
    half _MoleUVY;
    half _MoleScale;
    half4 _MoleTint;
    half _MoleIntensity;

    //LipstickMap
    half4 _LipstickTint;
    half _LipstickIntensity;
    half _MonteCarloBaseColorScatteringWeight;
CBUFFER_END