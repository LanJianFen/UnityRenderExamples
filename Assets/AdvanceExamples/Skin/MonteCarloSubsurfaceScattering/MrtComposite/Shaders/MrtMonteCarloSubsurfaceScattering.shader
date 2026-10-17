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
            /*#pragma vertex vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include  "Assets/Common/Shaders/Math.hlsl"
            #include  "Assets/Common/Shaders/BSDF.hlsl"
            #include  "SubsurfaceInput.hlsl"
            #include  "SubsurfaceLightAccumulator.hlsl"
            #include  "SubsurfaceShadingCommon.hlsl"
            #include  "SubsurfaceShadingModel.hlsl"

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _FORWARD_PLUS
            
            struct FSubsurfaceFragOutput
            {
                half4 diffuse  : SV_Target0; // RT0: diffuse RT (供 SSS 模糊)
                half3 specular : SV_Target1; // RT1: Total Non-scattered / Specular
                half3 albedo   : SV_Target2; // RT2: Material Albedo, 最后一起合成
            };
            
            FVertexToPixel vert(FVertexInput i)
            {
                FVertexToPixel o = (FVertexToPixel)0;
                o.uv01 = float4(i.uv0, i.uv1), o.uv23 = float4(i.uv2, i.uv3);
                o.position_ws = TransformObjectToWorld(i.position_os.xyz);
                o.position_cs = TransformWorldToHClip(o.position_ws.xyz);
                
                float4 ndc = o.position_cs * 0.5f;
                o.position_ndc.xy = float2(ndc.x, ndc.y * _ProjectionParams.x) + ndc.w;
                o.position_ndc.zw = o.position_cs.zw;
                
                o.normal_ws = TransformObjectToWorldNormal(i.normal_os, true);
                real sign = real(i.tangent_os.w) * GetOddNegativeScale();
                o.tangent_ws = real4(TransformObjectToWorldDir(i.tangent_os.xyz), sign);
                return o;
            }
            
            FSubsurfaceFragOutput frag(FVertexToPixel i) : SV_Target
            {
                FSubsurfaceFragOutput o = (FSubsurfaceFragOutput)0;

                // 阶段 1：几何上下文
                FMaterialPixelParameters pixel_params = SetupMaterialPixelParameters(i);

                // 阶段 2：采样贴图与材质解包
                FPixelMaterialInputs material_inputs = GetPixelMaterialInputs(pixel_params);

                // 阶段 3： GBUFFER 数据, 模拟 UE5 的 Deffered Rendering
                FGBufferData buffer = SetupGBufferData(pixel_params, material_inputs);
                
                // 阶段 4： BSDF 数据
                FSubstrateBSDF bsdf = SetupSubstrateBSDF(pixel_params, material_inputs);
                
                // 阶段 5：逐光源光照积分求值与累加
                FLightingAccumulator accumulator = EvaluateAllLighting(bsdf, pixel_params);

                // 输出至 3 张 Render Target (MRT)
                o.diffuse  = half4(accumulator.scatterable_light, 1.0f);
                o.specular = accumulator.total_light;
                o.albedo   = bsdf.diffuse_albedo;

                return o;
            }*/
            ENDHLSL
        }
    }
}