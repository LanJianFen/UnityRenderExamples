Shader "Advance Examples/SSS/Deferred MonteCarlo SSS Lighting"
{
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityGBuffer.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

        #define kMaterialFlagSkin 16

        half _MonteCarloBaseColorScatteringWeight;

        TEXTURE2D_X_HALF(_GBuffer0);
        TEXTURE2D_X_HALF(_GBuffer1);
        TEXTURE2D_X_HALF(_GBuffer2);

        struct Varyings { float4 positionCS : SV_POSITION; };

        Varyings Vert(uint vertexID : SV_VertexID)
        {
            Varyings o;
            o.positionCS = GetFullScreenTriangleVertexPosition(vertexID);
            return o;
        }

        bool IsSkin(half4 gb0, out uint flags)
        {
            flags = UnpackMaterialFlags(gb0.a);
            return (flags & kMaterialFlagSkin) != 0;
        }
        ENDHLSL

        // Pass 0：皮肤直接光（只算主光）
        Pass
        {
            Name "Deferred Monte Carlo Subsurface Lighting"
            HLSLPROGRAM
            #pragma vertex   Vert
            #pragma fragment Frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Output
            {
                half4 Diffuse  : SV_Target0;   // 白色反照率的漫反射，a = 皮肤遮罩
                half4 Specular : SV_Target1;
            };

            Output Frag(Varyings i)
            {
                Output o;
                uint2 coord = uint2(i.positionCS.xy);
                half4 gb0 = LOAD_TEXTURE2D_X(_GBuffer0, coord);
                uint flags;
                if (!IsSkin(gb0, flags)) discard;

                half4 gb1 = LOAD_TEXTURE2D_X(_GBuffer1, coord);
                half4 gb2 = LOAD_TEXTURE2D_X(_GBuffer2, coord);

                // 重建世界坐标
                float  depth = LoadSceneDepth(coord);
                float2 uv    = i.positionCS.xy / _ScaledScreenParams.xy;
                float3 posWS = ComputeWorldSpacePosition(uv, depth, UNITY_MATRIX_I_VP);

                half3 N = normalize(UnpackNormal(gb2.xyz));
                half3 V = GetWorldSpaceNormalizeViewDir(posWS);
                BRDFData brdf = BRDFDataFromGbuffer(gb0, gb1, gb2);

                // 主光：不要用 GetMainLight()
                // 它会读 unity_LightData（逐物体常量），全屏 Pass 里没有这个值，可能是 0
                half3 L = _MainLightPosition.xyz;
                half shadow = MainLightShadow(TransformWorldToShadowCoord(posWS), posWS,
                                              half4(1, 1, 1, 1), _MainLightOcclusionProbes);
                if (flags & kMaterialFlagReceiveShadowsOff) shadow = 1.0h;

                half  NoL      = saturate(dot(N, L));
                half3 radiance = _MainLightColor.rgb * (shadow * NoL);

                
                o.Diffuse = half4(radiance * pow(gb0.rgb, _MonteCarloBaseColorScatteringWeight), 1.0h) ;   // URP 的直接漫反射不除以 π，和 StencilDeferred 一致

                half3 spec = 0;
                if ((flags & kMaterialFlagSpecularHighlightsOff) == 0)
                    spec = brdf.specular * DirectBRDFSpecular(brdf, N, L, V) * radiance;
                o.Specular = half4(spec, 1.0h);
                return o;
            }
            ENDHLSL
        }

        // Pass 1：合成，叠加到相机颜色
        Pass
        {
            Name "Deferred Monte Carlo Subsurface Composite"
            Blend One One
            HLSLPROGRAM
            #pragma vertex   Vert
            #pragma fragment Frag

            TEXTURE2D_X(_MonteCarloSubsurfaceScatteredRt);
            TEXTURE2D_X(_MonteCarloSubsurfaceSpecularRt);

            half4 Frag(Varyings i) : SV_Target
            {
                uint2 coord = uint2(i.positionCS.xy);
                half4 gb0 = LOAD_TEXTURE2D_X(_GBuffer0, coord);
                uint flags;
                if (!IsSkin(gb0, flags)) discard;

                half3 scattered = LOAD_TEXTURE2D_X(_MonteCarloSubsurfaceScatteredRt, coord).rgb;
                half3 spec      = LOAD_TEXTURE2D_X(_MonteCarloSubsurfaceSpecularRt,  coord).rgb;
                // 反照率在散射之后才乘（Post-Scatter），毛孔细节不会被模糊掉
                return half4(scattered * pow(gb0.rgb, 1.0h - _MonteCarloBaseColorScatteringWeight) + spec, 0);
            }
            ENDHLSL
        }
    }
}