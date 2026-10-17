inline BRDFData BrdfDataUrp(FSubstrateBSDFSlab Slab)
{
    BRDFData brdfData;
    half  BrdfAlpha            = 1.0h;
    half  Reflectivity         = ReflectivitySpecular(Slab.F0);
    half  OneMinusReflectivity = 1.0h - Reflectivity;
    InitializeBRDFDataDirect(Slab.DiffuseColor, Slab.DiffuseColor * OneMinusReflectivity, Slab.F0, Reflectivity, OneMinusReflectivity, 1.0h - Slab.Roughness, BrdfAlpha, brdfData);
    return brdfData;
}

inline half3 EvaluateIndirectLighting(FSubstrateBSDFSlab Slab, FMaterialPixelParameters Parameters, FShadingOcclusion Occ, float3 SvPosition)
{
    // SH
    half3 DiffuseIndirectLighting = SampleSH(Parameters.WorldNormal);
    half3 diffuse = DiffuseIndirectLighting * Slab.DiffuseColor * AOMultiBounce(Slab.BaseColor, Occ.DiffOcclusion);

    // IBL
    half  NoV = max(dot(Parameters.WorldNormal, Parameters.CameraVector), 1e-4h);
    half3 prefiltered = GlossyEnvironmentReflection(Parameters.ReflectionVector, Parameters.AbsoluteWorldPosition, Slab.Roughness, 1.0h,GetNormalizedScreenSpaceUV(SvPosition));
    half3 specular = prefiltered * EnvironmentBRDFSpecular(BrdfDataUrp(Slab), Pow4(1.0h - NoV)) * Occ.SpecOcclusion;

    return diffuse + specular;
}

struct DirectLighting
{
    half3 diffuse;
    half3 specular;
};

inline DirectLighting EvaluateDirectLighting(FSubstrateBSDFSlab Slab, FBxDFContext ctx , half3 LightColor)
{
    DirectLighting lighting = (DirectLighting) 0;
    // Diffuse
    half3 diffuse = LightColor * ctx.NoL * pow(Slab.DiffuseColor, _MonteCarloBaseColorScatteringWeight);
    lighting.diffuse = diffuse;
    
    // Specular
    half3 bsdf = D_GGX(ctx.NoH, Slab.Roughness) * V_SmithJointGGX(ctx.NoL, ctx.NoV, Slab.Roughness) 
                    * F_Schlick(Slab.F0, Slab.F90, ctx.VoH);
    half3 specular = bsdf * LightColor * ctx.NoL;
    
    lighting.specular = specular;
    return lighting;
}

half DirectMobileV(FSubstrateBSDFSlab slab, half LoH)
{
    half LoH2 = LoH * LoH;
    half normalizationTerm = slab.Alpha * 4.0h + 2.0h;
    half VF = 1.0h / (max(0.1h, LoH2) * normalizationTerm);
    return VF;
}
half DirectMobileBRDFSpecular(FSubstrateBSDFSlab slab, FBxDFContext ctx)
{
    float NoH = ctx.NoH;
    half LoH = ctx.LoH;

    // GGX Distribution multiplied by combined approximation of Visibility and Fresnel
    // BRDFspec = (D * V * F) / 4.0
    // D = roughness^2 / ( NoH^2 * (roughness^2 - 1) + 1 )^2
    // V * F = 1.0 / ( LoH^2 * (roughness + 0.5) )
    // See "Optimizing PBR for Mobile" from Siggraph 2015 moving mobile graphics course
    // https://community.arm.com/events/1155

    // Final BRDFspec = roughness^2 / ( NoH^2 * (roughness^2 - 1) + 1 )^2 * (LoH^2 * (roughness + 0.5) * 4.0)
    // We further optimize a few light invariant terms
    // brdfData.normalizationTerm = (roughness + 0.5) * 4.0 rewritten as roughness * 4.0 + 2.0 to a fit a MAD.
    half roughness2MinusOne = slab.Alpha * slab.Alpha - 1.0h;
    float d = NoH * NoH * roughness2MinusOne + 1.00001f;

    half LoH2 = LoH * LoH;
    half normalizationTerm = slab.Alpha * 4.0h + 2.0h;
    half specularTerm = slab.Alpha * slab.Alpha / ((d * d) * max(0.1h, LoH2) * normalizationTerm);

    // On platforms where half actually means something, the denominator has a risk of overflow
    // clamp below was added specifically to "fix" that, but dx compiler (we convert bytecode to metal/gles)
    // sees that specularTerm have only non-negative terms, so it skips max(0,..) in clamp (leaving only min(100,...))
#if REAL_IS_HALF
    specularTerm = specularTerm - HALF_MIN;
    // Update: Conservative bump from 100.0 to 1000.0 to better match the full float specular look.
    // Roughly 65504.0 / 32*2 == 1023.5,
    // or HALF_MAX / ((mobile) MAX_VISIBLE_LIGHTS * 2),
    // to reserve half of the per light range for specular and half for diffuse + indirect + emissive.
    specularTerm = clamp(specularTerm, 0.0, 1000.0); // Prevent FP16 overflow on mobiles
#endif

    return specularTerm;
}

inline DirectLighting EvaluateMobileDirectLighting(FSubstrateBSDFSlab Slab, FBxDFContext ctx , half3 LightColor)
{
    DirectLighting lighting = (DirectLighting) 0;
    // Diffuse
    half3 diffuse = LightColor * ctx.NoL * pow(Slab.DiffuseColor, _MonteCarloBaseColorScatteringWeight);
    lighting.diffuse = diffuse;
    
    // Specular
    half3 specular = DirectMobileBRDFSpecular(Slab, ctx) * LightColor * ctx.NoL * Slab.F0;
    
    lighting.specular = specular;
    return lighting;
}

FShadingOcclusion BuildShadingOcclusion(half materialAO)
{
    FShadingOcclusion o;
    o.DiffOcclusion = materialAO;
    o.SpecOcclusion = materialAO;
    return o;   // UE 这里还有 ApplyBentNormal，我们没有 BentNormal
}