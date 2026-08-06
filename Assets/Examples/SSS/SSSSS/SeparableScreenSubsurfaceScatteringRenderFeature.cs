using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Examples.SSS.SSSSS
{
    public class SeparableScreenSubsurfaceScatteringRenderFeature : ScriptableRendererFeature
    {
        private class SeparableSubsurfaceScatteringRenderPass : ScriptableRenderPass
        {
            private SeparableScreenSubsurfaceScatteringRenderFeature _sssssRenderFeature;
            private FilteringSettings _sssssFilteringSettings =  new FilteringSettings(RenderQueueRange.opaque);
            private readonly ShaderTagId _sssssScatteringDiffuse = new ShaderTagId("Separable Subsurface Scattering Direct Diffuse");
            private readonly ShaderTagId _sssssFinalBlendId = new ShaderTagId("Separable Subsurface Scattering Final Blend");
            private readonly int _separableSubsurfaceDirectDiffuseRTID = Shader.PropertyToID("_SeparableSubsurfaceDirectDiffuseRT");
            private readonly int _separableSurfaceScaleID = Shader.PropertyToID("_SeparableSurfaceScale");
            private readonly int _gaussianKernelID = Shader.PropertyToID("_GaussianKernel");
            private readonly int _gaussianKernelNumID = Shader.PropertyToID("_GaussianKernelNum");

            //private readonly int _nSamplesShaderID = Shader.PropertyToID("_nSamples");
            private readonly int _separableSubsurfaceScatteringXAxisRTID = Shader.PropertyToID("_SeparableSubsurfaceScatteringXAxisRT");
            private readonly int _separableSubsurfaceScatteringRTID = Shader.PropertyToID("_SeparableSubsurfaceScatteringRT");

            private RTHandle _sssssDirectDiffuseRT;  // Pass 1 输出的直接光的 diffuse RT， 交给 SSS Pass 生成 SSS RT
            private RTHandle _sssssXAxisRT;            // Pass 2 要在 X 轴积分 1 次，在 Y 轴积分 1 次，需要一张临时 RT
            private RTHandle _sssssRT;                   // Pass 2 SSS 层 输出的 RT
            public SeparableSubsurfaceScatteringRenderPass(SeparableScreenSubsurfaceScatteringRenderFeature sssssRenderFeature)
            {
                this._sssssRenderFeature = sssssRenderFeature;
                this.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
            }
            
            public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
            {
                // 获取相机的配置
                RenderTextureDescriptor descriptor = renderingData.cameraData.cameraTargetDescriptor;
                descriptor.colorFormat = RenderTextureFormat.DefaultHDR;  //颜色用普通的 srgb
                descriptor.depthBufferBits = 0;  //???、
                
                RenderingUtils.ReAllocateIfNeeded(ref _sssssDirectDiffuseRT, descriptor, FilterMode.Bilinear,TextureWrapMode.Clamp, name: "Subsurface Scattering Direct Diffuse RT");
                RenderingUtils.ReAllocateIfNeeded(ref _sssssXAxisRT, descriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "Subsurface Scattering X Axis RT");
                RenderingUtils.ReAllocateIfNeeded(ref _sssssRT, descriptor, FilterMode.Bilinear, TextureWrapMode.Clamp, name: "Subsurface Scattering RT");
            }
            
            // ==================================
            // Pass 1 :Direct Diffuse 只输出 直接光的 diffuse 到 _sssDirectDiffuseRT
            // ==================================
            private void ExecuteDirectDiffusePass(ref ScriptableRenderContext context, ref CommandBuffer cmd, ref RenderingData renderingData)
            {
                // 按默认的渲染顺序，只给 opaque 的物体执行
                SortingCriteria sortingCriteria = renderingData.cameraData.defaultOpaqueSortFlags;
                DrawingSettings sssDirectDiffuseDrawSettings = CreateDrawingSettings(_sssssScatteringDiffuse, ref renderingData, sortingCriteria);
                
                RTHandle depthTargetHandle = renderingData.cameraData.renderer.cameraDepthTargetHandle;
                cmd.SetRenderTarget(_sssssDirectDiffuseRT, depthTargetHandle);
                cmd.ClearRenderTarget(false, true, Color.black);
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                context.DrawRenderers(renderingData.cullResults, ref sssDirectDiffuseDrawSettings, ref _sssssFilteringSettings);
            }
            
            // ==================================
            // Pass 2 :Separable SSS 只输出 SSS
            // ==================================
            private void ExecuteSeparableSubsurfaceScatteringPass(ref ScriptableRenderContext context, ref CommandBuffer cmd, ref RenderingData renderingData)
            {
                cmd.SetGlobalFloat(_separableSurfaceScaleID, _sssssRenderFeature.separableSurfaceScale);
                //cmd.SetGlobalInt(_nSamplesShaderID, _sssssRenderFeature._nSamples);
                cmd.SetGlobalInt(_gaussianKernelNumID, _sssssRenderFeature.gaussianKernelNum);
                cmd.SetGlobalVectorArray(_gaussianKernelID, _sssssRenderFeature._kernelArray);

                // 把 Pass 1 画好的 Diffuse RT 传给 SSSSS Pass 2, 开始画 X Axis 的积分
                cmd.SetGlobalTexture(_separableSubsurfaceDirectDiffuseRTID, _sssssDirectDiffuseRT);
                CoreUtils.DrawFullScreen(cmd, _sssssRenderFeature._separableSubsurfaceScatteringMaterial, _sssssXAxisRT, null, 0);
                
                // 把 X Axis 画好的传给 SSSSS Pass 2, 开始画 Y Axis 的积分
                cmd.SetGlobalTexture(_separableSubsurfaceScatteringXAxisRTID, _sssssXAxisRT);
                CoreUtils.DrawFullScreen(cmd, _sssssRenderFeature._separableSubsurfaceScatteringMaterial, _sssssRT, null, 1);
            }
            
            // ==================================
            // Pass 3 :混合高光、环境光、SSS
            // ==================================
            private void ExecuteFinalBlendPass(ref ScriptableRenderContext context, ref CommandBuffer cmd, ref RenderingData renderingData)
            {
                RTHandle colorTargetHandle = renderingData.cameraData.renderer.cameraColorTargetHandle;
                RTHandle depthTargetHandle = renderingData.cameraData.renderer.cameraDepthTargetHandle;

                cmd.SetGlobalTexture(_separableSubsurfaceScatteringRTID, _sssssRT);
                cmd.SetRenderTarget(colorTargetHandle, depthTargetHandle);
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                
                SortingCriteria sorting = renderingData.cameraData.defaultOpaqueSortFlags;  
                DrawingSettings finalBlendDrawSettings = CreateDrawingSettings(_sssssFinalBlendId, ref renderingData, sorting);
                context.DrawRenderers(renderingData.cullResults, ref finalBlendDrawSettings, ref _sssssFilteringSettings);
            }
            
            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
            {
                CommandBuffer cmd = CommandBufferPool.Get("3 Pass SSSSS Feature");
                
                ExecuteDirectDiffusePass(ref context, ref cmd, ref renderingData);
                
                ExecuteSeparableSubsurfaceScatteringPass(ref context, ref cmd, ref renderingData);
                
                ExecuteFinalBlendPass(ref context, ref cmd, ref renderingData);
                
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }

            public void Dispose()
            {
                _sssssDirectDiffuseRT?.Release();
                _sssssXAxisRT?.Release();
                _sssssRT?.Release();
            }
        }
        
        [SerializeField] private Shader separableSubsurfaceScatteringShader;
        [SerializeField] public float separableSurfaceScale = 1.0f;  // 模型的缩放大小，用于巨人和正常人
        [SerializeField] public int gaussianKernelNum = 25;         // 采样点的个数
        //[SerializeField] public Vector3 falloff = new Vector3(1.0f, 0.37f, 0.3f); // 默认近似皮肤
        //[SerializeField] public Vector3 strength = new Vector3(0.233f, 0.41f, 0.28f);

        //private int _nSamples = 16;
        private Vector4[] _kernelArray;
        private Material _separableSubsurfaceScatteringMaterial;
        private SeparableSubsurfaceScatteringRenderPass _separableSubsurfaceScatteringRenderPass;

        public override void Create()
        {
            if (separableSubsurfaceScatteringShader == null) return;
            _kernelArray = new Vector4[gaussianKernelNum];
    
            // 【核心参数】
            // falloff: 决定红光跑得远，绿蓝光跑得近（Jimenez 的真理）
            Vector3 falloff = new Vector3(1.0f, 0.37f, 0.3f); 
            // strength: 因为我们接下来要在 Shader 里改成“前置 Albedo”，
            // SSS 阶段只负责纯净的物理模糊，绝不能二次染色，所以这里必须设为 1.0！
            Vector3 strength = new Vector3(0.232f, 0.9f, 0.8f); 

            // 调用你写好的黎曼和生成器！
            SeparableScreenSubsurfaceScatteringDiffusionProfile.CalculateKernel(
                _kernelArray, 
                gaussianKernelNum, 
                strength, 
                falloff
            );
 
            //SeparableScreenSubsurfaceScatteringDiffusionProfile.CalculateKernel(_kernelArray, 16, strength, falloff);
            _separableSubsurfaceScatteringMaterial = CoreUtils.CreateEngineMaterial(separableSubsurfaceScatteringShader);
            _separableSubsurfaceScatteringRenderPass = new SeparableSubsurfaceScatteringRenderPass(this);
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (separableSubsurfaceScatteringShader == null) return;
            renderer.EnqueuePass(_separableSubsurfaceScatteringRenderPass);
        }

        protected override void Dispose(bool disposing)
        {
            CoreUtils.Destroy(_separableSubsurfaceScatteringMaterial);
            _separableSubsurfaceScatteringRenderPass?.Dispose();
        }
    }
}