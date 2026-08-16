Shader "Advance Examples/SSS/Separable Screen SSS"
{
    Properties
    {
        [Header(Base Emission)]
        [Space(5)]
        _AlbedoMap ("Albedo Map", 2D) = "white" {}
        _AlbedoColor ("Albedo Color", Color) = (1.0, 1.0, 1.0, 1.0)
        [Header(Base Normal)]
        [Space(5)]
        _NormalMap("Normal Map", 2D) = "bump"{} //normal map 默认必须是 "bump" (Unity 内置平面法线)
        [Header(Surface Detail)]
        [Space(5)]
        _DetailMap("Detail Map", 2D) = "bump"{}
        // _Metallic ("Metallic", Range(0, 1)) = 0.0
        _Roughness ("Roughness", Range(0, 1)) = 0.5
        _Specular("Specular", Range(0, 1)) = 0.5
        _DepthBias("Depth Bias", Float) = 0.5
    }

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
                "LightMode" = "Separable Subsurface Scattering Direct Diffuse"
            }

            Stencil
            {
                Ref 2
                Comp Always // 永远通过
                Pass Replace // 画到哪里，就把哪里的模板值替换成 2
            }

            HLSLPROGRAM
            #pragma vertex vertShader
            #pragma fragment fragShader

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            #include  "../../../Common/Shaders/Math.hlsl"
            #include  "../../../Common/Shaders/CustomBrdf.hlsl"

            struct Attributes
            {
                float4 position_os : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal_os : NORMAL;
                float4 tangent_os : TANGENT;
            };

            struct Varings
            {
                float4 position_cs : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 position_ws : TEXCOORD1;
                float3 normal_ws : TEXCOORD2;
                float4 tangent_ws : TEXCOORD3; // .w = bitangent sign  
                float4 shadow_coord : TEXCOORD4;
            };


            TEXTURE2D(_AlbedoMap);
            TEXTURE2D(_NormalMap);
            TEXTURE2D(_DetailMap);

            SAMPLER(sampler_AlbedoMap);
            SAMPLER(sampler_NormalMap);
            SAMPLER(sampler_DetailMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _AlbedoColor;
                float _Roughness;
                float _Specular;
            CBUFFER_END

            Varings vertShader(Attributes i)
            {
                Varings o = (Varings)0;
                VertexPositionInputs posInputs = GetVertexPositionInputs(i.position_os.xyz);
                VertexNormalInputs nrmInputs = GetVertexNormalInputs(i.normal_os, i.tangent_os);
                o.position_ws = posInputs.positionWS;
                o.normal_ws = nrmInputs.normalWS;
                o.tangent_ws = float4(TransformObjectToWorldDir(i.tangent_os.xyz), i.tangent_os.w);
                o.uv = i.uv;
                o.shadow_coord = GetShadowCoord(posInputs);
                o.position_cs = posInputs.positionCS;
                return o;
            }

            half4 fragShader(Varings i) : SV_Target
            {
                float3 albedo = SAMPLE_TEXTURE2D(_AlbedoMap, sampler_AlbedoMap, i.uv).rgb;

                //half3 nWS = SampleWorldNormal(i.uv, normalize(i.normal_ws), i.tangent_ws);
                float3 normal_ts = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv));
                float3 bitangent_ws = cross(i.normal_ws, i.tangent_ws.xyz) * i.tangent_ws.w * GetOddNegativeScale();
                float3x3 tbn = float3x3(i.tangent_ws.xyz, bitangent_ws, i.normal_ws);
                half3 final_normal_ws = normalize(mul(normal_ts, tbn));

                // Main light irradiance: NdotL * lightColor / PI (no albedo)  
                Light mainLight = GetMainLight(i.shadow_coord);
                half attenuation = mainLight.shadowAttenuation * mainLight.distanceAttenuation;

                half NdotL = saturate(dot(final_normal_ws, mainLight.direction));
                half3 direct_diffuse_irradiance_without_albedo =  mainLight.color * NdotL; // 不含 radiance 的漫反射

                half3 sh_ambient = SampleSH(final_normal_ws);

                // Combine: SH + mainLight, both attenuated by main-light shadow (mirrors 20308 line 1194-1208)  
                half3 sss_diffuse_irradiance_without_albedo = (direct_diffuse_irradiance_without_albedo + sh_ambient) *
                    attenuation;
                /*
                                // Additional lights irradiance (Forward+ cluster or classic per-object list). No albedo.  
                                #if defined(_ADDITIONAL_LIGHTS) || defined(_FORWARD_PLUS)
                                    uint addCount = GetAdditionalLightsCount();
                                    #if USE_FORWARD_PLUS
                                        InputData inputData = (InputData)0;
                                        inputData.positionWS = i.position_ws;
                                        inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.position_cs);
                                        LIGHT_LOOP_BEGIN(addCount)
                                            Light l = GetAdditionalLight(lightIndex, i.position_ws);
                                            half nl = saturate(dot(final_normal_ws, l.direction));
                                            half la = l.distanceAttenuation * l.shadowAttenuation;
                                            sss_diffuse_irradiance_without_albedo += l.color * nl * INV_PI * la;
                                        LIGHT_LOOP_END
                                    #else
                                        for (uint k = 0u; k < addCount; ++k)
                                        {
                                            Light l = GetAdditionalLight(k, i.position_ws);
                                            half nl = saturate(dot(final_normal_ws, l.direction));
                                            half la = l.distanceAttenuation * l.shadowAttenuation;
                                            sss_diffuse_irradiance_without_albedo += l.color * nl * INV_PI * la;
                                        }
                                    #endif
                                #endif
                */

                return half4(sss_diffuse_irradiance_without_albedo, 1.0h);
            }
            ENDHLSL
        }
        Pass
        {
            Tags
            {
                "LightMode" = "Separable Subsurface Scattering Final Blend"
            }

            ZWrite Off
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vertShader
            #pragma fragment fragShader

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include  "../../../Common/Shaders/Math.hlsl"
            #include  "../../../Common/Shaders/CustomBrdf.hlsl"

            struct Attributes
            {
                float4 position_os : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal_os : NORMAL;
                float4 tangent_os : TANGENT;
            };

            struct Varings
            {
                float4 position_cs : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 position_ws : TEXCOORD1;
                float3 normal_ws : TEXCOORD2;
                float4 tangent_ws : TEXCOORD3;
            };


            TEXTURE2D(_AlbedoMap);
            TEXTURE2D(_NormalMap);
            TEXTURE2D(_DetailMap);

            SAMPLER(sampler_AlbedoMap);
            SAMPLER(sampler_NormalMap);
            SAMPLER(sampler_DetailMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _AlbedoColor;
                //float _Metallic;
                float _Roughness;
                float _Specular;
            CBUFFER_END

            TEXTURE2D(_SeparableSubsurfaceScatteringRT);
            SAMPLER(sampler_SeparableSubsurfaceScatteringRT);

            Varings vertShader(Attributes i)
            {
                Varings o = (Varings)0;
                o.uv = i.uv;
                o.position_cs = TransformObjectToHClip(i.position_os.xyz);
                o.position_ws = TransformObjectToWorld(i.position_os.xyz);
                o.normal_ws = TransformObjectToWorldNormal(i.normal_os, true);
                o.tangent_ws = float4(TransformObjectToWorldDir(i.tangent_os.xyz), i.tangent_os.w);
                return o;
            }


            half4 fragShader(Varings i) : SV_Target
            {
                float4 albedo = SAMPLE_TEXTURE2D(_AlbedoMap, sampler_AlbedoMap, i.uv) * _AlbedoColor;
                // 法线旋转叠加：旋转到在宏观法线方向，叠加更细节的法线。这个要在 宏观法线的起点 Tangent Space 才能叠加上去
                float3 normal_ts = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv));
                float3 detail_normal_ts = UnpackNormal(SAMPLE_TEXTURE2D(_DetailMap, sampler_DetailMap, i.uv));
                float3 final_normal_ts = BlendNormalRNMCustom(normal_ts, detail_normal_ts);

                // 构建 TBN 矩阵
                float3 bitangent_ws = cross(i.normal_ws, i.tangent_ws.xyz) * i.tangent_ws.w * GetOddNegativeScale();
                float3x3 tbn = float3x3(i.tangent_ws.xyz, bitangent_ws, i.normal_ws);
                // 把叠加 detail 法线后在最终法线 转移到 ws，这里用的是 final\_normal\_ts 右乘 tbn 的转置
                float3 final_normal_ws = normalize(mul(final_normal_ts, tbn));

                Light main_light = GetMainLight();
                float3 L = normalize(main_light.direction);
                float3 V = normalize(_WorldSpaceCameraPos - i.position_ws);
                float3 H = normalize(L + V);

                float NdotH = saturate(dot(final_normal_ws, H));
                float NdotV = saturate(dot(final_normal_ws, V));
                float NdotL = saturate(dot(final_normal_ws, L));
                float VdotH = saturate(dot(V, H));

                // Specular
                // 基础反射率 F0 (非金属为 0.04，金属为 Albedo)
                float3 F0 = float3(0.08, 0.08, 0.08) * _Specular;

                float3 F = F_Schlick_Custom(VdotH, F0);
                float G = G_SmithJointGGX_Custom(NdotL, NdotV, _Roughness * _Roughness);
                float D = D_GGX_Custom(NdotH, _Roughness * _Roughness);

                float3 ggx_BRDF = D * G * F / max(4.0f * NdotL * NdotV, 0.000001f);;
                float3 direct_specular_radiance = ggx_BRDF * main_light.color * NdotL * PI;
                float3 IBL_ambient = IBL_SpecularCustom(final_normal_ws, V, NdotV, F0, _Roughness);
                // ==== IBL 间接高光 (掠射角 → 边缘发光) ====
                float3 specular_radiance = direct_specular_radiance + IBL_ambient;

                // ==== SH 环境光 ====
                float3 kD = 1.0f - F;
                float3 sh_ambient = albedo.rgb * SampleSH(final_normal_ws) * kD;

                float3 Ft_out = 1.0f - F_Schlick_Custom(NdotV, F0);
                float2 ss_uv = i.position_cs.xy / _ScreenParams.xy;
                float3 sss_radiance = Ft_out * SAMPLE_TEXTURE2D(_SeparableSubsurfaceScatteringRT,
                sampler_SeparableSubsurfaceScatteringRT, ss_uv).rgb;

                // 测试一下 普通 PBR 有没有错误
                //float3 kD = 1.0f - F;
                //float3 direct_diffuse_radiance = albedo.rgb * main_light.color * NdotL; // 普通的 PBR
                //float3 diffuse_radiance = (direct_diffuse_radiance + sh_ambient) * kD;

                return half4(specular_radiance + albedo.rgb * sss_radiance, 1.0f);
            }
            ENDHLSL

        }
    }
}