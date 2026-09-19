Shader "Common/Upsample"
{
    Properties
    {
        [HideInInspector] _MainTex ("Source Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        Cull Off
        ZWrite Off
        ZTest Always
        Blend One One

        Pass
        {
            Name "Epic God Ray Upsample"
            HLSLPROGRAM
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "UpsampleCore.hlsl"

            #pragma vertex Vert
            #pragma fragment FragEpic
            ENDHLSL
        }

        Pass
        {
            Name "Medium God Ray Upsample"
            HLSLPROGRAM
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "UpsampleCore.hlsl"

            #pragma vertex Vert
            #pragma fragment FragMedium
            ENDHLSL
        }

        Pass
        {
            Name "Low God Ray Upsample"
            HLSLPROGRAM
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "UpsampleCore.hlsl"

            #pragma vertex Vert
            #pragma fragment FragLow
            ENDHLSL
        }

        Pass
        {
            Name "God Ray DepthDownsample"
            Cull Off 
            ZWrite On
            ZTest Always 
            ColorMask 0
            Stencil
            {
                Ref 0
                Comp Always
                Pass Replace
            }
            HLSLPROGRAM
            #pragma vertex VertDepth
            #pragma fragment FragDepth
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            
            struct Attributes { uint vertexID : SV_VertexID; };
            struct Varyings   { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };
            
            Varyings VertDepth(Attributes i)
            {
                Varyings o = (Varyings)0;
                o.positionCS = GetFullScreenTriangleVertexPosition(i.vertexID);
                o.uv = GetFullScreenTriangleTexCoord(i.vertexID);
                return o;
            }
            
            void FragDepth(Varyings i, out float outDepth : SV_Depth)
            {
                outDepth = SampleSceneDepth(i.uv);
            }
            ENDHLSL
        }
    }


}