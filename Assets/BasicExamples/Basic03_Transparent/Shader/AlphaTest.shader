Shader "Basic Example/Basic03 Transparent/Alpha Test"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        _BaseTexture("Base Texture", 2D) = "white" {}
        _AlphaThreshold("Alpha Threshold", Range(0, 1)) = 1
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        Pass
        {
            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #pragma vertex vertex_shader
            #pragma fragment fragment_shader
            
            // 用同一个shader就能进行SRP Batches合批
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseTexture_ST; // Tilling存储在xy，Offset存储在zw
                float _AlphaThreshold;   // alpha通道低于这个值的就不显示
            CBUFFER_END

            TEXTURE2D(_BaseTexture);
            SAMPLER(sampler_BaseTexture); //采样规则在Texture导入的时候设置的Wrap Mode,Filter Mode
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            v2f vertex_shader(Attributes v)
            {
                v2f o = (v2f) 0;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                //TRANSFORM_TEX：计算Tilling和Offset之后的uv
                o.uv = TRANSFORM_TEX(v.uv, _BaseTexture);
                return o;
            }

            float4 fragment_shader(v2f i) : SV_TARGET
            {
                float4 textureColor = SAMPLE_TEXTURE2D(_BaseTexture, sampler_BaseTexture, i.uv);

                if (textureColor.a < _AlphaThreshold)
                {
                    discard;
                }
                
                return textureColor * _BaseColor;
            }
            ENDHLSL
        }
    }
}