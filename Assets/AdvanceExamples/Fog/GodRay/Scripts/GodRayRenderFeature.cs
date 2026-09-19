using System;
using System.Collections.Generic;
using System.Diagnostics;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace AdvanceExamples.Fog.GodRay.Scripts
{
    [DisallowMultipleRendererFeature("[Fog] God Ray RenderFeature")]

    public class GodRayRenderFeature : ScriptableRendererFeature
    {
#if UNITY_EDITOR
        private class GodRayShadowPass : ScriptableRenderPass
        {
            // 生成深度的相机
            private Camera _ghostCamera;

            // Material
            private Material _linearDepthMat;

            // Light Mode
            private static readonly ShaderTagId[] _forwardTagId = new[]
            {
                new ShaderTagId("UniversalForward"),
                new ShaderTagId("SRPDefaultUnlit"),
                new ShaderTagId("UniversalForwardOnly")
            };

            private static readonly int _godRayCameraPositionId = Shader.PropertyToID("_GodRayCameraPosition");
            private static readonly int _godRayCameraForwardId = Shader.PropertyToID("_GodRayCameraForward");
            private static readonly int _godRayCameraFarClipId = Shader.PropertyToID("_GodRayCameraFarClip");

            // RT
            private RenderTargetHandle  _godRayShadowDepthRt;

            public GodRayShadowPass(QualitySettings settings, Material linearDepthMat)
            {
                renderPassEvent = settings.ForwardPassEvent;

                _linearDepthMat = linearDepthMat;

                // 创建相机
                _ghostCamera = new GameObject("GodRay GhostCamera Internal").AddComponent<Camera>();
                _ghostCamera.gameObject.hideFlags = HideFlags.HideAndDontSave;  // 不进场景，不进存档
                _ghostCamera.enabled = false; // 禁止自动渲染
                _ghostCamera.orthographic = true;
            
                _godRayShadowDepthRt.Init("God Ray Shadow RT");
            }

            public void Setup(QualitySettings settings, Material linearDepthMat)
            {
                renderPassEvent = settings.ForwardPassEvent;
                _linearDepthMat = linearDepthMat == null? _linearDepthMat : linearDepthMat;
            } 

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                /*RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.msaaSamples = 1;
            desc.width = 512;
            desc.height = 512;
            desc.graphicsFormat = GraphicsFormat.None;
            desc.depthBufferBits = 24;
            RenderingUtils.ReAllocateIfNeeded(ref _godRayShadowDepthRt, desc, FilterMode.Point, TextureWrapMode.Clamp, name: "God Ray Shadow RT");*/
                RenderTextureDescriptor desc = new RenderTextureDescriptor(GodRayHelper.GodRayCookieMaskResolution, GodRayHelper.GodRayCookieMaskResolution, RenderTextureFormat.Depth, 24)
                {
                    msaaSamples = 1,
                    useMipMap = false,
                    autoGenerateMips = false
                };
            
                cmd.GetTemporaryRT(_godRayShadowDepthRt.id, desc, FilterMode.Point);
            }

            // ================================================
            // 检查插槽是否给了离线的图
            // ================================================
            private bool CheckNeedRealTimeShadow(GodRayHelper godRay)
            {
                if (godRay.NeedsRealtimeShadow) godRay.SetCookieMaskRt();
                else godRay.SetCookieMaskBaked();

                return godRay.NeedsRealtimeShadow;
            }

            // ================================================
            // 构建相机配置
            // ================================================
            private void ConfigureGhostCamera(CommandBuffer cmd, ScriptableRenderContext ctx, Transform godRay)
            {
                (Vector3 scale, Vector3 positionWs, Quaternion rotationWs) = (godRay.localScale, godRay.position, godRay.rotation * Quaternion.Euler(-90, 0, 0));

                _ghostCamera.transform.position = positionWs;
                _ghostCamera.transform.rotation = rotationWs;
                _ghostCamera.orthographicSize = scale.z;
                _ghostCamera.aspect = scale.x / scale.z;
                _ghostCamera.nearClipPlane = 0.0f;
                _ghostCamera.farClipPlane = scale.y;

                Matrix4x4 view = _ghostCamera.worldToCameraMatrix;
                Matrix4x4 projection = GL.GetGPUProjectionMatrix(_ghostCamera.projectionMatrix, true);
                
                if (!SystemInfo.graphicsUVStartsAtTop) // 为 false 说明是 OpenGL/GLES
                {
                    // 垂直镜像翻转投影矩阵 (第 1 行取反)
                    projection.m10 = -projection.m10;
                    projection.m11 = -projection.m11;
                    projection.m12 = -projection.m12;
                    projection.m13 = -projection.m13;
                }
                
                cmd.SetViewProjectionMatrices(view, projection);
            }

            // ================================================
            // 绘制
            // ================================================
            private void DrawingLinearDepth(CommandBuffer cmd, ScriptableRenderContext ctx, ref RenderingData renderingData, GodRayHelper godRay)
            {
                if (!_ghostCamera.TryGetCullingParameters(out ScriptableCullingParameters cullingParams)) return;
                CullingResults ghostCull = ctx.Cull(ref cullingParams);

                FilteringSettings filtering = new FilteringSettings(RenderQueueRange.opaque);
                SortingSettings sorting = new SortingSettings(_ghostCamera) { criteria = SortingCriteria.CommonOpaque };
                DrawingSettings drawing = new DrawingSettings(_forwardTagId[0], sorting)
                {
                    overrideMaterial = _linearDepthMat,
                    overrideMaterialPassIndex = 0,
                    enableInstancing = true
                };
                drawing.SetShaderPassName(1, _forwardTagId[1]);
                drawing.SetShaderPassName(2, _forwardTagId[2]);
            
                _linearDepthMat.SetInt("_ZTest", (int)(SystemInfo.usesReversedZBuffer ? CompareFunction.GreaterEqual : CompareFunction.LessEqual));

                // Rt 在脚本里分配和销毁，Feature 不管理，并且 Rt 赋值到材质上也封装在脚本上
                cmd.SetRenderTarget(godRay.ShadowRt, _godRayShadowDepthRt.Identifier());
                cmd.ClearRenderTarget(true, true, Color.red, SystemInfo.usesReversedZBuffer ? 0.0f : 1.0f);

                cmd.SetGlobalVector(_godRayCameraPositionId, _ghostCamera.transform.position);
                cmd.SetGlobalVector(_godRayCameraForwardId, _ghostCamera.transform.forward);
                cmd.SetGlobalFloat(_godRayCameraFarClipId, _ghostCamera.farClipPlane);
                if (!SystemInfo.graphicsUVStartsAtTop) cmd.SetInvertCulling(true);
                ctx.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                ctx.DrawRenderers(ghostCull, ref drawing, ref filtering);
                
                if (!SystemInfo.graphicsUVStartsAtTop)
                {
                    cmd.SetInvertCulling(false);
                    ctx.ExecuteCommandBuffer(cmd);
                    cmd.Clear();
                }
            }

            // ================================================
            // 重置回主相机
            // ================================================
            private void ResetMainCamera(CommandBuffer cmd, ScriptableRenderContext ctx, ref RenderingData renderingData)
            {
                Camera cam = renderingData.cameraData.camera;

                cmd.SetViewProjectionMatrices(cam.worldToCameraMatrix, cam.projectionMatrix);
            }

            public override void Execute(ScriptableRenderContext ctx, ref RenderingData renderingData)
            {
                if (_linearDepthMat == null || _ghostCamera == null) return;

                List<GodRayHelper> godRays = GodRayHelper.ActiveGodRays;
                if (godRays == null || godRays.Count < 1) return;

                CommandBuffer cmd = CommandBufferPool.Get();
                cmd.BeginSample("God Ray Shadow Pass");

                foreach (var sampler in godRays)
                {
                    if (!CheckNeedRealTimeShadow(sampler)) continue;

                    // 构建相机配置
                    ConfigureGhostCamera(cmd, ctx, sampler.transform);

                    // 绘制
                    DrawingLinearDepth(cmd, ctx, ref renderingData, sampler);
                }

                // 重置主相机
                ResetMainCamera(cmd, ctx, ref renderingData);

                cmd.EndSample("God Ray Shadow Pass");
                ctx.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }

            public override void OnCameraCleanup(CommandBuffer cmd)
            {
                cmd.ReleaseTemporaryRT(_godRayShadowDepthRt.id);
            }
        
            public void Dispose()
            {
                CoreUtils.Destroy(_ghostCamera.gameObject);
                _ghostCamera = null;
            }

            // ================================================
            // 构建 V 和 P 矩阵：正交相机，且父物体只有旋转，禁止缩放
            // ================================================
            private (Matrix4x4, Matrix4x4) ViewAndProjection(Transform camera)
            {
                (Vector3 scale, Vector3 positionWs, Quaternion rotationWs) = (camera.localScale, camera.position, camera.rotation * Quaternion.Euler(-90, 0, 0));

                Matrix4x4 view = Matrix4x4.Scale(new Vector3(1, 1, -1)) * Matrix4x4.TRS(positionWs, rotationWs, Vector3.one).inverse; // camera 的 M 矩阵，就是其他物体的 V 矩阵 ，openGL 的相机正面看的是 -z 方向，但是我们构建的矩阵看的是 +z 方向

                Matrix4x4 projection = GL.GetGPUProjectionMatrix(Matrix4x4.Ortho(-scale.x, scale.x, -scale.z, scale.z, 0.0f, scale.y), true);

                return (view, projection);
            }

            // ================================================
            // 构建相机配置
            // ================================================
            private void ConfigureOrthoCameraLegacy(CommandBuffer cmd, ScriptableRenderContext ctx, Transform camera)
            {
                (Matrix4x4 view, Matrix4x4 projection) = ViewAndProjection(camera);

                cmd.SetViewProjectionMatrices(view, projection);

                ctx.ExecuteCommandBuffer(cmd); // 必须提交

                cmd.Clear();
            }
        }

    
        // 只给 Scene 窗口用（临时也在 Game 窗口生效方便对比测试）：手动重新画一遍不透明物体的深度，塞进全局 _CameraDepthTexture。
        // 画法照抄 GodRayShadowPass —— 用 LinearDepthMat 做 overrideMaterial，靠 ZWrite On 让硬件把真实深度写进深度附件，
        // 而不是用它 Frag 里手算的那个 "linear depth_01"（那是给 Cookie Mask 用的自定义编码，不是硬件深度，不能直接喂 _CameraDepthTexture）。
        private class GodRaySceneViewDepthPass : ScriptableRenderPass
        {
            // Light Mode，跟 GodRayShadowPass 一样
            private static readonly ShaderTagId[] _forwardTagId = new[]
            {
                new ShaderTagId("UniversalForward"),
                new ShaderTagId("SRPDefaultUnlit"),
                new ShaderTagId("UniversalForwardOnly")
            };
            private static readonly int _cameraDepthTextureId = Shader.PropertyToID("_CameraDepthTexture");
            private static readonly int _godRayCameraPositionId = Shader.PropertyToID("_GodRayCameraPosition");
            private static readonly int _godRayCameraForwardId = Shader.PropertyToID("_GodRayCameraForward");
            private static readonly int _godRayCameraFarClipId = Shader.PropertyToID("_GodRayCameraFarClip");

            private Material _linearDepthMat;

            private RenderTargetHandle _sceneViewDepthRt;
            private RenderTargetHandle _sceneViewDummyColorRt;

            public GodRaySceneViewDepthPass(QualitySettings settings, Material linearDepthMat)
            {
                renderPassEvent = settings.ForwardPassEvent;
                _linearDepthMat = linearDepthMat;

                _sceneViewDepthRt.Init("_God Ray SceneView Depth RT");
                _sceneViewDummyColorRt.Init("_God Ray SceneView Dummy Color RT");
            }

            public void Setup(QualitySettings settings, Material linearDepthMat)
            {
                renderPassEvent = settings.ForwardPassEvent;
                _linearDepthMat = linearDepthMat == null ? _linearDepthMat : linearDepthMat;
            }

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                RenderTextureDescriptor srcDesc = renderingData.cameraData.cameraTargetDescriptor;

                RenderTextureDescriptor depthDesc = new RenderTextureDescriptor(srcDesc.width, srcDesc.height, RenderTextureFormat.Depth, 24)
                {
                    msaaSamples = 1
                };
                cmd.GetTemporaryRT(_sceneViewDepthRt.id, depthDesc, FilterMode.Point);

                // LinearDepthMat 的 Pass 会往 SV_TARGET 写东西，随便给一张不关心内容的 color RT 承接，真正要的是它 ZWrite On 写进深度附件的硬件深度
                RenderTextureDescriptor colorDesc = new RenderTextureDescriptor(srcDesc.width, srcDesc.height, RenderTextureFormat.Default, 0)
                {
                    msaaSamples = 1
                };
                cmd.GetTemporaryRT(_sceneViewDummyColorRt.id, colorDesc, FilterMode.Point);
            }

            public override void Execute(ScriptableRenderContext ctx, ref RenderingData renderingData) 
            { 
                if (_linearDepthMat == null) return; 
                Camera camera = renderingData.cameraData.camera; 
                CommandBuffer cmd = CommandBufferPool.Get(); 
                cmd.BeginSample("God Ray SceneView Depth Prepass"); 

                CoreUtils.SetRenderTarget(
                    cmd, 
                    _sceneViewDummyColorRt.Identifier(), 
                    _sceneViewDepthRt.Identifier(), 
                    ClearFlag.All, 
                    Color.clear
                );
                ctx.ExecuteCommandBuffer(cmd); 
                cmd.Clear(); 
            
                SortingSettings sorting = new SortingSettings(camera) { criteria = SortingCriteria.CommonOpaque }; 
                DrawingSettings drawing = new DrawingSettings(_forwardTagId[0], sorting) 
                { 
                    overrideMaterial = _linearDepthMat, 
                    overrideMaterialPassIndex = 1, 
                    enableInstancing = true
                }; 
                drawing.SetShaderPassName(1, _forwardTagId[1]);
                drawing.SetShaderPassName(2, _forwardTagId[2]);
                FilteringSettings filtering = new FilteringSettings(RenderQueueRange.opaque); 

                ctx.DrawRenderers(renderingData.cullResults, ref drawing, ref filtering); 
                cmd.SetGlobalTexture(_cameraDepthTextureId, _sceneViewDepthRt.Identifier()); 
            
                cmd.EndSample("God Ray SceneView Depth Prepass"); 
                ctx.ExecuteCommandBuffer(cmd); 
                CommandBufferPool.Release(cmd); 
            }
        
            public override void OnCameraCleanup(CommandBuffer cmd)
            {
                cmd.ReleaseTemporaryRT(_sceneViewDepthRt.id);
                cmd.ReleaseTemporaryRT(_sceneViewDummyColorRt.id);
            }
        }
