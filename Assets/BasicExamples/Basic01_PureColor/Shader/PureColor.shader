Shader "Basic Example/Basic01 Pure Color/Pure Color"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1, 1, 1, 1)
    }
    
    SubShader
    {
        Tags {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }
        
        Pass
        {
            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #pragma vertex vertex_shader
            #pragma  fragment  fragment_shader
            
            float4 _BaseColor;

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct  v2f
            {
                float4 positionCS : SV_POSITION;
            };

            v2f vertex_shader(Attributes v)
            {
                v2f o = (v2f) 0;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                return o;
            }

            float4 fragment_shader(v2f i) : SV_TARGET
            {
                return _BaseColor;
            }
            
            ENDHLSL
        }
    }
}
