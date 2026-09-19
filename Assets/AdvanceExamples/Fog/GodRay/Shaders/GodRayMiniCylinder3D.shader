Shader "Advance Examples/Fog/God Ray/God Ray Mini Cylinder 3D"
{
    Properties
    {
        [Header(Base Emission)]
        [Space(5)]
        _FogColor ("雾气颜色", Color) = (0.9716981,0.7104397,0.7104397,1)
        _Intensity ("亮度", Range(0.0, 1.0)) = 0.5
        //_Contrast ("对比度", Range(1, 2.2)) = 1.0
        
        [Header(Shape and Falloff)]
        [Space(5)]
        [PowerSlider(3.0)] _VerticalFade ("纵向衰减", Range(0.01, 1.0)) = 0.01
        [PowerSlider(3.0)] _HorizontalFade ("横向衰减", Range(0.01, 1.0)) = 0.01
        [PowerSlider(3.0)] _FoggyIntensity ("弥漫强度", Range(0.0, 1.0)) = 0.0
        
        [Header(Cookie Mask)]
        [Space(5)]
        _CookieMask ("遮挡物遮罩", 2D) = "white" {}
        [PowerSlider(4.0)]_Bias ("遮挡 Bias", Range(0.0, 1.0)) = 0.0
    }

    // 外网没有 LOD 1000，800 当最高画质吧
    SubShader
    {
        LOD 1000
        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
            "IgnoreProjector" = "True"
        }
        
        Pass
        {
            Name "GodRayMiniCylinderOutside"
            Tags {"LightMode" = "GodRayMiniForward"}

            Cull Back
            ZWrite Off
            ZTest LEqual
            Blend One One
            
            Stencil
            {
                Ref 3
                Comp Greater
                Pass IncrSat
                Fail Keep
                ZFail Keep
            }

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "GodRayMarchingCore.hlsl"
                        
            #pragma vertex Vert
            #pragma fragment FragEpic

            ENDHLSL
        }

        Pass
        {
            Name "GodRayMiniCylinderInside"
            Tags {"LightMode" = "GodRayMiniForward"}

            Cull Front
            ZWrite Off
            ZTest Always
            Blend One One
            
            Stencil
            {
                Ref 3
                Comp Greater
                Pass IncrSat
                Fail Keep
                ZFail Keep
            }

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "GodRayMarchingCore.hlsl"
                        
            #pragma vertex Vert
            #pragma fragment FragEpic

            ENDHLSL
        }
    }
    SubShader
    {
        LOD 800
        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
            "IgnoreProjector" = "True"
        }
        
        Pass
        {
            Name "GodRayMiniCylinderOutside"
            Tags {"LightMode" = "GodRayMiniForward"}

            Cull Back
            ZWrite Off
            ZTest LEqual
            Blend One One
            
            Stencil
            {
                Ref 3
                Comp Greater
                Pass IncrSat
                Fail Keep
                ZFail Keep
            }

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "GodRayMarchingCore.hlsl"
                        
            #pragma vertex Vert
            #pragma fragment FragHigh

            ENDHLSL
        }
        Pass
        {
            Name "GodRayMiniCylinderInside"
            Tags {"LightMode" = "GodRayMiniForward"}

            Cull Front
            ZWrite Off
            ZTest Always
            Blend One One
            
            Stencil
            {
                Ref 3
                Comp Greater
                Pass IncrSat
                Fail Keep
                ZFail Keep
            }

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "GodRayMarchingCore.hlsl"
                        
            #pragma vertex Vert
            #pragma fragment FragHigh

            ENDHLSL
        }
    }
    SubShader
    {
        LOD 300
        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
            "IgnoreProjector" = "True"
        }
        
        Pass
        {
            Name "GodRayMiniCylinder"
            Tags {"LightMode" = "GodRayMiniForward"}

            Cull Front
            ZWrite Off
            ZTest LEqual
            Blend One One
            
            Stencil
            {
                Ref 3
                Comp Greater
                Pass IncrSat
                Fail Keep
                ZFail Keep
            }

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "GodRayMarchingCore.hlsl"
                        
            #pragma vertex Vert
            #pragma fragment FragLow

            ENDHLSL
        }
    }
    FallBack "Diffuse"
}