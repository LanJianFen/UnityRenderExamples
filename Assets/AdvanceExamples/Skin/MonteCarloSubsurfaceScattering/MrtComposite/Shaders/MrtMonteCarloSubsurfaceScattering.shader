Shader "Advance Examples/SSS/Mrt MonteCarlo SSS"
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
        _SubsurfaceIntensity("Subsurface Intensity", Range(0.0, 1.0)) = 0.5
        [Header(Eye)]
        [Space(5)]
        _EyelidNormalMap("Eyelid Normal Map", 2D) = "bump"{}
        _LeftEyeCloseWeight("Left Eye Close Weight", Range(0.0, 1.0)) = 0.0
        _RightEyeCloseWeight("Right Eye Close Weight", Range(0.0, 1.0)) = 0.0
        _EyeshadowMap("Eyeshadow Map", 2D) = "white"{}
        _EyeshadowTint("Eyeshadow Tint", Color) = (1.0, 1.0, 1.0, 1.0)
        _EyelinerMap("Eyeliner Map", 2D) = "white"{}
        _EyelinerTint("Eyeliner Tint", Color) = (1.0, 1.0, 1.0, 1.0)
        _EyebrowMask("Eyebrow Mask", 2D) = "white"{}
        _EyebrowTint("Eyebrow Tint", Color) = (1.0, 1.0, 1.0, 1.0)
        [Header(Blush)]
        [Space(5)]
        _BlushMask("Blush Mask", 2D) = "white"{}
        _BlushTint("Blush Tint", Color) = (1.0, 1.0, 1.0, 1.0)
        [Header(Mole)]
        [Space(5)]
        _MoleUVX("Mole UV X", Range(0.0, 1.0)) = 0.0
        _MoleUVY("Mole UV Y", Range(0.0, 1.0)) = 0.0
        _MoleScale("Mole Scale", Range(0.0, 1.0)) = 0.0
        _MoleIntensity("Mole Intensity",  Range(0.0, 1.0)) = 0.0
        [Header(Lipstick)]
        [Space(5)]
        _LipstickMap("Lipstick Map", 2D) = "white"{}
        _LipstickTint("Lipstick Tint", Color) = (1.0, 1.0, 1.0, 1.0)
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "RenderPipeline"="UniversalPipeline"
        }
        
        Pass
        {
            Tags
            {
                "LightMode" = "Monte Carlo Subsurface Forward"
            }

            //Stencil
            //{
            //    Ref 1 // 我们的暗号是数字 1
            //    Comp Always // 永远通过
            //    Pass Replace // 画到哪里，就把哪里的模板值替换成 1
            //}

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "SubsurfaceInput.hlsl"
            #include "SubsurfaceVertexFactory.hlsl"
            #include "SubsurfaceMaterialInputs.hlsl"
            #include "SubstrateBsdfSlab.hlsl"
            #include "SubsurfaceLightAccumulator.hlsl"
            #include "SubsurfaceShadingModel.hlsl"

            FBasePassVSToPS vert(FVertexFactoryInput Input)
            {
                FBasePassVSToPS Output;
                float3 WorldPosition = TransformObjectToWorld(Input.Position.xyz);
                Output.Position            = TransformWorldToHClip(WorldPosition);
                Output.FactoryInterpolants = VertexFactoryGetInterpolantsVSToPS(Input);
                return Output;
            }
            
            FSubsurfaceFragOutput frag(FVertexFactoryInterpolantsVSToPS Interpolants, float4 SvPosition : SV_POSITION, FRONT_FACE_TYPE bIsFrontFace : FRONT_FACE_SEMANTIC) : SV_TARGET
            {
                FSubsurfaceFragOutput o = (FSubsurfaceFragOutput)0;

                // 阶段 1：几何上下文
                FMaterialPixelParameters PixelParameters = GetMaterialPixelParameters(Interpolants, SvPosition);

                // 阶段 2：采样贴图与材质解包
                //FPixelMaterialInputs material_inputs = GetPixelMaterialInputs(pixel_params);
                FPixelMaterialInputs MaterialInputs = (FPixelMaterialInputs)0;
                float4 ScreenPosition = SvPositionToResolvedScreenPosition(SvPosition);
                float3 TranslatedWorldPosition = SvPositionToResolvedTranslatedWorld(SvPosition);
                CalcMaterialParametersEx(PixelParameters, MaterialInputs, SvPosition, ScreenPosition,
                                         bIsFrontFace, TranslatedWorldPosition, TranslatedWorldPosition);
            
                // 阶段 3： GBUFFER 数据, 模拟 UE5 的 Deffered Rendering
                //FGBufferData buffer = SetupGBufferData(PixelParameters, material_inputs);
                
                // 阶段 4： BSDF 数据
                FSubstrateBSDFSlab slab = SetupSubstrateBSDF(PixelParameters, MaterialInputs);

                // 阶段 5：逐光源光照积分求值与累加
                FLightingAccumulator accumulator = EvaluateAllLighting(slab, PixelParameters);

                // 输出至 3 张 Render Target (MRT)
                o.diffuse  = half4(accumulator.scatterable_light, 1.0f);
                o.specular = accumulator.total_light;
                o.albedo   = bsdf.diffuse_albedo;

                return o;
            }
            ENDHLSL
        }
    }
}