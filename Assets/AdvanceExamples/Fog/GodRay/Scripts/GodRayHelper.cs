using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;

#if UNITY_EDITOR
using UnityEditor;
#endif

namespace AdvanceExamples.Fog.GodRay.Scripts
{
    [ExecuteAlways]
    public class GodRayHelper : MonoBehaviour
    {
#if UNITY_EDITOR
        private enum DepthResolution
        {
            _64 = 64,
            _128 = 128,
            _256 = 256,
            _512 = 512,
            _1024 = 1024,
        }
    
        [Header("Bake Settings")]
        private DepthResolution _resolution = DepthResolution._512;
    
        // =============================================================================================

        private static readonly int _godRayCookieMaskId = Shader.PropertyToID("_CookieMask");
        public static readonly int GodRayCookieMaskResolution = 1024;
        
        private int Id { get; set; }
        private MaterialPropertyBlock Mpb { get; set; }
        public RTHandle ShadowRt { get; private set; }
        public bool NeedsRealtimeShadow { get; private set; }         // 状态标识：当前插槽是否空着？

        private bool _isUsingRealtimeRt = false;
        private bool _isInitialized = false; // 确保启动时至少赋一次值
#endif
    
        public enum GodRayType
        {
            Large = 0,
            Mini = 1
        }
        [field: SerializeField]
        public GodRayType RayType { get; private set; } = GodRayType.Mini;
        public MeshRenderer Renderer { get; private set;  }
        public static readonly List<GodRayHelper> ActiveGodRays = new List<GodRayHelper>();
    
        public static bool HasAnyMiniGodRay()
        {
            foreach (var ray in ActiveGodRays)
                if (ray != null && ray.isActiveAndEnabled && ray.RayType == GodRayType.Mini)
                    return true;
        
            return false;
        }
    
        public static bool HasAnyGodRay()
        {
            foreach (var ray in ActiveGodRays)
                if (ray != null && ray.isActiveAndEnabled)
                    return true;
        
            return false;
        }
    
        private void DetectRayType()
        {
            if (Renderer == null || Renderer.sharedMaterial == null) return;
            Material mat = Renderer.sharedMaterial;
        
            if (mat.FindPass("GodRayMiniCylinder") != -1)
                RayType = GodRayType.Mini;
            else if(mat.FindPass("GodRayLargeCylinder") != -1)
                RayType = GodRayType.Large;
        }
    
        public bool IsMiniGodRayAndCameraInside(Vector3 cameraWorldPos)
        {
            if (RayType != GodRayType.Mini) return false;

            // 转换到光柱本地坐标系
            Vector3 p = transform.InverseTransformPoint(cameraWorldPos);
            // 扩大一下半径
            float margin = 0.2f;
            float expandedRadius = 1.9f;
        
            bool insideHeight = p.y >= -margin && p.y <= 1.0f + margin;
            bool insideRadius = (p.x * p.x + p.z * p.z) <= expandedRadius;
            return insideHeight && insideRadius;
        }
    
        private void OnEnable()
        {
#if UNITY_EDITOR
            Id = gameObject.GetInstanceID();
            Mpb = new MaterialPropertyBlock();

            ShadowRt = RTHandles.Alloc(
                width: GodRayCookieMaskResolution, 
                height: GodRayCookieMaskResolution, 
                slices: 1, 
                depthBufferBits: DepthBits.None, // 不需要自身深度，走全局共享
                colorFormat: GraphicsFormat.R32_SFloat, 
                filterMode: FilterMode.Point, 
                wrapMode: TextureWrapMode.Clamp, 
                useMipMap: false, 
                name: $"GodRayShadow_{Id}"
            );
#endif
            Renderer = GetComponent<MeshRenderer>();
            DetectRayType();
            if (!ActiveGodRays.Contains(this)) ActiveGodRays.Add(this);
        }

        private void OnDisable()
        {
#if UNITY_EDITOR
            SetCookieMaskBaked();
            ShadowRt.Release();
#endif
            ActiveGodRays.Remove(this);
        }
    
    
    
#if UNITY_EDITOR
        private void Update()
        {
            if (Renderer == null || Renderer.sharedMaterial == null) return;
            DetectRayType();
            // 探测材质插槽, 如果没图，就需要实时阴影；有图就不需要！
            Texture bakedTex = Renderer.sharedMaterial.GetTexture(_godRayCookieMaskId);
            NeedsRealtimeShadow = (bakedTex == null);
        }

