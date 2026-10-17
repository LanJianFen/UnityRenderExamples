using System;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace AdvanceExamples.Skin.MonteCarloSubsurfaceScattering.Deferred.Scripts
{
    [DisallowMultipleRendererFeature("[Subsurface] Deferred Monte Carlo Subsurface Scattering RenderFeature")]

    public class DeferredMonteCarloSubsurfaceScatteringRenderFeature : ScriptableRendererFeature
    {
        class DeferredMonteCarloSubsurfaceScatteringPass : ScriptableRenderPass
        {
            // profiling sampler
            private readonly ProfilingSampler _profilingSampler = new ("Deferred Monte Carlo Subsurface");
        
            // Material
            private readonly Material _scatteringMaterial;
            private readonly Material _lightingMaterial;
            
            // setting
            private Settings _settings;

            // RT
            private readonly RenderTargetIdentifier[] _mrt = new RenderTargetIdentifier[2];
            private RTHandle _diffuseRt, _specularRt, _scatteredRt;
            private static readonly int _diffuseRtId   = Shader.PropertyToID("_MonteCarloSubsurfaceDiffuseRt");
            private static readonly int _specularRtId  = Shader.PropertyToID("_MonteCarloSubsurfaceSpecularRt");
            private static readonly int _scatteredRtId = Shader.PropertyToID("_MonteCarloSubsurfaceScatteredRt");
        
            // Params
            private static readonly int _rcpScatteringDistanceParams = Shader.PropertyToID("_RcpMonteCarloScatteringDistance");
            private static readonly int _scatteringScaleParams = Shader.PropertyToID("_MonteCarloScatteringScale");
            private static readonly int _sampleNumParams = Shader.PropertyToID("_MonteCarloScatteringSampleNum");
            private static readonly int _baseColorScatteringWeightParams = Shader.PropertyToID("_MonteCarloBaseColorScatteringWeight");

        
            public void Setup(Settings settings)
            {
                _settings = settings;
                renderPassEvent = settings.RenderPassEvent;
            }
        
            public DeferredMonteCarloSubsurfaceScatteringPass(Material scatteringMaterial, Material lightingMaterial, Settings settings)
            {
                _scatteringMaterial = scatteringMaterial;
                _lightingMaterial = lightingMaterial;
                Setup(settings);
            }
        

            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                var desc = renderingData.cameraData.cameraTargetDescriptor;
                desc.depthStencilFormat = GraphicsFormat.None;
                desc.msaaSamples     = 1;
                desc.graphicsFormat = GraphicsFormat.R16G16B16A16_SFloat;

                RenderingUtils.ReAllocateIfNeeded(ref _diffuseRt,   desc, FilterMode.Point,    TextureWrapMode.Clamp, name: "_MonteCarloSubsurfaceDiffuseRt");
                RenderingUtils.ReAllocateIfNeeded(ref _specularRt,  desc, FilterMode.Point,    TextureWrapMode.Clamp, name: "_MonteCarloSubsurfaceSpecularRt");
                RenderingUtils.ReAllocateIfNeeded(ref _scatteredRt, desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "_MonteCarloSubsurfaceScatteredRt");
            
                _mrt[0] = _diffuseRt.nameID;
                _mrt[1] = _specularRt.nameID;
            }

            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                var cmd = CommandBufferPool.Get();
                using (new ProfilingScope(cmd, _profilingSampler))
                {
                    // [1] 皮肤光照：MRT，每帧必须清空（非皮肤像素会 discard）

                    RTHandle depthStencilRt = renderingData.cameraData.renderer.cameraDepthTargetHandle;
                    RTHandle cameraColorRt = renderingData.cameraData.renderer.cameraColorTargetHandle;
                
                    cmd.SetGlobalFloat(_baseColorScatteringWeightParams, _settings.BaseColorScatteringWeight);
                    CoreUtils.SetRenderTarget(cmd, _mrt, depthStencilRt, ClearFlag.Color, Color.clear);
                    CoreUtils.DrawFullScreen(cmd, _lightingMaterial, shaderPassId: 0);
                
                    // [2] 散射：_BlitTexture = _SkinDiffuse
                    cmd.SetGlobalTexture(_diffuseRtId, _diffuseRt);
                    Color sssDistance = _settings.ScatteringDistance;
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
                    cmd.SetGlobalVector(_rcpScatteringDistanceParams, rcpSubsurfaceScatteringDistanceParams);
                    cmd.SetGlobalFloat(_scatteringScaleParams, _settings.ScatteringScale);
                    cmd.SetGlobalInt(_sampleNumParams, _settings.SampleNum);
                    CoreUtils.SetRenderTarget(cmd, _scatteredRt, ClearFlag.Color, Color.clear);
                    Blitter.BlitCameraTexture(cmd, _diffuseRt, _scatteredRt, _scatteringMaterial, _settings.ScatteringPass);

                    // [3] 合成：叠加回相机颜色（就是 GBuffer3）
                    cmd.SetGlobalTexture(_scatteredRtId, _scatteredRt);
                    cmd.SetGlobalTexture(_specularRtId,  _specularRt);
                    CoreUtils.SetRenderTarget(cmd, cameraColorRt);
                    CoreUtils.DrawFullScreen(cmd, _lightingMaterial, shaderPassId: 1);
                }
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }

            public void Dispose()
            {
                _diffuseRt?.Release();
                _specularRt?.Release();
                _scatteredRt?.Release();
            }
        }
    
        [Serializable]
        public class Settings
        {
            public RenderPassEvent RenderPassEvent = RenderPassEvent.AfterRenderingDeferredLights;
            [ColorUsage(false, true)] public Color ScatteringDistance = new (15.0f, 5.0f, 2.0f, 1.0f);
            [Range(0f, 10f)] public float ScatteringScale = 1.0f;  // 模型的缩放大小，用于巨人和正常人
            [Range(0f, 1f)] public float BaseColorScatteringWeight = 0.5f;
            [Range(1, 32)] public int SampleNum = 16;
            public int   ScatteringPass = 0;
        }
        public Settings settings = new ();

        [HideInInspector] public Shader ScatteringShader;
        [HideInInspector] public Shader LightingShader;      // Hidden/Skin/DeferredLighting
        private Material _scatteringMaterial;      // 你的 McScattering
        private Material _lightingMat;
    
        private DeferredMonteCarloSubsurfaceScatteringPass _deferredMonteCarloSubsurfaceScatteringPass;

        public void OnValidate()
        {
            if (!isActive) return;
            
            if(ScatteringShader == null) ScatteringShader = Shader.Find("Advance Examples/SSS/MonteCarlo SSS Core");
            if(LightingShader == null)    LightingShader = Shader.Find("Advance Examples/SSS/Deferred MonteCarlo SSS Lighting");
            
            _deferredMonteCarloSubsurfaceScatteringPass   ?.Setup(settings);
        }
    
        public override void Create()
        {
            if (ScatteringShader == null || LightingShader == null) return;
            if (_scatteringMaterial == null)  _scatteringMaterial = CoreUtils.CreateEngineMaterial(ScatteringShader);
            if (_lightingMat == null) _lightingMat = CoreUtils.CreateEngineMaterial(LightingShader);
            _deferredMonteCarloSubsurfaceScatteringPass = new (_scatteringMaterial, _lightingMat, settings);
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (_deferredMonteCarloSubsurfaceScatteringPass == null || _scatteringMaterial == null || _lightingMat == null) return;
            renderer.EnqueuePass(_deferredMonteCarloSubsurfaceScatteringPass);
        }

        protected override void Dispose(bool disposing)
        {
            _deferredMonteCarloSubsurfaceScatteringPass?.Dispose();
            CoreUtils.Destroy(_scatteringMaterial);
            CoreUtils.Destroy(_lightingMat);
        }

    }
}