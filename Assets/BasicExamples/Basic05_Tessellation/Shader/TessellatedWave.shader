Shader "Basic Example/Basic05 Tessellation/Tessellated Wave"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1,1,1,1)
        // _BaeTexture ("Base Texture", 2D) = "white" {}
        _WaveHeight ("Wave Height", Range(0,1)) = 0.25 // 波浪的高度
        _WaveSpeed ("Wave Speed", Range(0,1)) = 1 // 波浪的速度
        _TessellationAmount("Tessellation Amount", Range(1,64)) = 1 // 细分的最大数量
        _TessellationFadeStart("Tessellation Fade Start", Float) = 25 // 开始减少细分面的距离
        _TessellationFadeEnd("Tessellation Fade End", Float) = 50 // 减到原始网格的距离
    }
    SubShader
    {
        Pass
        {
            Tags
            {
                "RenderPipeline" = "UniversalPipeline"
                "RenderType"="Opaque"
                "Queue" = "Geometry"
            }

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #pragma vertex  vertex_shader
            #pragma fragment fragment_shader
            #pragma hull hull
            #pragma domain domain_shader

            // 用同一个shader就能进行SRP Batches合批
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float _WaveHeight;
                float _WaveSpeed;
                float _TessellationAmount;
                float _TessellationFadeStart;
                float _TessellationFadeEnd;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                //float2 uv : TEXCOORD0;
            };

            // tessellation 的控制点，像贝塞尔曲线一样控制面的起伏
            struct tessControlPoint
            {
                float3 positionWS : INTERNALTESSPOS;
                //float uv : TEXCOORD0;
            };

            // 一个 patch 边缘切割数和内部切割数
            struct tessFactor
            {
                float edge[3] : SV_TessFactor;
                float inside : SV_InsideTessFactor;
            };

            struct t2f
            {
                float4 positionCS : SV_POSITION;
            };

            // 整体的思路
            // 1. vs 负责把 OS 坐标转换成 WS 坐标交给 hull
            // 2. hull 负责根据 WS 坐标和相机的距离计算内部切割数和边缘切割数
            // 3. domain 在 WS 负责原来 vs 的工作，在取得新增的顶点以后，计算波浪中顶点的位移
            // 4. fs 负责原来的工作
            tessControlPoint vertex_shader(Attributes i)
            {
                tessControlPoint o = (tessControlPoint)0;
                o.positionWS = TransformObjectToWorld(i.positionOS.xyz);
                return o;
            }

            // hull 通过一系列的 Attibutes 来指定运行时的规则
            [domain("tri")] // 三角形patch
            [outputcontrolpoints(3)] // 每个面输出3个控制点，控制起伏
            [outputtopology("triangle_cw")] // 顶点顺时针分布，逆时针是ccw
            [partitioning("integer")] // 算出小数细分级别的时候取整
            [patchconstantfunc("patchConstantFunc")] // 指定一个 patch 边缘切割数和内部切割数的函数
            tessControlPoint hull(InputPatch<tessControlPoint, 3> patch, uint id : SV_OutputControlPointID)
            {
                // hull 是 hull shader 的一部分，启动多个线程组去处理一个patch，返回线程组的id
                return patch[id];
            }

            tessFactor patchConstantFunc(InputPatch<tessControlPoint, 3> patch)
            {
                tessFactor f = (tessFactor)0;
                // 根据距离计算 patch 的边缘切割数和内部切割数，这里全是在 World Space 下进行的
                float3 triPos0 = patch[0].positionWS;
                float3 triPos1 = patch[1].positionWS;
                float3 triPos2 = patch[2].positionWS;

                // 每条边的中点
                float3 edgeMidPos0 = 0.5 * (triPos1 + triPos2);
                float3 edgeMidPos1 = 0.5 * (triPos0 + triPos2);
                float3 edgeMidPos2 = 0.5 * (triPos0 + triPos1);

                // 相机世界坐标
                float3 cameraWS = _WorldSpaceCameraPos;

                // 每个中点和相机的距离
                float distance0 = distance(edgeMidPos0, cameraWS);
                float distance1 = distance(edgeMidPos1, cameraWS);
                float distance2 = distance(edgeMidPos2, cameraWS);

                // 对距离进行在_TessellationFadeStart 和 _TessellationFadeEnd 之间归一化
                // 小于 _TessellationFadeStart 的，结果是 < 0; 大于 _TessellationFadeEnd 的，结果是 > 1
                float normallizedDistance0 = (distance0 - _TessellationFadeStart) / (_TessellationFadeEnd -_TessellationFadeEnd);
                float normallizedDistance1 = (distance1 - _TessellationFadeStart) / (_TessellationFadeEnd -_TessellationFadeEnd);
                float normallizedDistance2 = (distance2 - _TessellationFadeStart) / (_TessellationFadeEnd -_TessellationFadeEnd);

                float edgeFactor0 = saturate(1.0 - normallizedDistance0);
                float edgeFactor1 = saturate(1.0 - normallizedDistance1);
                float edgeFactor2 = saturate(1.0 - normallizedDistance2);

                f.edge[0] = max(edgeFactor0 * _TessellationAmount, 1);
                f.edge[1] = max(edgeFactor1 * _TessellationAmount, 1);
                f.edge[2] = max(edgeFactor2 * _TessellationAmount, 1);

                f.inside = (f.edge[0] + f.edge[1] + f.edge[2]) / 3;

                return f;
            }

            [domain("tri")]
            t2f domain_shader(tessFactor factors, OutputPatch<tessControlPoint, 3> patch,float3 baryCentricCoordinates : SV_DomainLocation)
            {
                t2f o = (t2f)0;
                // 新顶点的重心插值
                float3 positionWS = patch[0].positionWS * baryCentricCoordinates[0] +
                    patch[1].positionWS * baryCentricCoordinates[1] +
                    patch[2].positionWS * baryCentricCoordinates[2];

                // 波浪的形状
                positionWS.z = positionWS.z + sin(positionWS.x + positionWS.y + _Time.y * _WaveSpeed) * _WaveHeight;

                o.positionCS = TransformWorldToHClip(positionWS);

                return o;
            }

            float4 fragment_shader(t2f i) : SV_TARGET
            {
                return _BaseColor;
            }
            ENDHLSL
        }
    }
}