half3 SampleWorldNormal(float2 uv0, float2 uv2, float3 normalWS, float4 tangentWS)
{
    half eyeSideClose = (uv0.x >= 0.5h) ? _RightEyeClose : _LeftEyeClose;

    // 睁眼法线: 普通法线贴图
    half3 mainNormalOpen = UnpackNormal(SAMPLE_TEXTURE2D_BIAS(_NormalMap, sampler_NormalMap, uv0, _AlbedoLODBias));

    // 闭眼法线 (对齐 NormalSkinData, uv2 = 眼皮区域)
    half4 closeEyeProperty = SAMPLE_TEXTURE2D_BIAS(_ClosedEyeAlbedo, sampler_LinearClamp, uv2, _AlbedoLODBias);
    half  closeEyeWeight   = closeEyeProperty.a;
    half3 closeEyeNormal   = UnpackNormal(SAMPLE_TEXTURE2D_BIAS(_ClosedEyeNormal, sampler_LinearClamp, uv2, _AlbedoLODBias));

    // 双眼皮沟槽细节法线 (Default 贴图, 手动重建, 不走 UnpackNormal, .z/.w 另有用途)
    half4 detailNRaw = SAMPLE_TEXTURE2D(_DoubleEyelidMap, sampler_NormalMap, uv2);
    half2 detailNxy = detailNRaw.xy * 2.0h - 1.0h;
    half3 detailNormalTS = half3(detailNxy, sqrt(saturate(1.0h - dot(detailNxy, detailNxy))));

    half3 normalTS = lerp(mainNormalOpen, detailNormalTS, detailNRaw.w * _DoubleEyelidWeight);
    normalTS = lerp(normalTS, closeEyeNormal, eyeSideClose * closeEyeWeight);
    normalTS = normalize(normalTS);

    half3 bitangentWS = cross(normalWS, tangentWS.xyz) * tangentWS.w;
    return normalize(normalTS.x * tangentWS.xyz +
                     normalTS.y * bitangentWS +
                     normalTS.z * normalWS);
}

void InitializeNormalData(INPUT input)
{
    // ---- 2) 眼皮闭合权重（按 uv0.x 左右判定）----
    half eyeSideClose = (input.uv0.x >= 0.5h) ? _RightEyeClose : _LeftEyeClose;

    // ---- 3) Base albedo + tint（对齐 Face_Core: lerp(albedo, albedo × tint, weight)）----
    half4 albedoProperty = SAMPLE_TEXTURE2D_BIAS(_AlbedoMap, sampler_LinearClamp, input.uv0, _AlbedoLODBias);
    half3 baseAlbedo = lerp(albedoProperty.rgb, albedoProperty.rgb * _AlbedoTint.rgb, _AlbedoTintWeight);

    // ---- 4) 闭眼贴图 (对齐 NormalSkinData, uv2 = 眼皮区域) ----
    //   _ClosedEyeAlbedo: rgb = 闭眼颜色, a = 跟 base albedo 的混合权重
    //   _ClosedEyeNormal: 闭眼法线 (普通切线空间法线贴图)
    half4 closeEyeProperty = SAMPLE_TEXTURE2D_BIAS(_ClosedEyeAlbedo, sampler_LinearClamp, input.uv2, _AlbedoLODBias);
    half3 closeEyeAlbedo   = closeEyeProperty.rgb;
    half  closeEyeWeight   = closeEyeProperty.a;

    // ---- 5) 法线合成 (切线空间): 睁眼法线 → 叠双眼皮沟槽细节 → 按 eyeSideClose × closeEyeWeight 混合到闭眼法线 ----
    half3 mainNormalOpen  = UnpackNormal(SAMPLE_TEXTURE2D_BIAS(_NormalMap, sampler_LinearClamp, input.uv0, _AlbedoLODBias));
    half3 closeEyeNormal  = UnpackNormal(SAMPLE_TEXTURE2D_BIAS(_ClosedEyeNormal, sampler_LinearClamp, input.uv2, _AlbedoLODBias));

    half4 detailNRaw = SAMPLE_TEXTURE2D(_DoubleEyelidMap, sampler_LinearClamp, input.uv2);
    half2 detailNxy  = detailNRaw.xy * 2.0h - 1.0h;
    half3 detailNormalTS = half3(detailNxy, sqrt(saturate(1.0h - dot(detailNxy, detailNxy))));

    half3 normalTS = lerp(mainNormalOpen, detailNormalTS, detailNRaw.w * _DoubleEyelidWeight);
    normalTS = lerp(normalTS, closeEyeNormal, eyeSideClose * closeEyeWeight);
    surface.tNormal = normalize(normalTS);

    // ---- 6) albedo: 先按闭眼贴图做颜色切换 (差值法, 对齐 NormalSkinData), 再叠双眼皮沟槽 darken ----
    half3 deltaAlbedo = closeEyeWeight * (closeEyeAlbedo - baseAlbedo);
    half3 eyeBlendedAlbedo = eyeSideClose * deltaAlbedo + baseAlbedo;
    half3 detailDarken = lerp(_DoubleEyelidTint, (half3)1.0h, detailNRaw.z);
    surface.albedo = eyeBlendedAlbedo * lerp(detailDarken, (half3)1.0h, eyeSideClose);

    return surface;
}

void Makeup(surface surface, Input input)
{
    half3 albedo;
    
    // 腮红
    half blusher_mask      = SAMPLE_TEXTURE2D(_BlusherMask, sampler_LinearClamp, uvBlusher).a;
    albedo          = lerp(albedo.rgb, _BlusherColor.rgb, blusher_mask);

    // 眼影 
    uvEyeshadow.x = _Eyeshadow_Double * uvEyeshadow.x + (1.0h - _Eyeshadow_Double) * (uvEyeshadow.x * 2.0h * step(uvEyeshadow.x, 0.5h) + (2.0h - uvEyeshadow.x * 2.0h) * step(0.5h, uvEyeshadow.x));
    half3 eye_shadow_mask        = SAMPLE_TEXTURE2D(_EyeshadowMask,   sampler_LinearClamp, uv_eye_shadow).a;
    albedo     = lerp(albedo.rgb, _EyeshadowColor.rgb, eye_shadow_mask);


    // 痣
    float2 uvMole = saturate((input.uv0 + _MoleUVOffset.xy - 0.5) * (100.0h - _MoleUVScale * 100.0h) + 0.5);
    half4  mole   = SAMPLE_TEXTURE2D(_MoleMap, sampler_LinearClamp, uvMole);
    albedo = ApplyMakeupLerp(albedo, mole, _MoleTint.rgb, _MoleStrength * 2.0h);
}

half3 ApplyMakeupLerp(half3 base, half4 sample, half3 tint, half strength)
{
    half weight = saturate(sample.a * strength);
    return lerp(base, sample.rgb * tint, weight);
}

half3 SamplePreIntegratedSkin(half NoL, half curvature)
{
    half3 sssNormal = lerp(normalize(i.normalWS), N, 0.4);
    half  sssNoL    = dot(sssNormal, mainLight.direction);
    mainSssDiffuse = SamplePreIntegratedSkin(sssNoL, surface.curvature) * mainLightColor * shadowFactor * mainLight.shadowAttenuation * mainLight.distanceAttenuation;
    float2 lut_uv = float2(NoL * 0.5h + 0.5h, curvature);
    return SAMPLE_TEXTURE2D_LOD(_PreIntegratedSkinLUT, sampler_LinearClamp, lut_uv, 0).rgb;
}

