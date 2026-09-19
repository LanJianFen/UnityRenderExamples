using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;

namespace AdvanceExamples.Fog.GodRay.Scripts
{
    internal enum FogShape
    {
        Cone2D,
        Cone3D,
        Sphere3D,
        GodRayLargeCylinder3D,
        GodRayMiniCylinder3D,
    }

    public static class LocalVolumetricFogHelper
    {
        private static readonly Dictionary<FogShape, (string materialName, string shaderName)> FogConfig = new()
        {
            { FogShape.Cone2D,                      ("ConeFog2D",   "Advance Examples/Fog/Geometry Fog/2D Cone Geometry Fog") },
            { FogShape.Cone3D,                      ("ConeFog3D",   "Advance Examples/Fog/Geometry Fog/3D Cone Geometry Fog")},   
            { FogShape.Sphere3D,                    ("SphereFog3D", "Advance Examples/Fog/Geometry Fog/3D Sphere Geometry Fog") },   
            { FogShape.GodRayLargeCylinder3D,  ("GodRayCylinder3D_", "Advance Examples/Fog/God Ray/God Ray Large Cylinder 3D") },
            { FogShape.GodRayMiniCylinder3D,   ("GodRayMiniCylinder3D_", "Advance Examples/Fog/God Ray/God Ray Mini Cylinder 3D") }
        };  
    
        /// <summary>
        /// UNITY EDITOR 用来创建局部体积雾gameObject的菜单
        /// </summary>
        // 创建一个2D三角形，给它挂上面片的体积雾材质
        [MenuItem("GameObject/Create Other/2D Cone Fog", priority = 1)]
        static void Add2DTriangle()
        {

            (Material material, string number) = CreateMaterial(FogShape.Cone2D);
            if (material == null) return;
        
            // 新建一个 GameObject 并设置它的父物体为选中的物体
            GameObject parent = Selection.activeGameObject;
            GameObject goFog = new GameObject("cone fog 2d",  typeof(MeshFilter), typeof(MeshRenderer));
            goFog.transform.SetParent(parent? parent.transform : null, false);
            Selection.activeGameObject = goFog;

            goFog.GetComponent<MeshRenderer>().material = material;
            ConfigureFogRenderer(goFog.GetComponent<MeshRenderer>());

            // ========================================
            // 创建一个等腰直角三角形 ，高为 2 的Mesh ，赋值给 GameObject
            // ========================================
            Mesh triangleMesh = new Mesh();
            triangleMesh.vertices = new[]
            {
                new Vector3(0.0f, 0.0f, 0.0f),
                new Vector3(-1.0f, 1.0f, 0.0f),
                new Vector3(1.0f, 1.0f, 0.0f),
            };

            triangleMesh.uv = new Vector2[]
            {
                new Vector2(0.0f, 0.0f),
                new Vector2(-1.0f, 1.0f),
                new Vector2(1.0f, 1.0f),
            };

            triangleMesh.triangles = new int[] { 0, 1, 2, };
        
            goFog.GetComponent<MeshFilter>().sharedMesh = triangleMesh;
            goFog.transform.localScale = new Vector3(3, 10, 1);
        }
    
        // 创建一个8段圆锥（底面半径0.5，高2），给它挂上3D圆锥的体积雾材质
        [MenuItem("GameObject/Create Other/3D Cone Fog", priority = 1)]
        static void AddCone()
        {
            (Material material, string number) = CreateMaterial(FogShape.Cone3D);
            if (material == null) return;
        
            GameObject parent = Selection.activeGameObject;
            GameObject fog = new GameObject("cone fog 3d",  typeof(MeshFilter), typeof(MeshRenderer));
            fog.transform.SetParent(parent ? parent.transform : null, false);
            Selection.activeGameObject = fog;

            fog.GetComponent<MeshRenderer>().material = material;
            ConfigureFogRenderer(fog.GetComponent<MeshRenderer>());

            const int segments = 20;    // 圆锥底部由 segments 条边模拟这个圆
            const float radius = 0.5f;  // 底面半径
            const float height = 2f;    // 高

            // 圆锥总共是底面 segments 个顶点 + 尖端 1 个顶点
            Vector3[] vertices = new Vector3[1 + segments];

            vertices[0] = Vector3.zero; // 尖端（pivot）

            // 底面圆上的坐标是 ( r · cosθ, r · sinθ) 
            for (int i = 0; i < segments; i++)
            {
                float angle = i * 2f * Mathf.PI / segments;
                vertices[1 + i] = new Vector3(radius * Mathf.Cos(angle), height, radius * Mathf.Sin(angle));
            }

            // 侧面 segments 个三角形 + 底盖 segments - 2 个三角形
            int[] triangles = new int[segments * 3 + (segments - 2) * 3];
            int idx = 0;

            // 侧面（外法线）逆时针方向组织三角形
            for (int i = 0; i < segments; i++)
            {
                triangles[idx++] = 0;
                triangles[idx++] = 1 + i;
                triangles[idx++] = 1 + (i + 1) % segments;
            }

            // 底盖（外法线，+y 朝上，从下面看是 back face）
            for (int i = 0; i < segments - 2; i++)
            {
                triangles[idx++] = 1;
                triangles[idx++] = i + 3;
                triangles[idx++] = i + 2;
            }

            Mesh coneMesh = new Mesh();
            coneMesh.vertices  = vertices;
            coneMesh.triangles = triangles;

            fog.GetComponent<MeshFilter>().sharedMesh = coneMesh;
            fog.transform.localScale = new Vector3(6, 6, 6);
        }
    
