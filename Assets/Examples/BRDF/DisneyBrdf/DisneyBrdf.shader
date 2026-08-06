Shader "Custom/Disney BRDF"
{
    Properties
    {
        _AlbedoMap("Albedo Map", 2D) = "white" {}
        _AlbedoTint("Albedo Tint", Color) = (1.0, 1.0, 1.0, 1.0)
        _Roughness ("Roughness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0
        _Specular ("Specular", Range(0,1)) = 0.5
        _SpecularTint("Specular Tint", Range(0,1)) = 0.0
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
            "RenderPipeline" = "UniversalPipeline"
        }

        ZWrite On
        Cull Back
        Pass
        {
            HLSLPROGRAM
            #pragma vertex vertexShader
            #pragma fragment fragmentShader

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include  "DisneyBrdfSpecular.hlsl"
            
            struct Attributes
            {
                float4 position_os : POSITION;
                float3 normal_os  : NORMAL;
                float4 tangent_os : TANGENT;
                float2 uv            : TEXCOORD0;
            };

            struct Varings
            {
                float4 position_cs : SV_POSITION;
                float2 uv            : TEXCOORD0;
                float3 position_ws: TEXCOORD1;
                half3 normal_ws  : TEXCOORD2;
                half4 tangent_ws : TEXCOORD3;
            };

            CBUFFER_START(UnityPerMaterial)
                half4 _AlbedoTint;
                half _Roughness;
                half _Metallic;
                half _Specular;
                half _SpecularTint;
            CBUFFER_END

            TEXTURE2D(_AlbedoMap);  SAMPLER(sampler_AlbedoMap);
            
            Varings vertexShader(Attributes i)
            {
                Varings o = (Varings) 0;
                o.position_cs = TransformObjectToHClip(i.position_os.xyz);
                o.position_ws = TransformObjectToWorld(i.position_os.xyz);
                o.normal_ws = TransformObjectToWorldNormal(i.normal_os);
                o.tangent_ws = float4(TransformObjectToWorldDir(i.tangent_os.xyz), i.tangent_os.w);
                o.uv = i.uv;
                return o;
            }

            half4 fragmentShader(Varings i) : SV_TARGET
            {
                half3 albedo = SAMPLE_TEXTURE2D(_AlbedoMap, sampler_AlbedoMap, i.uv).rgb * _AlbedoTint;
                // 构建 TBN 矩阵
                //half3 tangent_ws = normalize(i.tangent_ws.xyz);
                //half3 bitangent_ws = normalize(cross(i.normal_ws, i.tangent_ws.xyz) * i.tangent_ws.w * GetOddNegativeScale());
                half3 normal_ws = normalize(i.normal_ws);
                //half3x3 tbn = half3x3(tangent_ws, bitangent_ws, normal_ws);
                
                Light main_light = GetMainLight();
                half3 light_color = main_light.color;
                
                half3 N = normal_ws;
                half3 L = main_light.direction;
                half3 V = normalize(GetCameraPositionWS() - i.position_ws);
                half3 H = normalize(L + V);

                half NdotL = saturate(dot(N, L));
                half NdotV = saturate(dot(N, V));
                half NdotH = saturate(dot(N, H));
                half VdotH = saturate(dot(V, H));
                
                half3 specular_brdf = D_GGX_Disney(_Roughness, NdotH) * F_Schlick_Disney(albedo, _Specular, _SpecularTint, _Metallic, VdotH);
                half3 main_specular = specular_brdf * light_color * NdotL;

                half3 radiance = main_specular;

                return half4(radiance, 1);
            }
            ENDHLSL
        }
    }
    FallBack "Diffuse"
}