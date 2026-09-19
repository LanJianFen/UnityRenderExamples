Shader "Advance Examples/Fog/God Ray/God Ray Linear Depth"
{
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass  
        {  
            Name "Realtime GodRay Shadow"
            Cull Off   
            ZWrite On  
            ZTest [_ZTest]                          
            
            HLSLPROGRAM  
            #pragma vertex Vert  
            #pragma fragment Frag  
  
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"  
            
            struct Attributes  
            {  
                float4 position_os : POSITION;  
            };  
  
            struct Varyings  
            {  
                float4 position_cs : SV_POSITION;  
                float  depth_01    : TEXCOORD0;  
            };  
  
            float3 _GodRayCameraPosition;  
            float3 _GodRayCameraForward;  
            float  _GodRayCameraFarClip;  
              
            Varyings Vert(Attributes i)  
            {  
                Varyings o;  
                
                o.position_cs = TransformObjectToHClip(i.position_os.xyz);  
                float3 position_ws = TransformObjectToWorld(i.position_os.xyz);    

                float3 position_offset = position_ws - _GodRayCameraPosition;    
                o.depth_01 = dot(position_offset, _GodRayCameraForward) / _GodRayCameraFarClip;    
                  
                return o;  
            }  
  
            float Frag(Varyings i) : SV_TARGET  
            {  
                return i.depth_01;
            }  
            ENDHLSL  
        }  

        Pass
        {
            Name "PerspectiveDepthPrepass"
            Tags { "LightMode" = "GodRayDepthPrepass" }
            Cull Back
            ZWrite On
            
            ZTest LEqual 
            
            ColorMask 0 
            HLSLPROGRAM
            #pragma vertex VertDepth
            #pragma fragment FragDepth
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            struct Attributes
            {
                float4 position_os : POSITION;
            };
            struct Varyings
            {
                float4 position_cs : SV_POSITION;
            };
            Varyings VertDepth(Attributes i)
            {
                Varyings o;
                // 纯粹的 MVP 变换，底层硬件会自动把 Z/W 深度吸进你的 Depth RT 里！
                o.position_cs = TransformObjectToHClip(i.position_os.xyz);
                return o;
            }
            half4 FragDepth(Varyings i) : SV_TARGET
            {
                // 因为写了 ColorMask 0，这里的输出会被硬件直接无视，随便 return 即可
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "GodRay Cookie Mask Pass"
            Cull Off
            ZWrite On
            ZTest [_ZTest]   // 由 C# 端根据 SystemInfo.usesReversedZBuffer 设置

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 position_os : POSITION;
            };

            struct Varyings
            {
                float4 position_cs : SV_POSITION;
                float  depth_01   : TEXCOORD0;
            };

            Varyings Vert(Attributes i)
            {
                Varyings o;
                o.position_cs = TransformObjectToHClip(i.position_os.xyz);

                // 正交相机下 view space 的 z 与世界距离线性相关
                // Unity 相机看向 -z，所以 pos_vs.z 为负，取反得到正距离
                // 假设 nearClipPlane = 0；否则需减去 near 并除以 (far - near)
                float3 pos_ws = TransformObjectToWorld(i.position_os.xyz);
                float3 pos_vs = TransformWorldToView(pos_ws);
                o.depth_01 = -pos_vs.z / _ProjectionParams.z;

                return o;
            }

            float Frag(Varyings i) : SV_TARGET
            {
                return i.depth_01;
            }

            ENDHLSL
        }
    }
    FallBack "Diffuse"
}