        public void SetCookieMaskRt()
        {
            // 如果已经在实时模式了，直接 0 开销早退，绝不碰 Renderer！
            if (_isInitialized && _isUsingRealtimeRt) return;
            Renderer.GetPropertyBlock(Mpb);
            Mpb.SetTexture(_godRayCookieMaskId, ShadowRt);
            Renderer.SetPropertyBlock(Mpb);
            _isUsingRealtimeRt = true;
            _isInitialized = true;
        }
        public void SetCookieMaskBaked()
        {
            // 如果已经在烘焙模式了，直接 0 开销早退，保住 SRP Batcher 缓存！
            if (_isInitialized && !_isUsingRealtimeRt) return;
            Renderer.GetPropertyBlock(Mpb);
            Mpb.Clear();
            Renderer.SetPropertyBlock(Mpb);
            _isUsingRealtimeRt = false;
            _isInitialized = true;
        }
#endif
    
    
#if UNITY_EDITOR

        // =============================================================================================
    
        //[Header("Cookie Softening (Gaussian Blur)")]
        //[Range(0, 128)] public int blurRadius = 0;   // texel 单位；0 = 关闭
        //public float blurSigma = 0f;                // 0 = 自动（= radius / 3）

        private string _savePath;
    
        public void SampleDepthTex()
        {
            try
            {
                // 检查参数的合法性
                if (!CheckValidParameters()) return;
            
                // 保存到磁盘
                SaveDepthTexture();

                // 自动赋值材质
                AutoAssignBakedTextureToMaterial();
                EditorUtility.DisplayDialog("生成深度图", $"已保存到：{_savePath}", "OK");
            }
            catch (Exception e)
            {
                EditorUtility.DisplayDialog("深度图出错啦", e.Message + "\n" + e.StackTrace, "OK");
            }
        }

        private bool CheckValidParameters()
        {
            if (GetComponent<MeshRenderer>() == null)
            {
                EditorUtility.DisplayDialog("生成深度图失败", "需要挂在带 MeshRenderer 的物体上", "OK");
                return false;
            }

            if (ShadowRt == null || ShadowRt.rt == null)
            {
                EditorUtility.DisplayDialog("生成深度图失败", "实时的 ShadowRt 尚未生成！请确保在 Scene/Game 视图能看到光柱阴影后，再点击烘焙。", "OK");
                return false;
            }
        

            _savePath = "Assets/AdvanceExamples/Fog/GodRay/Textures/T_CookieMask_" + gameObject.name.Replace(" ", "").Replace("0", "_0")  + ".exr";

            string directory = Path.GetDirectoryName(_savePath);
            if (string.IsNullOrEmpty(directory) || !Directory.Exists(directory))
            {
                EditorUtility.DisplayDialog("生成深度图失败", $"目录不存在：{directory}", "OK");
                return false;
            }
        
            return true;
        }

        private void SaveDepthTexture()
        {
            RenderTexture depthRt = ShadowRt.rt;
            // 异步读取回 Texture
            var req = AsyncGPUReadback.Request(depthRt);
            req.WaitForCompletion();
        
            Texture2D depthTex = new Texture2D(depthRt.width, depthRt.height, TextureFormat.RFloat, false);
            depthTex.SetPixelData(req.GetData<byte>(), 0);
            depthTex.Apply();

            // 保存到磁盘
            byte[] bytes = depthTex.EncodeToEXR(Texture2D.EXRFlags.None);
            File.WriteAllBytes(_savePath, bytes);
            DestroyImmediate(depthTex);
            AssetDatabase.ImportAsset(_savePath, ImportAssetOptions.ForceUpdate);

            // Unity 导入器设置
            var importer = AssetImporter.GetAtPath(_savePath) as TextureImporter ?? throw new InvalidOperationException($"无法获取 {_savePath} 的 TextureImporter");
            importer.sRGBTexture = false;
            importer.wrapMode = TextureWrapMode.Clamp;
            importer.filterMode = FilterMode.Point;
            importer.mipmapEnabled = false;
            importer.textureType = TextureImporterType.SingleChannel;
            // 关闭 alpha dilation，避免无物体处的 A 被邻近像素渗透
            importer.alphaSource = TextureImporterAlphaSource.FromInput;
            importer.alphaIsTransparency = false;

            // 显式指定 platform format 为 float，避免被压成 LDR (RGBA32) 导致精度丢失
            var platformSettings = importer.GetDefaultPlatformTextureSettings();
            platformSettings.format = TextureImporterFormat.R16;
            platformSettings.textureCompression = TextureImporterCompression.Uncompressed;
            platformSettings.overridden = true;
            importer.SetPlatformTextureSettings(platformSettings);

            importer.SaveAndReimport();
        }