#endif

        private class GodRayRenderPass : ScriptableRenderPass
        {
            private readonly QualitySettings _settings;

            // LightMode
            private static readonly ShaderTagId _godRayTagId = new ShaderTagId("GodRayLargeForward");
            private static readonly ShaderTagId _godRayMiniTagId = new ShaderTagId("GodRayMiniForward");

            // 降采样材质
            private Material _upsampleMat;

            internal RenderTargetHandle _godRayRt;
            internal RenderTargetHandle _depthStencilRt;
        
            public GodRayRenderPass(QualitySettings settings, Material upsampleMat)
            {
                _settings = settings;
                renderPassEvent = settings.ForwardPassEvent;

                _upsampleMat = upsampleMat;
            
                _godRayRt.Init("_God Ray RT");
                _depthStencilRt.Init("_God Ray Stencil RT");
            
                ConfigureInput(ScriptableRenderPassInput.Depth);
            }

            public void Setup(QualitySettings settings, Material upsampleMat)
            {
                renderPassEvent = settings.ForwardPassEvent;
                _upsampleMat = upsampleMat;
            }

            // todo: 注意 安卓 Vulkan 平台是否能用这些RT的格式，还有深度的那个 exr
            // RTHandle 系统不支持 combined RT，color 和 depth 必须分成两张
            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                /*RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.msaaSamples = 1;
            desc.width = Mathf.Max(1, Mathf.RoundToInt(desc.width * _settings.ResolutionScale));
            desc.height = Mathf.Max(1, Mathf.RoundToInt(desc.height * _settings.ResolutionScale));

            // Color Rt
            desc.useMipMap = true;
            desc.autoGenerateMips = false;
            desc.graphicsFormat = SystemInfo.GetGraphicsFormat(DefaultFormat.HDR); // Unity 挑平台最优 HDR
            desc.depthBufferBits = 0;
            //RenderingUtils.ReAllocateIfNeeded(ref _godRayRt, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_God Ray RT");
            cmd.GetTemporaryRT(_godRayRt.id, desc, FilterMode.Bilinear);

            // Depth-Stencil RT：无 color，24bit depth + 8bit stencil，Unity 挑平台最优格式
            desc.graphicsFormat = GraphicsFormat.None;
            desc.depthBufferBits = 24;
            //RenderingUtils.ReAllocateIfNeeded(ref _depthStencilRt, desc, FilterMode.Point, TextureWrapMode.Clamp, name: "_God Ray Stencil RT");*/
           
                RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
                int width = Mathf.Max(1, Mathf.RoundToInt(desc.width * _settings.ResolutionScale));
                int height = Mathf.Max(1, Mathf.RoundToInt(desc.height * _settings.ResolutionScale));
            
                RenderTextureDescriptor colorDesc = new RenderTextureDescriptor(width, height, RenderTextureFormat.DefaultHDR, 0)
                {
                    msaaSamples = 1,
                    useMipMap = false,
                    autoGenerateMips = false
                };
                cmd.GetTemporaryRT(_godRayRt.id, colorDesc, FilterMode.Bilinear);
            
            
                RenderTextureDescriptor depthDesc = new RenderTextureDescriptor(width, height, RenderTextureFormat.Depth, 24)
                {
                    msaaSamples = 1
                };
                cmd.GetTemporaryRT(_depthStencilRt.id, depthDesc, FilterMode.Point);
            }
            
            // =========================================================
            // CPU 收集与“由近到远”距离计算
            // =========================================================
            private (GodRayHelper ray, float sortDist, bool insideCamera)[] _miniGodRays = new (GodRayHelper, float, bool)[12];
            private static readonly IComparer<(GodRayHelper ray, float sortDist, bool insideCamera)> _miniGodRayComparer 
                = Comparer<(GodRayHelper ray, float sortDist, bool insideCamera)>.Create((a, b) => a.sortDist.CompareTo(b.sortDist));
            private int MiniGodRaySort(Camera camera)
            {
                (Vector3 cameraPos, Vector3 cameraForward) = (camera.transform.position, camera.transform.forward);
                 Vector3 rayCenterOffset = new Vector3(0, 0.5f, 0); 
                 
                 int rayCount = GodRayHelper.ActiveGodRays.Count;
                 if (_miniGodRays.Length < rayCount) Array.Resize(ref _miniGodRays, Mathf.NextPowerOfTwo(rayCount));
                 
                int validCount = 0;
                for (int i = 0; i < rayCount; i++)
                {
                    var ray = GodRayHelper.ActiveGodRays[i];
                    if (ray == null || !ray.isActiveAndEnabled || ray.RayType != GodRayHelper.GodRayType.Mini) continue;
                    
                    bool isInsideCamera = ray.IsMiniGodRayAndCameraInside(cameraPos);
                    float sortDist = isInsideCamera
                        ? float.MinValue
                        : Vector3.Dot(ray.transform.TransformPoint(rayCenterOffset) - cameraPos, cameraForward);

                    _miniGodRays[validCount++] = (ray , sortDist, isInsideCamera);
                }
                
                Array.Sort(_miniGodRays, 0, validCount, _miniGodRayComparer);
                return validCount;
            }

            private void ExecuteMiniGodRay(ScriptableRenderContext ctx, ref RenderingData renderingData)
            {
                int validCount = MiniGodRaySort(renderingData.cameraData.camera);
                if (validCount == 0) return;
                
                CommandBuffer cmd = CommandBufferPool.Get();
                cmd.BeginSample("God Ray Mini Forward Pass");

                // ======================
                // 插入深度降采样 Pass
                // ======================
                //cmd.Blit(null, _depthStencilRt.Identifier(), _upsampleMat, 3);
                cmd.SetRenderTarget(_depthStencilRt.Identifier());
                cmd.ClearRenderTarget(true, false, Color.clear);
                cmd.DrawProcedural(Matrix4x4.identity, _upsampleMat, 3, MeshTopology.Triangles, 3);
                
                cmd.SetRenderTarget(_godRayRt.Identifier(), _depthStencilRt.Identifier());
                cmd.ClearRenderTarget(false, true, Color.clear);
            
                ctx.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                
                /*
                Vector3 cameraPositionWs = renderingData.cameraData.camera.transform.position;
                foreach (var ray in GodRayHelper.ActiveGodRays)
                {
                    if (ray == null || !ray. isActiveAndEnabled) continue;

                    bool isCameraInside = ray.IsMiniGodRayAndCameraInside(cameraPositionWs);
                    Material mat = ray.Renderer.sharedMaterial;
                    cmd.DrawRenderer(ray.Renderer, mat,0,isCameraInside? mat.FindPass("GodRayMiniCylinderInside"): mat.FindPass("GodRayMiniCylinderOutside"));
                }*/
                
                for (int i = 0; i < validCount; i++)
                {
                    var (ray, _, insideCamera) = _miniGodRays[i];
                    Material mat = ray.Renderer.sharedMaterial;
                    if (mat == null) continue;
                    int passIndex = insideCamera 
                        ? mat.FindPass("GodRayMiniCylinderInside") 
                        : mat.FindPass("GodRayMiniCylinderOutside");
                    cmd.DrawRenderer(ray.Renderer, mat, 0, passIndex);
                }
                
                //cmd.GenerateMips(_godRayRt.Identifier());
            
                cmd.EndSample("God Ray Mini Forward Pass");
                ctx.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }

            private void ExecuteLargeGodRay(ScriptableRenderContext ctx, ref RenderingData renderingData)
            {
                SortingSettings sorting = new SortingSettings(renderingData.cameraData.camera)
                {
                    criteria = SortingCriteria.CommonOpaque
                };

                DrawingSettings drawing = new DrawingSettings(_godRayTagId, sorting)
                {
                    perObjectData = PerObjectData.None,
                    enableInstancing = true,
                };

                FilteringSettings filtering = new FilteringSettings(RenderQueueRange.transparent);

                CommandBuffer cmd = CommandBufferPool.Get();
                cmd.BeginSample("Large God Ray Forward Pass");

                cmd.SetRenderTarget(_godRayRt.Identifier(), _depthStencilRt.Identifier());
                cmd.ClearRenderTarget(true, true, Color.clear);
                ctx.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                ctx.DrawRenderers(renderingData.cullResults, ref drawing, ref filtering);

                //cmd.GenerateMips(_godRayRt.Identifier());

                cmd.EndSample("Large God Ray Forward Pass");
                ctx.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }

            public override void Execute(ScriptableRenderContext ctx, ref RenderingData renderingData)
            {
                if (GodRayHelper.HasAnyMiniGodRay())
                    ExecuteMiniGodRay(ctx, ref renderingData);
                else if(GodRayHelper.HasAnyGodRay())
                    ExecuteLargeGodRay(ctx, ref renderingData);
            }

            public override void OnCameraCleanup(CommandBuffer cmd)
            {
                cmd.ReleaseTemporaryRT(_godRayRt.id);
                cmd.ReleaseTemporaryRT(_depthStencilRt.id);
            }
        
            /*public void Dispose()
        {
            _godRayRt?.Release();
            _depthStencilRt?.Release();
        }*/
        }

        private class UpsampleRenderPass : ScriptableRenderPass
        {
            private Material _upsampleMat;
            private readonly GodRayRenderPass _godRayRenderPass;

            public UpsampleRenderPass(QualitySettings settings, Material upsampleMat, GodRayRenderPass godRayRenderPass)
            {
                renderPassEvent = settings.UpSamplePassEvent;

                _upsampleMat = upsampleMat;
                _godRayRenderPass = godRayRenderPass;
            }

            public void Setup(QualitySettings settings, Material upsampleMat)
            { 
                renderPassEvent = settings.UpSamplePassEvent;
                _upsampleMat = upsampleMat == null ? _upsampleMat : upsampleMat;
            } 

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                if (_upsampleMat == null || _godRayRenderPass._godRayRt == null) return;

                CommandBuffer cmd = CommandBufferPool.Get();
                cmd.BeginSample("God Ray Upsample Pass");

                RenderTargetIdentifier cameraTarget = renderingData.cameraData.renderer.cameraColorTarget;

                cmd.Blit(_godRayRenderPass._godRayRt.Identifier(), cameraTarget, _upsampleMat, Shader.globalMaximumLOD switch
                {
                    1000 => 0,   // LOD 1000
                    800  => 1,   // LOD 800
                    500  => 2,   // LOD 500
                    300  => 2,   // LOD 300
                    _    => 2
                });  
            
                cmd.EndSample("God Ray Upsample Pass");
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
        }


        [Serializable]
        public class QualitySettings
        {
            public RenderPassEvent ForwardPassEvent = RenderPassEvent.AfterRenderingOpaques;
            public RenderPassEvent UpSamplePassEvent = RenderPassEvent.BeforeRenderingTransparents;
            public float ResolutionScale = 0.5f;

        }
        public QualitySettings Settings = new QualitySettings();

        [SerializeField][HideInInspector] 
        internal Shader LinearDepthShader;
        [SerializeField][HideInInspector] 
        internal Shader UpsampleShader;
        internal Material UpsampleMat;

    
        private GodRayRenderPass _godRayRenderPass;
        private UpsampleRenderPass _upsampleRenderPass;


