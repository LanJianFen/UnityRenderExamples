using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace AdvanceExamples.Skin.MonteCarloSubsurfaceScattering.MrtComposite.Scripts
{
    // 这个类将渲染分成了 3 个 Pass
    [DisallowMultipleRendererFeature("[Subsurface] Mrt Monte Carlo Subsurface Scattering RenderFeature")]

    public class MrtMonteCarloSubsurfaceScatteringRenderFeature : ScriptableRendererFeature
    {
        private class MrtMonteCarloSubsurfaceScatteringPass : ScriptableRenderPass
        {
            // profiling
            private readonly ProfilingSampler _profilingSampler = new ("Monte Carlo Subsurface Scattering Pass");

            private QualitySettings _settings;
            private Material _monteCarloCoreMaterial, _compositeMaterial;
            
            // Light Mode
            private static readonly ShaderTagId _forwardTagId = new ("Monte Carlo Subsurface Forward");
            private static readonly ShaderTagId _compositeTagId = new ("Monte Carlo Subsurface Composite");
            
            // 参数
            private static readonly int _rcpScatteringDistanceParam = Shader.PropertyToID("_RcpMonteCarloScatteringDistance");
            private static readonly int _scatteringScaleParam = Shader.PropertyToID("_MonteCarloScatteringScale");

            // RT
            private readonly RenderTargetIdentifier[] _forwardMrts = new RenderTargetIdentifier[3];
            private RTHandle _diffuseRt, _specularRt, _albedoRt, _scatteringRt;
            
            private static readonly int _diffuseRtId = Shader.PropertyToID("_MonteCarloSubsurfaceDiffuseRT");
            private static readonly int _specularRtId = Shader.PropertyToID("_MonteCarloSubsurfaceSpecularRT");
            private static readonly int _albedoRtId = Shader.PropertyToID("_MonteCarloSubsurfaceAlbedoRT");
            private static readonly int _scatteringRtId = Shader.PropertyToID("_MonteCarloSubsurfaceScatteringRT");

            public void Setup(QualitySettings settings, Material monteCarloCoreMaterial, Material compositeMaterial)
            {
                _settings = settings;
                _monteCarloCoreMaterial = monteCarloCoreMaterial;
                _compositeMaterial = compositeMaterial;
                renderPassEvent = _settings.ForwardPassEvent;
            }
            
            public MrtMonteCarloSubsurfaceScatteringPass(QualitySettings settings, Material monteCarloCoreMaterial, Material compositeMaterial)
            {
                Setup(settings, monteCarloCoreMaterial, compositeMaterial);
            }
            
            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                // 获取相机的配置
                RenderTextureDescriptor descriptor = renderingData.cameraData.cameraTargetDescriptor;
                descriptor.msaaSamples = 1;
                descriptor.useMipMap = false;
                descriptor.depthStencilFormat = GraphicsFormat.None;

                descriptor.graphicsFormat = GraphicsFormat.R16G16B16A16_SFloat;   //颜色值会超过 1, 暂定 4 通道
                RenderingUtils.ReAllocateIfNeeded(ref _diffuseRt, descriptor, FilterMode.Bilinear,TextureWrapMode.Clamp, name: "Subsurface Scattering Diffuse RT");
                RenderingUtils.ReAllocateIfNeeded(ref _scatteringRt, descriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "Subsurface Scattering RT");

                descriptor.graphicsFormat = GraphicsFormat.B10G11R11_UFloatPack32;
                RenderingUtils.ReAllocateIfNeeded(ref _specularRt, descriptor, FilterMode.Bilinear,TextureWrapMode.Clamp, name: "Subsurface Scattering Specular RT");

                descriptor.graphicsFormat = GraphicsFormat.R8G8B8A8_SRGB;
                RenderingUtils.ReAllocateIfNeeded(ref _albedoRt, descriptor, FilterMode.Bilinear,TextureWrapMode.Clamp, name: "Subsurface Scattering Specular RT");

                _forwardMrts[0] = _diffuseRt.nameID;
                _forwardMrts[1] = _specularRt.nameID;
                _forwardMrts[2] = _albedoRt.nameID;
            }

            // ====================================================================
            // Pass 1 : Forward Diffuse 分别输出 Diffuse 和 Specular 到 MRT
            // ====================================================================
            private void ExecuteForwardPass(ref ScriptableRenderContext ctx, ref RenderingData renderingData, in CommandBuffer cmd)
            {
                // 按默认的渲染顺序，只给 opaque 的物体执行
                SortingCriteria sorting = renderingData.cameraData.defaultOpaqueSortFlags;
                DrawingSettings drawing = CreateDrawingSettings(_forwardTagId, ref renderingData, sorting);
                FilteringSettings filtering = new FilteringSettings(RenderQueueRange.opaque);
                
                RTHandle depthStencilRt = renderingData.cameraData.renderer.cameraDepthTargetHandle;
                CoreUtils.SetRenderTarget(cmd, _forwardMrts, depthStencilRt, ClearFlag.Color, Color.black);
                ctx.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                ctx.DrawRenderers(renderingData.cullResults, ref drawing, ref filtering);
            }

            // ====================================================================
            // Pass 2 : Screen Space MonteCarlo SSS 只输出 SSS
            // ====================================================================
            private void ExecuteSubSurfacePass(ref ScriptableRenderContext ctx, ref RenderingData renderingData,  in CommandBuffer cmd)
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
                cmd.SetGlobalVector(_rcpScatteringDistanceParam, rcpScatteringDistanceParams);
                cmd.SetGlobalFloat(_scatteringScaleParam, _settings.ScatteringScale);
                
                RTHandle depthStencilRt = renderingData.cameraData.renderer.cameraDepthTargetHandle;
                CoreUtils.SetRenderTarget(cmd, _scatteringRt, depthStencilRt, ClearFlag.Color, Color.black);
                
                // 在屏幕空间绘制 Monte Carlo SSS
                CoreUtils.DrawFullScreen(cmd, _monteCarloCoreMaterial);
            }

            // ====================================================================
            // Pass 3 : 混合高光、SSS
            // ====================================================================
            private void ExecuteCompositePass(ref ScriptableRenderContext ctx, ref RenderingData renderingData,  in CommandBuffer cmd)
            {
                RTHandle colorRt = renderingData.cameraData.renderer.cameraColorTargetHandle;
                RTHandle depthStencilRt = renderingData.cameraData.renderer.cameraDepthTargetHandle;

                cmd.SetGlobalTexture(_scatteringRtId, _scatteringRt);
                cmd.SetGlobalTexture(_specularRtId, _specularRt);
                cmd.SetGlobalTexture(_albedoRtId, _albedoRt);

                CoreUtils.SetRenderTarget(cmd, colorRt, depthStencilRt );
                // 在屏幕空间绘制 Composite，合成 3 张 RT
                CoreUtils.DrawFullScreen(cmd, _compositeMaterial);
            }

            public override void Execute(ScriptableRenderContext ctx, ref RenderingData renderingData)
            {
                if(_monteCarloCoreMaterial == null || _compositeMaterial == null) return;
                
                CommandBuffer cmd = CommandBufferPool.Get();

                using (var profilingScope = new ProfilingScope(cmd, _profilingSampler))
                {
                    // cmd 似乎没必要写 in，不过可以学习一下 in 和 ref 的使用方法，还是保留一下
                    ExecuteForwardPass(ref ctx, ref renderingData, in cmd);
                    ExecuteSubSurfacePass(ref ctx, ref renderingData,in cmd);
                    ExecuteCompositePass(ref ctx, ref renderingData, in cmd);
                }

                ctx.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
            
            public void Dispose()
            {
                _diffuseRt?.Release();
                _specularRt?.Release();
                _albedoRt?.Release();
                _scatteringRt?.Release();
            }
        }
        
        [Serializable]
        public class QualitySettings
        {
            public RenderPassEvent ForwardPassEvent = RenderPassEvent.AfterRenderingOpaques;
            public float ResolutionScale = 0.5f;
            public float ScatteringScale = 1.0f;  // 模型的缩放大小，用于巨人和正常人
            [ColorUsage(false, true)]
            public Color ScatteringDistance = new (15.0f, 5.0f, 2.0f, 1.0f);
        }
        public QualitySettings Settings;
        
        [SerializeField][HideInInspector] public Shader MonteCarloCoreShader;  
        [SerializeField][HideInInspector] public Shader CompositeShader;  
        
        [HideInInspector] public Material MonteCarloCoreMaterial;
        [HideInInspector] public Material CompositeMaterial;

        private MrtMonteCarloSubsurfaceScatteringPass _mrtMonteCarloSubsurfaceScatteringPass;

        void OnValidate()
        {
            if(!isActive) return;
            
            if(MonteCarloCoreShader == null) MonteCarloCoreShader = Shader.Find("Advance Examples/SSS/MonteCarlo SSS Core");
            if(CompositeShader == null) CompositeShader = Shader.Find("Advance Examples/SSS/MonteCarlo SSS Composite");
            
            if (MonteCarloCoreMaterial == null) CoreUtils.CreateEngineMaterial(MonteCarloCoreShader);
            if (CompositeMaterial == null) CoreUtils.CreateEngineMaterial(CompositeShader);
            
            _mrtMonteCarloSubsurfaceScatteringPass ??= new MrtMonteCarloSubsurfaceScatteringPass(Settings, MonteCarloCoreMaterial, CompositeMaterial);
            _mrtMonteCarloSubsurfaceScatteringPass?.Setup(Settings, MonteCarloCoreMaterial, CompositeMaterial);
        }

        public override void Create()
        {
            if (MonteCarloCoreShader == null || CompositeShader == null) return;
            // 在内存里创建核心的 SSS Material
            if(MonteCarloCoreMaterial == null) MonteCarloCoreMaterial = CoreUtils.CreateEngineMaterial(MonteCarloCoreShader);
            if(CompositeMaterial == null) CompositeMaterial = CoreUtils.CreateEngineMaterial(CompositeShader);
            // 创建 SSS 的 Render Pass
            _mrtMonteCarloSubsurfaceScatteringPass ??= new MrtMonteCarloSubsurfaceScatteringPass(Settings, MonteCarloCoreMaterial, CompositeMaterial);
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (MonteCarloCoreShader == null || CompositeShader == null) return;
            renderer.EnqueuePass(_mrtMonteCarloSubsurfaceScatteringPass);
        }

        protected override void Dispose(bool disposing)
        {
            CoreUtils.Destroy(MonteCarloCoreMaterial);
            _mrtMonteCarloSubsurfaceScatteringPass?.Dispose();
            _mrtMonteCarloSubsurfaceScatteringPass = null;
        }
    }
}