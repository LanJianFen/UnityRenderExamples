Shader "Basic Example/Basic04 Depth/Silhouette Depth Normal"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1, 1, 1, 1)
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
            Tags
            {
                "LightMode" = "SRPDefaultUnlit"
            }

            ZWrite On
            ZTest On

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #pragma vertex vertex_shader
            #pragma  fragment  fragment_shader

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
                v2f o = (v2f)0;
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

        //DepthOnly Pass : 有这个Pass，这个Material就会写入深度, 别的 shader 就可以在 CameraDepthTexture里用了
        Pass
        {
            Tags
            {
                "LightMode" = "DepthOnly"
            }

            ZWrite On
            ColorMask R

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #pragma vertex depth_only_vertex_shader
            #pragma  fragment  depth_only_fragment_shader

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
            };

            v2f depth_only_vertex_shader(Attributes i)
            {
                v2f o = (v2f)0;
                o.positionCS = TransformObjectToHClip(i.positionOS.xyz);
                return o;
            }

            float depth_only_fragment_shader(v2f i) : SV_TARGET
            {
                return i.positionCS.z;
            }
            ENDHLSL
        }

        // DepthNormalsPass
        Pass
        {
            Tags
            {
                "LightMode" = "DepthNormals"
            }

            ZWrite On

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #pragma vertex depth_normals_vertex_shader
            #pragma  fragment  depth_normals_fragment_shader

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS : TEXCOORD0;
            };

            v2f depth_normals_vertex_shader(Attributes i)
            {
                v2f o = (v2f)0;
                o.positionCS = TransformObjectToHClip(i.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(i.normalOS); // 第二个参数可以传true，来normalize
                o.normalWS = NormalizeNormalPerVertex(normalWS);
                return o;
            }

            float4 depth_normals_fragment_shader(v2f i) : SV_TARGET
            {
                float3 normalWS = NormalizeNormalPerPixel(i.normalWS);
                return float4(normalWS, 0.0);
            }
            ENDHLSL
        }
    }
}