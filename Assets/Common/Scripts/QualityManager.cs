using UnityEditor;
using UnityEngine;

namespace Common.Scripts
{
    public enum QualityLevel
    {
        Low,
        Medium,
        High,
        Epic
    }
    
    public readonly struct QualityProfile
    {
        public readonly int ShaderLOD;
        public readonly float LodBias;
        public readonly int MaxLODLevel;
        public readonly int MipmapLimit;
        public QualityProfile(int shaderLOD, float lodBias, int maxLODLevel, int mipmapLimit)
        {
            ShaderLOD = shaderLOD;
            LodBias = lodBias;
            MaxLODLevel = maxLODLevel;
            MipmapLimit = mipmapLimit;
        }
    }
    
    [InitializeOnLoad]
    public static class QualityManager
    {
        private const string _qualityKey = "Editor_Selected_Quality_Level";
        
        public static QualityLevel CurrentQuality { get; private set; } = QualityLevel.Epic;

        static QualityManager()
        {
            // 从本地恢复上次勾选的画质并立即生效
            QualityLevel savedLevel = (QualityLevel)EditorPrefs.GetInt(_qualityKey, (int)QualityLevel.High);
            ApplyQuality(savedLevel);
        }
        
        public static QualityProfile GetProfile(QualityLevel level)
        {
            return level switch
            {
                //                           ShaderLOD | lodBias | maxLOD | mipmapLimit
                QualityLevel.Low      => new QualityProfile(300,       0.50f,   1,         1),
                QualityLevel.Medium => new QualityProfile(500,       0.85f,   0,         0),
                QualityLevel.High     => new QualityProfile(800,       1.20f,   0,         0),
                QualityLevel.Epic      => new QualityProfile(1000,      1.50f,   0,         0),
                _                         => new QualityProfile(800,       1.20f,   0,         0)
            };
        }
        
        // =========================================================================
        // 顶部菜单栏定义
        // =========================================================================
        [MenuItem("Quality/Low - LOD 300", false, 1)]
        public static void SetLowQuality() => ApplyQuality(QualityLevel.Low);

        [MenuItem("Quality/Medium - LOD 500", false, 2)]
        public static void SetMediumQuality() => ApplyQuality(QualityLevel.Medium);

        [MenuItem("Quality/High - LOD 800", false, 3)]
        public static void SetHighQuality() => ApplyQuality(QualityLevel.High);

        [MenuItem("Quality/Epic - LOD 1000", false, 4)]
        public static void SetUltraQuality() => ApplyQuality(QualityLevel.Epic);

        // =========================================================================
        // 菜单勾选状态校验 
        // =========================================================================
        [MenuItem("Quality/Low - LOD 300", true)]
        public static bool ValidateLow() => CheckMenu(QualityLevel.Low, "Quality/Low - LOD 300");

        [MenuItem("Quality/Medium - LOD 500", true)]
        public static bool ValidateMedium() => CheckMenu(QualityLevel.Medium, "Quality/Medium - LOD 500");

        [MenuItem("Quality/High - LOD 800", true)]
        public static bool ValidateHigh() => CheckMenu(QualityLevel.High, "Quality/High - LOD 800");

        [MenuItem("Quality/Epic - LOD 1000", true)]
        public static bool ValidateUltra() => CheckMenu(QualityLevel.Epic, "Quality/Epic - LOD 1000");

        
        private static bool CheckMenu(QualityLevel level, string menuPath)
        {
            QualityLevel current = (QualityLevel)EditorPrefs.GetInt(_qualityKey, (int)QualityLevel.High);
            Menu.SetChecked(menuPath, current == level);
            return true;
        }

        // =========================================================================
        // 核心切换逻辑
        // =========================================================================
        private static void ApplyQuality(QualityLevel qualityLevel)
        {
            QualityProfile quality = GetProfile(qualityLevel);
            
            Shader.globalMaximumLOD = quality.ShaderLOD;
            
            // 设置全局几何 & 贴图
            QualitySettings.lodBias = quality.LodBias;
            QualitySettings.maximumLODLevel = quality.MaxLODLevel;
            QualitySettings.globalTextureMipmapLimit = quality.MipmapLimit;
            
            // 保存 Prefs
            CurrentQuality = qualityLevel;
            EditorPrefs.SetInt(_qualityKey, (int)qualityLevel);

            // 强制即时刷新视口
            SceneView.RepaintAll();
            UnityEditorInternal.InternalEditorUtility.RepaintAllViews();
            Debug.Log($"<color=#00FF7F>[Quality Switch] OK ➔ Shader LOD: {quality.ShaderLOD}</color>");
        }
        
        public static bool IsAtLeast(QualityLevel minLevel)
        {
            return CurrentQuality >= minLevel;
        }

    }
}