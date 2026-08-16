Shader "Advance Examples/SSS/Separable Screen SSS Core"
{
    Properties
    {
        [HideInInspector] _GaussianKernelNum("Gaussian Kernel Num", Int) = 25
        [HideInInspector] _SeparableSurfaceScale("Separable Surface Scale", Float) = 3.0
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Tags
            {
                "LightMode" = "Separable Subsurface Scattering X Axis"
            }

            Stencil
            {
                Ref 2 // 拿着暗号 1 去对比
                Comp Equal // 只有底层值等于 1 时，才允许执行这个全屏像素！
            }
            ZWrite Off
            ZTest Always
            Cull Off
            
            HLSLPROGRAM
            #pragma vertex   Vert
            #pragma fragment Frag
            #pragma target   3.5

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            TEXTURE2D(_SeparableSubsurfaceDirectDiffuseRT);
            SAMPLER(sampler_SeparableSubsurfaceDirectDiffuseRT);
            TEXTURE2D(_SSSDepth);
            SAMPLER(sampler_SSSDepth);

            #define SSS_KERNEL_MAX 25
            
            float4 _GaussianKernel[SSS_KERNEL_MAX];
            CBUFFER_START(UnityPerMaterial)
                int _GaussianKernelNum; 
                float _SeparableSurfaceScale; // maps to _73._child1  
            CBUFFER_END

            #define _MM_PER_METER 1000.0f
            #define _METER_PER_MM 0.001f
            #define  U_DIR float2(1.0f, 0.0f)
            #define  V_DIR float2(0.0f, 1.0f)
            
            struct Attributes
            {
                uint vertex_id : SV_VertexID;
            };

            struct Varyings
            {
                float4 position_cs : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings Vert(Attributes i)
            {
                Varyings o = (Varyings)0;
                o.position_cs = GetFullScreenTriangleVertexPosition(i.vertex_id);
                o.uv = GetFullScreenTriangleTexCoord(i.vertex_id);
                return o;
            }
            
            half4 Frag(Varyings i) : SV_Target
            {
                //half4 centerAll = SAMPLE_TEXTURE2D(_SeparableSubsurfaceDirectDiffuseRT, sampler_SeparableSubsurfaceDirectDiffuseRT, uv);
                // Diffuse Pass 算出来的 Diffuse 贴图
                half3 center_irradiance = SAMPLE_TEXTURE2D(_SeparableSubsurfaceDirectDiffuseRT, sampler_SeparableSubsurfaceDirectDiffuseRT, i.uv).rgb;
                //half centerMaskRT = centerAll.a; 

                //half outputAlpha = centerMaskRT; // pass 1-mask through to next stage (Y blur)  

                // ----- Depth setup at center -----
                float center_01_depth = SampleSceneDepth(i.uv);
                float center_real_depth = LinearEyeDepth(center_01_depth, _ZBufferParams);

                // Jimenez per-pixel stride (in UV space) and depth-diff scale
                float fov_scale = unity_CameraProjection[1][1]; 
                float meter_per_uv = center_real_depth / fov_scale;
                float uv_per_mm = rcp(max(meter_per_uv,1e-6) * _MM_PER_METER);
                float step = uv_per_mm * _SeparableSurfaceScale;
                
                //float depth_cmp = strength * 1701.3845;
                float depth_cmp = _SeparableSurfaceScale * fov_scale * 300.0f;
                
                // ----- Accumulator seeded with weighted center -----
                // 高斯核的 RGB 通道记录的是每个采样点的权重 （在这个采样点附近高斯函数积分的面积）
                half3 sssss_irradiance = center_irradiance * _GaussianKernel[0].rgb;

                // ----- 25-tap loop -----  
                [loop]
                for (int u = 1; u < _GaussianKernelNum; ++u)
                {
                    // 高斯核的 w 记录了采样点的分布
                    float2 sample_uv = i.uv + U_DIR * _GaussianKernel[u].w * step;

                   // half3 sample = sampleAll.rgb;
                    half3 sample_irradiance = SAMPLE_TEXTURE2D(_SeparableSubsurfaceDirectDiffuseRT, sampler_SeparableSubsurfaceDirectDiffuseRT, sample_uv).rgb;;
                    // // half sampleMaskRT = sampleAll.a;
                    // // half sampleMask   = 1.0h - sampleMaskRT;   // actual source.g: 0=SSS, 1=NOT SSS
                    
                    //float rawDepthS = SAMPLE_TEXTURE2D(_SSSDepth, sampler_SSSDepth, sampleUV).r;
                    //float linDepthS = LinearizeReciprocal(rawDepthS);
                    float sample_01_depth = SampleSceneDepth(sample_uv);
                    float sample_real_depth = LinearEyeDepth(sample_01_depth, _ZBufferParams);
                    
                    // Depth-aware fallback (still active): samples across depth discontinuities  
                    // are rejected in favor of the center value.
                    //half depthWeight = saturate(depthCmp * abs(linDepthC - linDepthS));  
                    //half3 modified = lerp(sample, reference, depthWeight);
                    half modified_depth_diff = saturate(depth_cmp * abs(sample_real_depth - center_real_depth));
                    half3 irradiance_make_up = lerp(sample_irradiance, center_irradiance, 0.0f);
                    // MASK TODO: while mask is disabled, tap = modified (no mask-based blend).  
                    // Original (mask-aware): half3 tap = lerp(modified, reference, sampleMask);
                    //half3 tap = modified;  

                    sssss_irradiance += _GaussianKernel[u].rgb * irradiance_make_up;
                }

                return half4(sssss_irradiance, 1.0f);
            }
            ENDHLSL
        }
        Pass
        {
            Tags
            {
                "LightMode" = "Separable Subsurface Scattering Y Axis"
            }

            Stencil
            {
                Ref 2 // 拿着暗号 1 去对比
                Comp Equal // 只有底层值等于 1 时，才允许执行这个全屏像素！
            }
            ZWrite Off
            ZTest Always
            Cull Off
            
            HLSLPROGRAM
            #pragma vertex   Vert
            #pragma fragment Frag
            #pragma target   3.5

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            TEXTURE2D(_SeparableSubsurfaceScatteringXAxisRT);
            SAMPLER(sampler_SeparableSubsurfaceScatteringXAxisRT);
            TEXTURE2D(_SSSDepth);
            SAMPLER(sampler_SSSDepth);

            #define SSS_KERNEL_MAX 25

            float4 _GaussianKernel[SSS_KERNEL_MAX];
            CBUFFER_START(UnityPerMaterial)
                int _GaussianKernelNum; 
                float _SeparableSurfaceScale; // maps to _73._child1  
            CBUFFER_END

            #define _MM_PER_METER 1000.0f
            #define _METER_PER_MM 0.001f
            #define  U_DIR float2(1.0f, 0.0f)
            #define  V_DIR float2(0.0f, 1.0f)
            
            struct Attributes
            {
                uint vertex_id : SV_VertexID;
            };

            struct Varyings
            {
                float4 position_cs : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings Vert(Attributes i)
            {
                Varyings o = (Varyings)0;
                o.position_cs = GetFullScreenTriangleVertexPosition(i.vertex_id);
                o.uv = GetFullScreenTriangleTexCoord(i.vertex_id);
                return o;
            }
            
            half4 Frag(Varyings i) : SV_Target
            {
                //half4 centerAll = SAMPLE_TEXTURE2D(_SeparableSubsurfaceDirectDiffuseRT, sampler_SeparableSubsurfaceDirectDiffuseRT, uv);
                // Diffuse Pass 算出来的 Diffuse 贴图
                half3 center_irradiance = SAMPLE_TEXTURE2D(_SeparableSubsurfaceScatteringXAxisRT, sampler_SeparableSubsurfaceScatteringXAxisRT, i.uv).rgb;
                //half centerMaskRT = centerAll.a; 

                //half outputAlpha = centerMaskRT; // pass 1-mask through to next stage (Y blur)  

                // ----- Depth setup at center -----
                float center_01_depth = SampleSceneDepth(i.uv);
                float center_real_depth = LinearEyeDepth(center_01_depth, _ZBufferParams);

                // Jimenez per-pixel stride (in UV space) and depth-diff scale
                float fov_scale = unity_CameraProjection[1][1]; 
                float meter_per_uv = center_real_depth / fov_scale;
                float uv_per_mm = rcp(max(meter_per_uv,1e-6) * _MM_PER_METER);
                float step = uv_per_mm * _SeparableSurfaceScale;
                
                //float depth_cmp = strength * 1701.3845;
                float depth_cmp = _SeparableSurfaceScale * fov_scale * 300.0f;
                
                // ----- Accumulator seeded with weighted center -----
                // 高斯核的 RGB 通道记录的是每个采样点的权重 （在这个采样点附近高斯函数积分的面积）
                half3 sssss_irradiance = center_irradiance * _GaussianKernel[0].rgb;

                // ----- 25-tap loop -----  
                [loop]
                for (int u = 1; u < _GaussianKernelNum; ++u)
                {
                    // 高斯核的 w 记录了采样点的分布
                    float2 sample_uv = i.uv + V_DIR * _GaussianKernel[u].w * step;

                   // half3 sample = sampleAll.rgb;
                    half3 sample_irradiance = SAMPLE_TEXTURE2D(_SeparableSubsurfaceScatteringXAxisRT, sampler_SeparableSubsurfaceScatteringXAxisRT, sample_uv).rgb;;
                    // // half sampleMaskRT = sampleAll.a;
                    // // half sampleMask   = 1.0h - sampleMaskRT;   // actual source.g: 0=SSS, 1=NOT SSS
                    
                    //float rawDepthS = SAMPLE_TEXTURE2D(_SSSDepth, sampler_SSSDepth, sampleUV).r;
                    //float linDepthS = LinearizeReciprocal(rawDepthS);
                    float sample_01_depth = SampleSceneDepth(sample_uv);
                    float sample_real_depth = LinearEyeDepth(sample_01_depth, _ZBufferParams);
                    
                    // Depth-aware fallback (still active): samples across depth discontinuities  
                    // are rejected in favor of the center value.
                    //half depthWeight = saturate(depthCmp * abs(linDepthC - linDepthS));  
                    //half3 modified = lerp(sample, reference, depthWeight);
                    half modified_depth_diff = saturate(depth_cmp * abs(sample_real_depth - center_real_depth));
                    half3 irradiance_make_up = lerp(sample_irradiance, center_irradiance, 0.0f);
                    // MASK TODO: while mask is disabled, tap = modified (no mask-based blend).  
                    // Original (mask-aware): half3 tap = lerp(modified, reference, sampleMask);
                    //half3 tap = modified;  

                    sssss_irradiance += _GaussianKernel[u].rgb * irradiance_make_up;
                }

                return half4(sssss_irradiance, 1.0f);
            }
            ENDHLSL
        }
    }

    FallBack Off
}