        // 创建一个球体，给它挂上3D球体的体积雾材质
        [MenuItem("GameObject/Create Other/3D Sphere Fog", priority = 1)]
        static void AddSphere()
        {
            (Material material, string number) = CreateMaterial(FogShape.Sphere3D);
            if (material == null) return;
        
            GameObject parent = Selection.activeGameObject;
            // UNITY 自带的 Sphere Mesh
            GameObject fog = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            fog.transform.localScale = new Vector3(10, 10, 10);
            fog.GetComponent<MeshRenderer>().material = material;
            ConfigureFogRenderer(fog.GetComponent<MeshRenderer>());

            Object.DestroyImmediate(fog.GetComponent<SphereCollider>());
            fog.name = "3d sphere fog";
            fog.transform.SetParent(parent ? parent.transform : null, false);
            Selection.activeGameObject = fog;

        }

        static void ConfigureFogRenderer(MeshRenderer mr)
        {
            mr.shadowCastingMode = ShadowCastingMode.Off;
            mr.receiveShadows = false;
            mr.lightProbeUsage = LightProbeUsage.Off;
            mr.reflectionProbeUsage = ReflectionProbeUsage.Off;
            mr.motionVectorGenerationMode = MotionVectorGenerationMode.ForceNoMotion;
        }

        static (Material, string) CreateMaterial(FogShape fogShape)
        {
            string sceneName = SceneManager.GetActiveScene().name;
            string materialDir = "Assets/AdvanceExamples/Fog/GodRay/Materials";
            string materialNamePrefix = "/M_" + FogConfig[fogShape].materialName;
        
            if (!AssetDatabase.IsValidFolder(materialDir))
            {
                EditorUtility.DisplayDialog("找不到材质路径", "找不到材质路径：" + materialDir, "OK");
                return (null, null);
            }

            // 找到最大的编号
            int index = 1;
            while (AssetDatabase.LoadAssetAtPath<Material>(materialDir + materialNamePrefix + index.ToString("D2") + ".mat") != null)
                index++;

            string number = index.ToString("D2");
            string materialName = materialDir + materialNamePrefix + number + ".mat";

            Shader fogShader = Shader.Find(FogConfig[fogShape].shaderName);
            Material material = new Material(fogShader);

            AssetDatabase.CreateAsset(material, materialName);
            AssetDatabase.SaveAssets();
            return (material, number);
        }

        
        // 创建一个8段圆柱（底面半径1，高1）
        [MenuItem("GameObject/Create Other/3D Cylinder Large God Ray Fog", priority = 1)]
        static void AddCylinder()
        {
            (Material material, string number) = CreateMaterial(FogShape.GodRayLargeCylinder3D);
            if (material == null) return;
        
            GameObject parent = Selection.activeGameObject;
            GameObject fog = new GameObject("God Ray Cylinder Large 3D " + number,  typeof(MeshFilter), typeof(MeshRenderer));
            fog.transform.SetParent(parent ? parent.transform : null, false);
            Selection.activeGameObject = fog;

            fog.GetComponent<MeshRenderer>().material = material;
            ConfigureFogRenderer(fog.GetComponent<MeshRenderer>());

            fog.AddComponent<GodRayHelper>();
            const int segments = 20;    // 圆柱侧面由 segments 条边模拟
            const float radius = 1f;    // 底面半径
            const float height = 1f;    // 高

            // 底面圆 segments 个顶点 + 顶面圆 segments 个顶点
            // 索引区间：[0, segments) 底圈，[segments, 2*segments) 顶圈
            Vector3[] vertices = new Vector3[2 * segments];

            // 底面圆上的坐标是 ( r · cosθ, r · sinθ)
            for (int i = 0; i < segments; i++)
            {
                float angle = i * 2f * Mathf.PI / segments;
                float x = radius * Mathf.Cos(angle);
                float z = radius * Mathf.Sin(angle);
                vertices[i]            = new Vector3(x, 0f,     z); // 底圈
                vertices[segments + i] = new Vector3(x, height, z); // 顶圈
            }

            // 侧面 segments 个 quad = 2*segments 个三角形
            // 顶盖 + 底盖 各 (segments - 2) 个三角形
            int[] triangles = new int[segments * 6 + (segments - 2) * 6];
            int idx = 0;

            // 侧面（外法线朝外）
            for (int i = 0; i < segments; i++)
            {
                int b0 = i;
                int b1 = (i + 1) % segments;
                int t0 = segments + i;
                int t1 = segments + (i + 1) % segments;

                // quad = b0, b1, t1, t0  拆成两个三角形（外法线朝外，Unity CW = front）
                triangles[idx++] = b0;
                triangles[idx++] = t1;
                triangles[idx++] = b1;

                triangles[idx++] = b0;
                triangles[idx++] = t0;
                triangles[idx++] = t1;
            }

            // 顶盖（外法线 +y，从 top[0] 扇形三角化）
            for (int i = 0; i < segments - 2; i++)
            {
                triangles[idx++] = segments;
                triangles[idx++] = segments + i + 2;
                triangles[idx++] = segments + i + 1;
            }

            // 底盖（外法线 -y，绕序反向）
            for (int i = 0; i < segments - 2; i++)
            {
                triangles[idx++] = 0;
                triangles[idx++] = i + 1;
                triangles[idx++] = i + 2;
            }

            Mesh cylinderMesh = new Mesh();
            cylinderMesh.vertices  = vertices;
            cylinderMesh.triangles = triangles;
            cylinderMesh.RecalculateNormals();
            cylinderMesh.RecalculateBounds();

            fog.GetComponent<MeshFilter>().sharedMesh = cylinderMesh;
            fog.transform.localScale = new Vector3(6, 6, 6);
        }
    
