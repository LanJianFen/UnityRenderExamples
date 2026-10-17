using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace AdvanceExamples.Skin.MonteCarloSubsurfaceScattering.GeometryComposite.Scripts
{
    // 这个类将渲染分成了 3 个 Pass
    [DisallowMultipleRendererFeature("[Subsurface] Monte Carlo Subsurface Scattering RenderFeature")]

    public class MonteCarloSubsurfaceScatteringRenderFeature : ScriptableRendererFeature
    {
        private class MonteCarloSubsurfaceScatteringPass : ScriptableRenderPass
        {
            private static ProfilingSampler _profilingSampler =  new ("Monte Carlo Subsurface");
            
            // settings
            private Settings _settings;
            
            // Material
            private readonly Material _scatteringMaterial;
            
            // LightMode
            private readonly ShaderTagId _diffuseTagId = new ("Monte Carlo Subsurface Direct Diffuse");
            private readonly ShaderTagId _compositeTagId = new ("Monte Carlo Subsurface Composite");
            
            // Params
            private static readonly int _rcpScatteringDistanceParams = Shader.PropertyToID("_RcpMonteCarloScatteringDistance");
            private static readonly int _scatteringScaleParams = Shader.PropertyToID("_MonteCarloScatteringScale");
            private static readonly int _sampleNumParams = Shader.PropertyToID("_MonteCarloScatteringSampleNum");
            private static readonly int _baseColorScatteringWeightParams = Shader.PropertyToID("_MonteCarloBaseColorScatteringWeight");

            // Rt
            private RTHandle _diffuseRt,  _scatteredRt;
            private static readonly int _diffuseRtId = Shader.PropertyToID("_MonteCarloSubsurfaceDiffuseRt");
            private static readonly int _scatteredRtId = Shader.PropertyToID("_MonteCarloSubsurfaceScatteredRt");

            public void Setup(Settings settings)
            {
                _settings = settings;
                renderPassEvent = settings.RenderPassEvent;
            }
            
            public MonteCarloSubsurfaceScatteringPass(Settings settings, Material scatteringMaterial )
            {
                _scatteringMaterial = scatteringMaterial;
                Setup(settings);
            }
            
            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                // 获取相机的配置
                RenderTextureDescriptor descriptor = renderingData.cameraData.cameraTargetDescriptor;
                descriptor.graphicsFormat = GraphicsFormat.R16G16B16A16_SFloat;
                descriptor.depthStencilFormat = GraphicsFormat.None;
                
                RenderingUtils.ReAllocateIfNeeded(ref _diffuseRt, descriptor, FilterMode.Point,TextureWrapMode.Clamp, name: "_MonteCarloScatteringDiffuseRt");
                RenderingUtils.ReAllocateIfNeeded(ref _scatteredRt, descriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_MonteCarloScatteredRt");
            }

            // ==================================
            // Pass 1 :Direct Diffuse 只输出 直接光的 diffuse 到 _sssDirectDiffuseRT
            // ==================================
            private void ExecuteDiffusePass(ref ScriptableRenderContext context,  ref RenderingData renderingData, CommandBuffer cmd)
            {
                // 按默认的渲染顺序，只给 opaque 的物体执行
                SortingCriteria sorting = renderingData.cameraData.defaultOpaqueSortFlags;
                DrawingSettings drawing = CreateDrawingSettings(_diffuseTagId, ref renderingData, sorting);
                FilteringSettings filtering = new(RenderQueueRange.opaque);

                cmd.SetGlobalFloat(_baseColorScatteringWeightParams, _settings.BaseColorScatteringWeight);
                RTHandle depthStencilRt = renderingData.cameraData.renderer.cameraDepthTargetHandle;
                CoreUtils.SetRenderTarget(cmd, _diffuseRt, depthStencilRt, ClearFlag.Color, Color.black);
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                context.DrawRenderers(renderingData.cullResults, ref drawing, ref filtering);
            }

            // ==================================
            // Pass 2 :MonteCarlo SSS 只输出 SSS
            // ==================================
            private void ExecuteSubSurfacePass(ref ScriptableRenderContext context, ref RenderingData renderingData, CommandBuffer cmd)
            {
                Color scatteringDistance = _settings.ScatteringDistance;
                // 各通道的 平均自由程 d 的倒数 s
                float rcpDistanceR = 1.0f / Mathf.Max(scatteringDistance.r * 255.0f, 0.0001f);
                float rcpDistanceG = 1.0f / Mathf.Max(scatteringDistance.g * 255.0f, 0.0001f);
                float rcpDistanceB = 1.0f / Mathf.Max(scatteringDistance.b * 255.0f, 0.0001f);
                // 传给 Shader 的参数, w 是自由程最长的那个光
                Vector4 rcpScatteringDistanceParams = new Vector4(
                    rcpDistanceR, rcpDistanceG, rcpDistanceB,
                    Mathf.Min(rcpDistanceR, Mathf.Min(rcpDistanceG, rcpDistanceB))
                );
                
                cmd.SetGlobalTexture(_diffuseRtId, _diffuseRt); // 把 Pass 1 画好的交给 MonteCarlo Pass 2
                cmd.SetGlobalVector(_rcpScatteringDistanceParams, rcpScatteringDistanceParams);
                cmd.SetGlobalFloat(_scatteringScaleParams, _settings.ScatteringScale);
                cmd.SetGlobalInt(_sampleNumParams, _settings.SampleNum);
                
                RTHandle depthStencilRt = renderingData.cameraData.renderer.cameraDepthTargetHandle;
                CoreUtils.SetRenderTarget(cmd, _scatteredRt, depthStencilRt, ClearFlag.Color, Color.black);

                // 在屏幕空间绘制 Monte Carlo SSS
                CoreUtils.DrawFullScreen(cmd, _scatteringMaterial);
            }

            // ==================================
            // Pass 3 :混合高光、环境光、SSS
            // ==================================
            private void ExecuteCompositePass(ref ScriptableRenderContext context, ref RenderingData renderingData, CommandBuffer cmd)
            {
                SortingCriteria sorting = renderingData.cameraData.defaultOpaqueSortFlags;  
                DrawingSettings drawing = CreateDrawingSettings(_compositeTagId, ref renderingData, sorting);
                FilteringSettings filtering = new(RenderQueueRange.opaque);

                RTHandle colorRt = renderingData.cameraData.renderer.cameraColorTargetHandle;
                RTHandle depthStencilRt = renderingData.cameraData.renderer.cameraDepthTargetHandle;

                cmd.SetGlobalFloat(_baseColorScatteringWeightParams, _settings.BaseColorScatteringWeight);
                cmd.SetGlobalTexture(_scatteredRtId, _scatteredRt);
                CoreUtils.SetRenderTarget(cmd, colorRt, depthStencilRt);
                
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                context.DrawRenderers(renderingData.cullResults, ref drawing, ref filtering);
            }

            public override void Execute(ScriptableRenderContext ctx, ref RenderingData renderingData)
            {
                if (_scatteringMaterial == null) return;
                
                CommandBuffer cmd = CommandBufferPool.Get();
                
                using (var profilingScope = new ProfilingScope(cmd, _profilingSampler))
                {
                    ExecuteDiffusePass(ref ctx, ref renderingData, cmd);
                    ExecuteSubSurfacePass(ref ctx, ref renderingData, cmd);
                    ExecuteCompositePass(ref ctx, ref renderingData, cmd);
                }

                ctx.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
            
            public void Dispose()
            {
                _diffuseRt?.Release();
                _scatteredRt?.Release();
            }
        }
        
        [Serializable]
        public class Settings
        {
            public RenderPassEvent RenderPassEvent = RenderPassEvent.AfterRenderingOpaques;
            [ColorUsage(false, true)] public Color ScatteringDistance = new (15.0f, 5.0f, 2.0f, 1.0f);
            [Range(0f, 10f)] public float ScatteringScale = 1.0f;  // 模型的缩放大小，用于巨人和正常人
            [Range(0f, 1f)] public float BaseColorScatteringWeight = 0.5f;
            [Range(1, 32)] public int SampleNum = 16;
            //[Range(0, 1)] public float Resolution = 1.0f;
        }
        public Settings settings = new ();
        
        [HideInInspector] public Shader ScatteringShader;  
        private Material _scatteringMaterial;
        
        MonteCarloSubsurfaceScatteringPass _monteCarloSubsurfaceScatteringPass;

        public void OnValidate()
        {
            if (!isActive) return;
            
            if(ScatteringShader == null) ScatteringShader = Shader.Find("Advance Examples/SSS/MonteCarlo SSS Core");
            
            _monteCarloSubsurfaceScatteringPass   ?.Setup(settings);
        }
        
        public override void Create()
        {
            if (ScatteringShader == null) return;
            // 在内存里创建核心的 SSS Material
            if (_scatteringMaterial == null) _scatteringMaterial = CoreUtils.CreateEngineMaterial(ScatteringShader);
            // 创建 SSS 的 Render Pass
            _monteCarloSubsurfaceScatteringPass = new (settings, _scatteringMaterial);
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (_scatteringMaterial == null) return;
            renderer.EnqueuePass(_monteCarloSubsurfaceScatteringPass);
        }

        protected override void Dispose(bool disposing)
        {
            _monteCarloSubsurfaceScatteringPass?.Dispose();
            CoreUtils.Destroy(_scatteringMaterial);
        }
    }
}