        private void AutoAssignBakedTextureToMaterial()
        {
            AssetDatabase.ImportAsset(_savePath, ImportAssetOptions.ForceUpdate);

            Texture2D bakedTex = AssetDatabase.LoadAssetAtPath<Texture2D>(_savePath);
            if (bakedTex == null)
            {
                Debug.LogError($"[GodRay] 加载生成的贴图失败: {_savePath}");
                return;
            }

            if (Renderer != null && Renderer.sharedMaterial != null)
            {
                Material mat = Renderer.sharedMaterial;
                Undo.RecordObject(mat, "Assign Baked GodRay Cookie Mask");
                mat.SetTexture(_godRayCookieMaskId, bakedTex);
                EditorUtility.SetDirty(mat);
                SetCookieMaskBaked();
            }
        }

        // 分离式高斯模糊：先横后竖两趟，成本 O(2 × kSize × N²) 而非 O(kSize² × N²)
        // Clamp 边界（跟 shader 端 Point/Clamp 采样对应）
        private static void GaussianBlurSeparable(float[] pixels, int width, int height, int radius, float sigma)
        {
            int kSize = radius * 2 + 1;
            float[] kernel = new float[kSize];
            float sum = 0f;
            for (int i = 0; i < kSize; i++)
            {
                int x = i - radius;
                kernel[i] = Mathf.Exp(-(x * x) / (2f * sigma * sigma));
                sum += kernel[i];
            }
            for (int i = 0; i < kSize; i++) kernel[i] /= sum;

            float[] temp = new float[pixels.Length];

            // Horizontal pass: temp = blur_x(pixels)
            for (int y = 0; y < height; y++)
            {
                int rowStart = y * width;
                for (int x = 0; x < width; x++)
                {
                    float acc = 0f;
                    for (int k = 0; k < kSize; k++)
                    {
                        int sx = Mathf.Clamp(x + k - radius, 0, width - 1);
                        acc += pixels[rowStart + sx] * kernel[k];
                    }
                    temp[rowStart + x] = acc;
                }
            }

            // Vertical pass: pixels = blur_y(temp)
            for (int y = 0; y < height; y++)
            {
                for (int x = 0; x < width; x++)
                {
                    float acc = 0f;
                    for (int k = 0; k < kSize; k++)
                    {
                        int sy = Mathf.Clamp(y + k - radius, 0, height - 1);
                        acc += temp[sy * width + x] * kernel[k];
                    }
                    pixels[y * width + x] = acc;
                }
            }
        }
#endif
    }

#if UNITY_EDITOR
    [CustomEditor(typeof(GodRayHelper))]
    public class GodRayDepthSamplerExrAdvanceUtilsEditor : Editor
    {
        public override void OnInspectorGUI()
        {
            DrawDefaultInspector();
    
            EditorGUILayout.Space();
            var t = (GodRayHelper)target;
    
            string message1 = "当前状态：<color=#00BFFF>【实时预览模式】</color>\n" +
                              "<color=#FF4500>没有分配深度图！记得烘焙深度图并保存！</color>";
            string message2 = "当前状态：<color=#32CD32>【离线烘焙模式】</color>\n" +
                              "<color=#A9A9A9>如需恢复实时预览，请前往材质球，将遮罩插槽清空</color>";
    
            GUIStyle richHelpBoxStyle = new GUIStyle(EditorStyles.helpBox)
            {
                richText = true,
                fontSize = 12,
                padding = new RectOffset(10, 10, 8, 8) // 稍微撑开一点内边距，更美观
            };

            GUIContent content = new GUIContent(
                t.NeedsRealtimeShadow ? message1 : message2,
                EditorGUIUtility.IconContent(t.NeedsRealtimeShadow ? "console.erroricon" : "console.infoicon").image
            );
    
            EditorGUILayout.LabelField(content, richHelpBoxStyle);
            EditorGUILayout.Space();  
    
            if (GUILayout.Button("烘焙 Cookie Mask", GUILayout.Height(30)))
            {
                t.SampleDepthTex();
            }
        }
    }
#endif
}