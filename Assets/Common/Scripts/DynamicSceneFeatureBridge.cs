using System.Collections.Generic;
using UnityEngine.Rendering.Universal;

namespace Common.Scripts
{
    [DisallowMultipleRendererFeature("[Global] Dynamic Scene Feature Bridge")]
    public class DynamicSceneFeatureBridge : ScriptableRendererFeature
    {
        public override void Create()
        {
            // 空实现，生命周期由各场景内部的 Feature 自身管理
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            // 获取当前场景注册的 Feature 宿主
            SceneFeatureHost host = SceneFeatureHost.ActiveHost;
            if (host == null) return;

            List<ScriptableRendererFeature> features = host.GetFeatures();
            if (features == null || features.Count == 0) return;

            // 依次把当前场景的 Feature 塞入当前相机的渲染队列（Game 与 Scene 视口通用）
            for (int i = 0; i < features.Count; i++)
            {
                var feature = features[i];
                if (feature != null && feature.isActive)
                    feature.AddRenderPasses(renderer, ref renderingData);
            }
        }
    }
}