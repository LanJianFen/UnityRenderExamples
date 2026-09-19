using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace AdvanceExamples.Skin.MonteCarloSubsurfaceScattering.Scripts
{
    // 这个类将渲染分成了 3 个 Pass
    [DisallowMultipleRendererFeature("[Skin] Monte Carlo Subsurface Scattering RenderFeature")]

    public class MonteCarloSubsurfaceScatteringRenderFeature : ScriptableRendererFeature
    {
        private class MonteCarloSubsurfaceScatteringPass : ScriptableRenderPass
        {
            private ProfilingSampler _profilingSampler;
            private readonly MonteCarloSubsurfaceScatteringRenderFeature _sssRenderFeature;
            private readonly ShaderTagId _diffuseTagId = new ("Subsurface Scattering Direct Diffuse");
            private readonly ShaderTagId _compositeTagId = new ("Subsurface Scattering Final Blend");
            
            private readonly int _rcpSubsurfaceScatteringDistanceParamsId = Shader.PropertyToID("_RcpSubsurfaceScatteringDistance");
            private readonly int _surfaceScale = Shader.PropertyToID("_SurfaceScale");

            private RTHandle _diffuseRt;                                     // Pass 1 输出的直接光的 diffuse RT， 交给 SSS Pass 生成 SSS RT
            private RTHandle _subsurfaceScatteringRt;                    // Pass 2 SSS 层 输出的 RT
            
            private readonly int _diffuseRtId = Shader.PropertyToID("_SubsurfaceDirectDiffuseRT");
            private readonly int _subsurfaceScatteringRT = Shader.PropertyToID("_SubsurfaceScatteringRT");

            public MonteCarloSubsurfaceScatteringPass(MonteCarloSubsurfaceScatteringRenderFeature sssRenderFeature)
            {
                this._sssRenderFeature = sssRenderFeature;
                this.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
            }
            
            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                // 获取相机的配置
                RenderTextureDescriptor descriptor = renderingData.cameraData.cameraTargetDescriptor;
                descriptor.colorFormat = RenderTextureFormat.DefaultHDR;  //颜色用普通的 srgb
                descriptor.depthBufferBits = 0;  //???、
                
                RenderingUtils.ReAllocateIfNeeded(ref _diffuseRt, descriptor, FilterMode.Bilinear,TextureWrapMode.Clamp, name: "Subsurface Scattering Direct Diffuse RT");
                RenderingUtils.ReAllocateIfNeeded(ref _subsurfaceScatteringRt, descriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "Subsurface Scattering RT");
            }

            // ==================================
            // Pass 1 :Direct Diffuse 只输出 直接光的 diffuse 到 _sssDirectDiffuseRT
            // ==================================
            private void ExecuteDiffusePass(ref ScriptableRenderContext context, ref CommandBuffer cmd, ref RenderingData renderingData, ref FilteringSettings filteringSettings)
            {
                // 按默认的渲染顺序，只给 opaque 的物体执行
                SortingCriteria sortingCriteria = renderingData.cameraData.defaultOpaqueSortFlags;
                DrawingSettings sssDirectDiffuseDrawSettings = CreateDrawingSettings(_diffuseTagId, ref renderingData, sortingCriteria);
                
                RTHandle depthTargetHandle = renderingData.cameraData.renderer.cameraDepthTargetHandle;
                cmd.SetRenderTarget(_diffuseRt, depthTargetHandle);
                cmd.ClearRenderTarget(false, true, Color.black);
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                context.DrawRenderers(renderingData.cullResults, ref sssDirectDiffuseDrawSettings, ref filteringSettings);
            }

            // ==================================
            // Pass 2 :MonteCarlo SSS 只输出 SSS
            // ==================================
            private void ExecuteSubSurfaceScatteringPass(ref ScriptableRenderContext context, ref CommandBuffer cmd, ref RenderingData renderingData, ref FilteringSettings filteringSettings)
            {
                cmd.SetGlobalTexture(_diffuseRtId, _diffuseRt); // 把 Pass 1 画好的交给 MonteCarlo Pass 2
                
                Color sssDistance = _sssRenderFeature.sssDistance;
                // 各通道的 平均自由程 d 的倒数 s
                float rcpSubsurfaceScatteringDistanceR = 1.0f / Mathf.Max(sssDistance.r * 255.0f, 0.0001f);
                float rcpSubsurfaceScatteringDistanceG = 1.0f / Mathf.Max(sssDistance.g * 255.0f, 0.0001f);
                float rcpSubsurfaceScatteringDistanceB = 1.0f / Mathf.Max(sssDistance.b * 255.0f, 0.0001f);
                // 传给 Shader 的参数, w 是自由程最长的那个光
                Vector4 rcpSubsurfaceScatteringDistanceParams = new Vector4(
                    rcpSubsurfaceScatteringDistanceR,
                    rcpSubsurfaceScatteringDistanceG,
                    rcpSubsurfaceScatteringDistanceB,
                    Mathf.Min(rcpSubsurfaceScatteringDistanceR, Mathf.Min(rcpSubsurfaceScatteringDistanceG, rcpSubsurfaceScatteringDistanceB))
                );
                cmd.SetGlobalVector(_rcpSubsurfaceScatteringDistanceParamsId, rcpSubsurfaceScatteringDistanceParams);
                cmd.SetGlobalFloat(_surfaceScale, _sssRenderFeature.surfaceScale);
                
                RTHandle depthTargetHandle = renderingData.cameraData.renderer.cameraDepthTargetHandle;
                cmd.SetRenderTarget(_subsurfaceScatteringRt, depthTargetHandle);
                cmd.ClearRenderTarget(false, true, Color.black);
                
                // 在屏幕空间绘制 Monte Carlo SSS
                CoreUtils.DrawFullScreen(cmd, _sssRenderFeature._sssMonteCarloCoreMaterial);
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
            }

            // ==================================
            // Pass 3 :混合高光、环境光、SSS
            // ==================================
            private void ExecuteCompositePass(ref ScriptableRenderContext context, ref CommandBuffer cmd, ref RenderingData renderingData, ref FilteringSettings filteringSettings)
            {
                RTHandle colorTargetHandle = renderingData.cameraData.renderer.cameraColorTargetHandle;
                RTHandle depthTargetHandle = renderingData.cameraData.renderer.cameraDepthTargetHandle;

                cmd.SetGlobalTexture(_subsurfaceScatteringRT, _subsurfaceScatteringRt);
                cmd.SetRenderTarget(colorTargetHandle, depthTargetHandle);
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                
                SortingCriteria sorting = renderingData.cameraData.defaultOpaqueSortFlags;  
                DrawingSettings finalBlendDrawSettings = CreateDrawingSettings(_compositeTagId, ref renderingData, sorting);
                context.DrawRenderers(renderingData.cullResults, ref finalBlendDrawSettings, ref filteringSettings);
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                if (_diffuseRt == null) return;
                
                //using (var profilingScope = new ProfilingScope("Monte Carlo Subsurface Scattering"))
                CommandBuffer cmd = CommandBufferPool.Get("3 Pass SSS Feature");
                FilteringSettings filteringSettings = new (RenderQueueRange.opaque);
                
                ExecuteDiffusePass(ref context, ref cmd, ref renderingData, ref filteringSettings);
                ExecuteSubSurfaceScatteringPass(ref context, ref cmd, ref renderingData, ref filteringSettings);
                ExecuteCompositePass(ref context, ref cmd, ref renderingData, ref filteringSettings);

                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
            
            public void Dispose()
            {
                _diffuseRt?.Release();
                _subsurfaceScatteringRt?.Release();
            }
        }
        
        [SerializeField] private Shader sssMonteCarloCoreShader;  
        [ColorUsage(false, true)]
        [SerializeField] public Color sssDistance = new Color(15.0f, 5.0f, 2.0f, 1.0f);
        [SerializeField] public float surfaceScale = 1.0f;  // 模型的缩放大小，用于巨人和正常人
        private Material _sssMonteCarloCoreMaterial;
        
        MonteCarloSubsurfaceScatteringPass _monteCarloSubsurfaceScatteringPass;

        // Feature 初始化时调用
        public override void Create()
        {
            if (sssMonteCarloCoreShader == null) return;
            // 在内存里创建核心的 SSS Material
            _sssMonteCarloCoreMaterial = CoreUtils.CreateEngineMaterial(sssMonteCarloCoreShader);
            // 创建 SSS 的 Render Pass
            _monteCarloSubsurfaceScatteringPass = new (this);
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (sssMonteCarloCoreShader == null) return;
            renderer.EnqueuePass(_monteCarloSubsurfaceScatteringPass);
        }

        protected override void Dispose(bool disposing)
        {
            CoreUtils.Destroy(_sssMonteCarloCoreMaterial);
            _monteCarloSubsurfaceScatteringPass?.Dispose();
        }
    }
}