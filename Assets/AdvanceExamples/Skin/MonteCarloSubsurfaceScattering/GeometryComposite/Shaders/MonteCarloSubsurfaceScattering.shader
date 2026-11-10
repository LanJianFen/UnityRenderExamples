Shader "Advance Examples/SSS/MonteCarlo SSS"
{
    Properties
    {
        [Header(Base Surface)]
        [Space(5)]
        _BaseColorMap ("Base Color Map", 2D) = "white" {}
        _NormalMap("Normal Map", 2D) = "bump"{}
        _MaterialMap("Material Map", 2D) = "white"{}
        _Roughness("Roughness", Range(0.0, 1.0)) = 0.5
        _Specular("Specular", Range(0.0, 1.0)) = 0.5
        _Occlusion("Occlusion", Range(0.0, 1.0)) = 0.0
        _Subsurface("Subsurface", Range(0.0, 1.0)) = 0.5
        [Header(Eye)]
        [Space(5)]
        _EyelidNormalMap("Eyelid Normal Map", 2D) = "bump"{}
        _EyelidIntensity("Eyelid Intensity", Range(0.0, 1.0)) = 0.0
        _LeftEyeCloseWeight("Left Eye Close Weight", Range(0.0, 1.0)) = 0.0
        _RightEyeCloseWeight("Right Eye Close Weight", Range(0.0, 1.0)) = 0.0
        _EyeshadowMap("Eyeshadow Map", 2D) = "white"{}
        _EyeshadowTint("Eyeshadow Tint", Color) = (1.0, 0.2509804, 0.2509804, 1.0)
        _EyeshadowIntensity("Eyeshadow Intensity", Range(0.0, 1.0)) = 0.0
        _EyelinerMap("Eyeliner Map", 2D) = "white"{}
        _EyelinerTint("Eyeliner Tint", Color) = (1.0, 0.4339623, 0.4539403, 1.0)
        _EyelinerIntensity("Eyeliner Intensity", Range(0.0, 1.0)) = 0.0
        _EyebrowMask("Eyebrow Mask", 2D) = "white"{}
        _EyebrowTint("Eyebrow Tint", Color) = (0.509434, 0.235493, 0.3209403, 1.0)
        _EyebrowIntensity("Eyebrow Intensity", Range(0.0, 1.0)) = 0.0
        [Header(Blush)]
        [Space(5)]
        _BlushMask("Blush Mask", 2D) = "white"{}
        _BlushTint("Blush Tint", Color) = (1.0, 0.2627451, 0.0, 1.0)
        _BlushIntensity("Blush Intensity", Range(0.0, 1.0)) = 0.0
        [Header(Mole)]
        [Space(5)]
        _MoleMap("Mole Mask", 2D) = "white"{}
        _MoleTint("Mole Tint", Color) = (0.1490196, 0.06666665, 0.04399996, 1.0)
        _MoleUVX("Mole UV X", Range(-1.0, 1.0)) = -0.15
        _MoleUVY("Mole UV Y", Range(-1.0, 1.0)) = -0.05
        _MoleScale("Mole Scale", Range(0.0, 1.0)) = 0.092
        _MoleIntensity("Mole Intensity",  Range(0.0, 1.0)) = 0.0
        [Header(Lipstick)]
        [Space(5)]
        _LipstickMap("Lipstick Map", 2D) = "white"{}
        _LipstickTint("Lipstick Tint", Color) = (0.9921569, 0.0, 0.4588234, 1.0)
        _LipstickIntensity("Lipstick Intensity",  Range(0.0, 1.0)) = 0.0
    }

    SubShader
    {
        Tags {"RenderType"="Opaque" "RenderPipeline"="UniversalPipeline"}
        
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask R      // URP 14 标准写法
            Cull Back        // 和皮肤其他 Pass 的 Cull 保持一致

            HLSLPROGRAM
            #pragma vertex   DepthOnlyVert
            #pragma fragment DepthOnlyFrag
            #pragma multi_compile_instancing
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "SubsurfaceDepthOnly.hlsl"
            ENDHLSL
        }

        Pass
        {
            Tags
            {
                "LightMode" = "Monte Carlo Subsurface Forward"
            }

            /*Stencil
            {
                Ref 1 // 我们的暗号是数字 1
                Comp Always // 永远通过
                Pass Replace // 画到哪里，就把哪里的模板值替换成 1
            }*/

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "SubsurfaceInput.hlsl"
            #include "SubsurfaceVertexFactory.hlsl"
            #include "SubsurfaceMaterialInputs.hlsl"
            #include "SubstrateBsdfSlab.hlsl"
            #include "SubsurfaceShadingModel.hlsl"
            
            FBasePassVSToPS vert(FVertexFactoryInput Input)
            {
                FBasePassVSToPS Output;
                float3 WorldPosition = TransformObjectToWorld(Input.Position.xyz);
                Output.Position            = TransformWorldToHClip(WorldPosition);
                Output.FactoryInterpolants = VertexFactoryGetInterpolantsVSToPS(Input);
                return Output;
            }
            
            half4 frag(FVertexFactoryInterpolantsVSToPS Interpolants, float4 SvPosition : SV_POSITION, FRONT_FACE_TYPE bIsFrontFace : FRONT_FACE_SEMANTIC) : SV_TARGET
            {
                // 阶段 1 : 像素上下文
                FMaterialPixelParameters PixelParameters = GetMaterialPixelParameters(Interpolants, SvPosition);
                
                // 阶段 2 : 材质引脚解包 + 像素上下文 Ex
                FPixelMaterialInputs MaterialInputs = (FPixelMaterialInputs)0;
                float4 ScreenPosition = SvPositionToResolvedScreenPosition(SvPosition);
                float3 TranslatedWorldPosition = SvPositionToResolvedTranslatedWorld(SvPosition);
                CalcMaterialParametersEx(PixelParameters, MaterialInputs, SvPosition, ScreenPosition,
                                         bIsFrontFace, TranslatedWorldPosition, TranslatedWorldPosition);
            
                // 阶段 3 : Bsdf Slab 填充
                FSubstrateBSDFSlab slab = SetupSubstrateBSDF(PixelParameters, MaterialInputs);
                
                Light mainLight = GetMainLight();
                FBxDFContext ctx = InitBxDFContext(PixelParameters.WorldNormal, PixelParameters.CameraVector,  normalize(mainLight.direction));
                DirectLighting lighting = EvaluateDirectLighting(slab, ctx, mainLight.color * mainLight.shadowAttenuation * mainLight.distanceAttenuation);

                return half4(lighting.diffuse, 1.0h);
            }
            ENDHLSL
        }

        Pass
        {
            Tags
            {
                "LightMode" = "Monte Carlo Subsurface Composite"
            }
            
            ZWrite Off 
            ZTest LEqual
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "SubsurfaceInput.hlsl"
            #include "SubsurfaceVertexFactory.hlsl"
            #include "SubsurfaceMaterialInputs.hlsl"
            #include "SubstrateBsdfSlab.hlsl"
            #include "SubsurfaceShadingModel.hlsl"

            
            FBasePassVSToPS vert(FVertexFactoryInput Input)
            {
                FBasePassVSToPS Output;
                float3 WorldPosition = TransformObjectToWorld(Input.Position.xyz);
                Output.Position            = TransformWorldToHClip(WorldPosition);
                Output.FactoryInterpolants = VertexFactoryGetInterpolantsVSToPS(Input);
                return Output;
            }


            half4 frag(FVertexFactoryInterpolantsVSToPS Interpolants, float4 SvPosition : SV_POSITION, FRONT_FACE_TYPE bIsFrontFace : FRONT_FACE_SEMANTIC) : SV_TARGET
            {
                // 阶段 1 : 像素上下文
                FMaterialPixelParameters MaterialParameters = GetMaterialPixelParameters(Interpolants, SvPosition);
                
                // 阶段 2 : 材质引脚解包 + 像素上下文 Ex
                FPixelMaterialInputs PixelMaterialInputs = (FPixelMaterialInputs)0;
                float4 ScreenPosition = SvPositionToResolvedScreenPosition(SvPosition);
                float3 TranslatedWorldPosition = SvPositionToResolvedTranslatedWorld(SvPosition);
                CalcMaterialParametersEx(MaterialParameters, PixelMaterialInputs, SvPosition, ScreenPosition,
                                         bIsFrontFace, TranslatedWorldPosition, TranslatedWorldPosition);
            
                // 阶段 3 : Bsdf Slab 填充
                FSubstrateBSDFSlab slab = SetupSubstrateBSDF(MaterialParameters, PixelMaterialInputs);
                
                Light mainLight = GetMainLight();
                FBxDFContext ctx = InitBxDFContext(MaterialParameters.WorldNormal, MaterialParameters.CameraVector,  normalize(mainLight.direction));
                DirectLighting lighting = EvaluateMobileDirectLighting(slab, ctx, mainLight.color * mainLight.shadowAttenuation * mainLight.distanceAttenuation);
                
                float2 ss_uv = SvPosition.xy / _ScreenParams.xy;
                half3 subsurface = SAMPLE_TEXTURE2D(_MonteCarloSubsurfaceScatteredRt, sampler_MonteCarloSubsurfaceScatteredRt, ss_uv).rgb * (pow(slab.DiffuseColor, 1.0h - _MonteCarloBaseColorScatteringWeight));

                half  MaterialAO     = GetMaterialAmbientOcclusion(PixelMaterialInputs);
                FShadingOcclusion ShadingOcclusion = BuildShadingOcclusion(MaterialAO);

                half3 IndirectLighting = EvaluateIndirectLighting(slab, MaterialParameters, ShadingOcclusion, SvPosition);
                half3 Color = lighting.specular + subsurface + IndirectLighting + GetMaterialEmissive(PixelMaterialInputs);

                //BRDFData brdf;
                //InitializeBRDFData(slab.BaseColor, slab.Metallic, slab.F0,1.0h - slab.Roughness, slab.Alpha, brdf);
                //half3 specular = brdf.specular * DirectBRDFSpecular(brdf, slab.Normal, L, V) * radiance;
                half3 bsdf = D_GGX(ctx.NoH, slab.Alpha) * V_SmithJointGGX(ctx.NoL, ctx.NoV, slab.Alpha) 
                    * F_Schlick(slab.F0, slab.F90, ctx.VoH);
                bsdf = PI * D_GGX(ctx.NoH, slab.Alpha) * DirectMobileV(slab, ctx.LoH) 
                    * slab.F0;
                half3 specular = bsdf * mainLight.color * ctx.NoL;
                return half4(Color, 1.0f);
            }
            ENDHLSL

        }
    }
}