        // 创建一个8段圆柱（底面半径1，高1）
        [MenuItem("GameObject/Create Other/3D Cylinder Mini God Ray Fog", priority = 1)]
        static void AddMiniCylinder()
        {
            (Material material, string number) = CreateMaterial(FogShape.GodRayMiniCylinder3D);
            if (material == null) return;
        
            GameObject parent = Selection.activeGameObject;
            GameObject fogObj = new GameObject("God Ray Cylinder Mini 3D " + number,  typeof(MeshFilter), typeof(MeshRenderer));
            fogObj.transform.SetParent(parent ? parent.transform : null, false);
            Selection.activeGameObject = fogObj;

            fogObj.GetComponent<MeshRenderer>().material = material;
            ConfigureFogRenderer(fogObj.GetComponent<MeshRenderer>());

            fogObj.AddComponent<GodRayHelper>();
            const int segments = 20;    // 圆柱侧面由 segments 条边模拟
            const float radius = 1f;    // 底面半径
            const float height = 1f;    // 高

            // 底面圆 segments 个顶点 + 顶面圆 segments 个顶点
            // 索引区间：[0, segments) 底圈，[segments, 2*segments) 顶圈
            Vector3[] vertices = new Vector3[2 * segments];

            // 底面圆上的坐标是 ( r · cosθ, r · sinθ)
            for (int i = 0; i < segments; i++)
            {
                float angle = i * 2f * Mathf.PI / segments;
                float x = radius * Mathf.Cos(angle);
                float z = radius * Mathf.Sin(angle);
                vertices[i]            = new Vector3(x, 0f,     z); // 底圈
                vertices[segments + i] = new Vector3(x, height, z); // 顶圈
            }

            // 侧面 segments 个 quad = 2*segments 个三角形
            // 顶盖 + 底盖 各 (segments - 2) 个三角形
            int[] triangles = new int[segments * 6 + (segments - 2) * 6];
            int idx = 0;

            // 侧面（外法线朝外）
            for (int i = 0; i < segments; i++)
            {
                int b0 = i;
                int b1 = (i + 1) % segments;
                int t0 = segments + i;
                int t1 = segments + (i + 1) % segments;

                // quad = b0, b1, t1, t0  拆成两个三角形（外法线朝外，Unity CW = front）
                triangles[idx++] = b0;
                triangles[idx++] = t1;
                triangles[idx++] = b1;

                triangles[idx++] = b0;
                triangles[idx++] = t0;
                triangles[idx++] = t1;
            }

            // 顶盖（外法线 +y，从 top[0] 扇形三角化）
            for (int i = 0; i < segments - 2; i++)
            {
                triangles[idx++] = segments;
                triangles[idx++] = segments + i + 2;
                triangles[idx++] = segments + i + 1;
            }

            // 底盖（外法线 -y，绕序反向）
            for (int i = 0; i < segments - 2; i++)
            {
                triangles[idx++] = 0;
                triangles[idx++] = i + 1;
                triangles[idx++] = i + 2;
            }

            Mesh cylinderMesh = new Mesh();
            cylinderMesh.vertices  = vertices;
            cylinderMesh.triangles = triangles;
            cylinderMesh.RecalculateNormals();
            cylinderMesh.RecalculateBounds();

            fogObj.GetComponent<MeshFilter>().sharedMesh = cylinderMesh;
            fogObj.transform.localScale = new Vector3(1, 1, 1);
        }
    }
}