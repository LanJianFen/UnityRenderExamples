#pragma once

TEXTURE2D(_AlbedoMap);
TEXTURE2D(_NormalMap);
TEXTURE2D(_MaterialMap);
TEXTURE2D(_EyelidCloseNormalMap);
TEXTURE2D(_DecalMask);
            
CBUFFER_START(UnityPerMaterial)
    half4 _DecalTint;
    half _Roughness;
    half _Specular;
    half _EyelidCloseWeight;
    half _HairShadowWeight;
CBUFFER_END