Shader "Basic Example/Basic03 Transparent/Transparent"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        _BaseTexture("Base Texture", 2D) = "white" {}
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend("Source Blend Mode", Int) = 5
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend("Destination Blend Mode", Int) = 10
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
        }

        Pass
        {
            // SrcColor ：此像素背景的颜色
            // DstColor ：此像素fragment的颜色
            // Blend 这个集合有10种选项，这里举例两个
            
            // _SrcBlend = SrcAlpha, _DstBlend = DstAlpha
            // 最终输出的颜色是 SrcColor.rgb * SrcColor. a + DstColor.rgb * DstColor.a
            
            // _SrcBlend =  SrcColor, _DstBlend =  DstColor
            // 最终输出的颜色是 SrcColor.rgb * SrcColor. rgb + DstColor.rgb * DstColor.rgb
            
            Blend [_SrcBlend] [_DstBlend]

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #pragma vertex vertex_shader
            #pragma fragment fragment_shader
            
            // 用同一个shader就能进行SRP Batches合批
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseTexture_ST; //Tilling存储在xy，Offset存储在zw
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
                return textureColor * _BaseColor;
            }
            ENDHLSL
        }
    }
}