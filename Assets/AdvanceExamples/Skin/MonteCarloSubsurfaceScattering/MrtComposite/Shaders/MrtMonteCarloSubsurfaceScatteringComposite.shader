Shader "Advance Examples/SSS/MonteCarlo Forward SSS Composite"
{
    Properties {}
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
                "LightMode" = "Monte Carlo Subsurface Composite"
            }

            //Stencil
            //{
            //    Ref 1 // 拿着暗号 1 去对比
            //    Comp Equal // 只有底层值等于 1 时，才允许执行这个全屏像素！
            //}

            ZWrite Off
            ZTest Always // 无视遮挡，强行覆盖全屏
            Cull off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attibutes
            {
                uint vertex_id : SV_VertexID;
            };

            struct Varings
            {
                float2 uv : TEXCOORD0;
                float4 position_cs : SV_POSITION;
            };

            // 要被合成的 3 张 Rt
            TEXTURE2D(_MonteCarloSubsurfaceScatteringRT);
            TEXTURE2D(_MonteCarloSubsurfaceSpecularRT);
            TEXTURE2D(_MonteCarloSubsurfaceAlbedoRT);

            Varings vert(Attibutes i)
            {
                Varings o;
                o.position_cs = GetFullScreenTriangleVertexPosition(i.vertex_id);
                o.uv = GetFullScreenTriangleTexCoord(i.vertex_id);
                return o;
            }

            half4 frag(Varings i) : SV_Target
            {
                half3 subsurface = SAMPLE_TEXTURE2D(_MonteCarloSubsurfaceScatteringRT, sampler_PointClamp, i.uv).rgb;
                half3 specular = SAMPLE_TEXTURE2D(_MonteCarloSubsurfaceSpecularRT, sampler_PointClamp, i.uv);
                half3 albedo = SAMPLE_TEXTURE2D(_MonteCarloSubsurfaceAlbedoRT, sampler_PointClamp, i.uv);
                
                half3 color = subsurface * albedo + specular;
                return half4(color, 1.0h);
            }
            ENDHLSL
        }
    }
}