#if UNITY_EDITOR
        internal Material LinearDepthMat;
    
        private GodRayShadowPass _godRayShadowPass;
        private GodRaySceneViewDepthPass _godRaySceneViewDepthPass;
        public void OnValidate()
        {
            if (!isActive) return;

            if (LinearDepthShader == null) LinearDepthShader = Shader.Find("Advance Examples/Fog/God Ray/God Ray Linear Depth");
            if (UpsampleShader == null) UpsampleShader = Shader.Find("Common/Upsample");

            if (UpsampleMat == null) UpsampleMat = CoreUtils.CreateEngineMaterial(UpsampleShader);

            CreateGodRayShadowPass();
            CreateGodRayDepthPrePass();
            _godRayRenderPass ??= new GodRayRenderPass(Settings, UpsampleMat);
            _upsampleRenderPass ??= new UpsampleRenderPass(Settings, UpsampleMat, _godRayRenderPass);
        
            _godRayShadowPass?.Setup(Settings, LinearDepthMat);
            _godRaySceneViewDepthPass?.Setup(Settings, LinearDepthMat);
            _godRayRenderPass?.Setup(Settings, UpsampleMat);
            _upsampleRenderPass?.Setup(Settings, UpsampleMat);
        }

        [Conditional("UNITY_EDITOR")]
        private void CreateGodRayShadowPass()
        {
            if (LinearDepthShader == null) return;
            if (LinearDepthMat == null) LinearDepthMat = CoreUtils.CreateEngineMaterial(LinearDepthShader);
            _godRayShadowPass ??= new GodRayShadowPass(Settings, LinearDepthMat);
        }

        [Conditional("UNITY_EDITOR")]
        private void EnqueueGodRayShadowPass(ScriptableRenderer renderer)
        {
            if (_godRayShadowPass == null) return;
            renderer.EnqueuePass(_godRayShadowPass);
        }

        [Conditional("UNITY_EDITOR")]
        private void DestroyGodRayShadowPass()
        {
            CoreUtils.Destroy(LinearDepthMat);
            _godRayShadowPass?.Dispose();
            _godRayShadowPass = null;
        }
    
        [Conditional("UNITY_EDITOR")]
        private void CreateGodRayDepthPrePass()
        {
            if (LinearDepthShader == null || LinearDepthMat == null) return;
            _godRaySceneViewDepthPass ??= new GodRaySceneViewDepthPass(Settings, LinearDepthMat);
        }

        [Conditional("UNITY_EDITOR")]
        private void EnqueueGodRayDepthPrePass(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (_godRaySceneViewDepthPass == null || !renderingData.cameraData.isSceneViewCamera) return;
            renderer.EnqueuePass(_godRaySceneViewDepthPass);
        }

        [Conditional("UNITY_EDITOR")]
        private void DestroyGodRayDepthPrePass()
        {
            _godRaySceneViewDepthPass = null;
        }
#endif

        public override void Create()
        {
            if (UpsampleShader == null) return;
            if (UpsampleMat == null) UpsampleMat = CoreUtils.CreateEngineMaterial(UpsampleShader);

            _godRayRenderPass ??= new GodRayRenderPass(Settings, UpsampleMat);
            _upsampleRenderPass ??= new UpsampleRenderPass(Settings, UpsampleMat, _godRayRenderPass);

#if UNITY_EDITOR
            CreateGodRayShadowPass();
            CreateGodRayDepthPrePass();
#endif
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (!GodRayHelper.HasAnyGodRay() || Shader.globalMaximumLOD < 800) return;
#if UNITY_EDITOR
            EnqueueGodRayShadowPass(renderer);
            EnqueueGodRayDepthPrePass(renderer, ref renderingData);
#endif
            renderer.EnqueuePass(_godRayRenderPass);
            renderer.EnqueuePass(_upsampleRenderPass);
        }

        protected override void Dispose(bool disposing)
        {
            _godRayRenderPass = null;
            _upsampleRenderPass = null;
#if UNITY_EDITOR
            DestroyGodRayShadowPass();
            DestroyGodRayDepthPrePass();
#endif
        }
    }
}