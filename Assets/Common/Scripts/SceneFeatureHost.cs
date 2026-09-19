using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace Common.Scripts
{
    [ExecuteAlways]
    public class SceneFeatureHost : MonoBehaviour
    {
        public static SceneFeatureHost ActiveHost { get; private set; }
        
        [SerializeField] private ScriptableRendererData _rendererData;
        //[SerializeField] private List<ScriptableRendererFeature> customFeatures = new();

        private readonly List<ScriptableRendererFeature> _activeFeatures = new();

        private void OnEnable()
        {
            ActiveHost = this;
            BuildFeatures();
        }

        private void OnDisable()
        {
            if (ActiveHost != this) return;
            
            ActiveHost = null;
            _activeFeatures.Clear();
        }

        private void OnValidate()
        {
            BuildFeatures();
        }

        private void BuildFeatures()
        {
            _activeFeatures.Clear();

            // 收集 RendererData 里的 Features
            if (_rendererData != null && _rendererData.rendererFeatures != null)
                foreach (var f in _rendererData.rendererFeatures)
                    if (f != null && !_activeFeatures.Contains(f))
                        _activeFeatures.Add(f);
                
            

            /*
            // 收集手动指定的 Features
            if (customFeatures != null)
            {
                foreach (var f in customFeatures)
                {
                    if (f != null && !_allActiveFeatures.Contains(f))
                        _allActiveFeatures.Add(f);
                }
            }*/

            //  Feature 的初始化
            foreach (var f in _activeFeatures)
                if (f != null)
                    f.Create();
        }

        public List<ScriptableRendererFeature> GetFeatures()
        {
            return _activeFeatures;
        }

    }
}