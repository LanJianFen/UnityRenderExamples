Shader "Basic Example/Basic04 Depth/Silhouette Step"
{
    Properties
    {
        _BackgroundColor("BackGround Color", Color) = (1, 1, 1, 1)
        _BaseTexture("Base Texture", 2D) = "white" {}
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
            ZWrite On
            ZTest LEqual
            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #pragma vertex vertex_shader
            #pragma fragment fragment_shader

            // 用同一个shader就能进行SRP Batches合批
            CBUFFER_START(UnityPerMaterial)
                float4 _BackgroundColor;
                float4 _BaseTexture_ST; // Tilling存储在xy，Offset存储在zw
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
                float4 positionSS : TEXCOORD1;
                float2 uv : TEXCOORD0;
            };

            v2f vertex_shader(Attributes v)
            {
                v2f o = (v2f)0;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                // 直接用Clip Space的坐标计算屏幕空间坐标，而不是用NDC空间的坐标，因为中间涉及到透视矫正
                o.positionSS = ComputeScreenPos(o.positionCS);
                //TRANSFORM_TEX：计算Tilling和Offset之后的uv
                o.uv = TRANSFORM_TEX(v.uv, _BaseTexture);
                return o;
            }

            float4 fragment_shader(v2f i) : SV_TARGET
            {
                float4 textureColor = SAMPLE_TEXTURE2D(_BaseTexture, sampler_BaseTexture, i.uv);
                // 计算屏幕空间坐标，采样CameraTextureDepth的深度
                float2 screenUV = i.positionSS.xy / i.positionSS.w;
                float rawDepth = SampleSceneDepth(screenUV);
                // MVP变换中，depth不再是线性的，但是可以变换成线性的
                float linearDepth = Linear01Depth(rawDepth, _ZBufferParams);
                // 后面是否有物体
                int hasDepth = step(rawDepth, 0);

                return lerp(_BackgroundColor, textureColor, hasDepth);
                // return _BackgroundColor * hasDepth +  textureColor* (1 - hasDepth);
            }
            ENDHLSL
        }
    }
}