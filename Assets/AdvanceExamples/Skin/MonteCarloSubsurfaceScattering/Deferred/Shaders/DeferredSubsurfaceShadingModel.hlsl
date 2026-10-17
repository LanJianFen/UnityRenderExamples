inline BRDFData BrdfDataUrp(FGBufferData GBuffer)
{
    BRDFData brdfData;
    half  BrdfAlpha            = 1.0h;
    half  Reflectivity         = ReflectivitySpecular(GBuffer.SpecularColor);
    half  OneMinusReflectivity = 1.0h - Reflectivity;
    InitializeBRDFDataDirect(GBuffer.BaseColor, GBuffer.BaseColor * OneMinusReflectivity, GBuffer.SpecularColor, Reflectivity, OneMinusReflectivity, 1.0h - GBuffer.Roughness, BrdfAlpha, brdfData);
    return brdfData;
}


inline half3 EvaluateIndirectLighting(FGBufferData GBuffer, FMaterialPixelParameters Parameters, FShadingOcclusion Occ, half Roughness, float4 SvPosition)
{
    // SH
    half3 DiffuseIndirectLighting = SampleSH(Parameters.WorldNormal);
    half3 diffuse = DiffuseIndirectLighting * GBuffer.DiffuseColor * AOMultiBounce(GBuffer.BaseColor, Occ.DiffOcclusion);

    // IBL
    half  NoV = max(dot(Parameters.WorldNormal, Parameters.CameraVector), 1e-4h);
    half3 prefiltered = GlossyEnvironmentReflection(Parameters.ReflectionVector, Parameters.AbsoluteWorldPosition, Roughness, 1.0h,GetNormalizedScreenSpaceUV(SvPosition));
    half3 specular = prefiltered * EnvironmentBRDFSpecular(BrdfDataUrp(GBuffer), Pow4(1.0h - NoV)) * Occ.SpecOcclusion;

    return diffuse + specular;
}

FShadingOcclusion BuildShadingOcclusion(half materialAO)
{
    FShadingOcclusion o;
    o.DiffOcclusion = materialAO;
    o.SpecOcclusion = materialAO;
    return o;   // UE 这里还有 ApplyBentNormal，我们没有 BentNormal
}