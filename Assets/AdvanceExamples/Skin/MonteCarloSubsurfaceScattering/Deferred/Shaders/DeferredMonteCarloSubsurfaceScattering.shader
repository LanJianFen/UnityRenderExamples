Shader "Advance Examples/SSS/Deferred MonteCarlo SSS"
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
        _MoleScale("Mole Scale", Range(0.0, 1.0)) = 0.0
        _MoleIntensity("Mole Intensity",  Range(0.0, 1.0)) = 0.0
        [Header(Lipstick)]
        [Space(5)]
        _LipstickMap("Lipstick Map", 2D) = "white"{}
        _LipstickTint("Lipstick Tint", Color) = (0.9921569, 0.0, 0.4588234, 1.0)
        _LipstickIntensity("Lipstick Intensity",  Range(0.0, 1.0)) = 0.0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "UniversalMaterialType" = "Unlit" }
        
        Pass
        {
            Name "GBuffer"
            Tags{"LightMode" = "UniversalGBuffer"}
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
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityGBuffer.hlsl"
            #include "DeferredSubsurfaceInput.hlsl"
            #include "DeferredSubsurfaceVertexFactory.hlsl"
            #include "DeferredSubsurfaceMaterialInputs.hlsl"
            #include "DeferredSubsurfaceGBuffer.hlsl"
            #include "DeferredSubsurfaceShadingModel.hlsl"
            
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT

            
            FBasePassVSToPS vert(FVertexFactoryInput Input)
            {
                FBasePassVSToPS Output;
                float3 WorldPosition = TransformObjectToWorld(Input.Position.xyz);
                Output.Position            = TransformWorldToHClip(WorldPosition);
                Output.FactoryInterpolants = VertexFactoryGetInterpolantsVSToPS(Input);
                return Output;
            }
            
            FragmentGBufferOutput frag(FVertexFactoryInterpolantsVSToPS Interpolants, float4 SvPosition : SV_POSITION, FRONT_FACE_TYPE bIsFrontFace : FRONT_FACE_SEMANTIC)
            {
                // 阶段 1 : 像素上下文
                FMaterialPixelParameters MaterialParameters = GetMaterialPixelParameters(Interpolants, SvPosition);
                
                // 阶段 2 : 材质引脚解包 + 像素上下文 Ex
                FPixelMaterialInputs PixelMaterialInputs = (FPixelMaterialInputs)0;
                float4 ScreenPosition = SvPositionToResolvedScreenPosition(SvPosition);
                float3 TranslatedWorldPosition = SvPositionToResolvedTranslatedWorld(SvPosition);
                CalcMaterialParametersEx(MaterialParameters, PixelMaterialInputs, SvPosition, ScreenPosition,
                                         bIsFrontFace, TranslatedWorldPosition, TranslatedWorldPosition);
            
                // 阶段 3 : GBuffer 填充
                half3 BaseColor      = GetMaterialBaseColor(PixelMaterialInputs);
                half  Metallic       = GetMaterialMetallic(PixelMaterialInputs);
                half  Specular       = GetMaterialSpecular(PixelMaterialInputs);
                half  Roughness      = GetMaterialRoughness(PixelMaterialInputs);
                half  MaterialAO     = GetMaterialAmbientOcclusion(PixelMaterialInputs);
                half  Opacity        = GetMaterialOpacity(PixelMaterialInputs);
                uint  ShadingModelID = GetMaterialShadingModel(PixelMaterialInputs);
                
                FGBufferData GBuffer = (FGBufferData)0;

                // ---- 与着色模型相关的字段 ----
                SetGBufferForShadingModel(GBuffer, MaterialParameters, Opacity, BaseColor, Metallic, Specular,
                                          Roughness, 0, 0, 0, 0, ShadingModelID);

                FShadingOcclusion ShadingOcclusion = BuildShadingOcclusion(MaterialAO);

                // UE 这里会调用 ApplyBentNormal(...)，我们没有 BentNormal，所以跳过
                GBuffer.GBufferAO = AOMultiBounce(Luminance(GBuffer.SpecularColor), ShadingOcclusion.SpecOcclusion).g;

                half3 IndirectLighting = EvaluateIndirectLighting(GBuffer, MaterialParameters, ShadingOcclusion, Roughness, SvPosition);

                // ---- 总输出 ----
                half3 Color = IndirectLighting + GetMaterialEmissive(PixelMaterialInputs);
                FragmentGBufferOutput Out;
                EncodeGBuffer(GBuffer, Color, Out);
                return Out;
            }
            ENDHLSL
        }
    }
}