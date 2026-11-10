// 文件名: Editor/BrdfEnergyLutBaker.cs

using System.IO;
using UnityEditor;
using UnityEngine;

namespace AdvanceExamples.BRDF.Shaders.Sony
{
    public static class SPI2017SpecularLUT
    {
        [MenuItem("Tools/Bake SPI Energy LUT")]
        public static void BakeLut()
        {
            // 查找刚才写的 Compute Shader
            ComputeShader cs = AssetDatabase.LoadAssetAtPath<ComputeShader>("Assets/AdvanceExamples/BRDF/Shaders/Sony/SPI2017SpecularLUT.compute");
            if (cs == null)
            {
                Debug.LogError("未找到 BakeBrdfEnergyLut.compute，请检查路径！");
                return;
            }

            const int lutSize = 128;

            // 创建一张支持 UAV 写入的浮点 RenderTexture
            RenderTexture rt = new RenderTexture(lutSize, lutSize, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear)
            {
                enableRandomWrite = true,
                wrapMode = TextureWrapMode.Clamp,
                filterMode = FilterMode.Bilinear
            };
            rt.Create();

            // 绑定参数并派发 GPU 线程 (64 / 8 = 8 个线程组)
            int kernel = cs.FindKernel("SPI2017SpecularLUT");
            cs.SetInt("_LutSize", lutSize);
            cs.SetTexture(kernel, "_ResultLut", rt);
            cs.Dispatch(kernel, lutSize / 8, lutSize / 8, 1);

            // 从显存 (RenderTexture) 读回内存 (Texture2D)
            RenderTexture prev = RenderTexture.active;
            RenderTexture.active = rt;
            Texture2D tex = new Texture2D(lutSize, lutSize, TextureFormat.RGBAFloat, false, true);
            tex.ReadPixels(new Rect(0, 0, lutSize, lutSize), 0, 0);
            tex.Apply();

            // === 新增验证打印：读取第 0 行（最光滑）的左端与右端像素 ===
            Color smoothGrazing = tex.GetPixel(0, 0);              // 左下角: mu_o -> 0, roughness -> 0
            Color smoothNormal  = tex.GetPixel(lutSize - 1, 0);    // 右下角: mu_o -> 1, roughness -> 0
            Color roughGrazing  = tex.GetPixel(0, lutSize - 1);    // 左上角: mu_o -> 0, roughness -> 1
            Debug.Log($"[光滑边缘 (0,0)] R(A)={smoothGrazing.r:F4}, G(B)={smoothGrazing.g:F4}, R+G={smoothGrazing.r + smoothGrazing.g:F4} | 第3通道 B(A_avg)={smoothGrazing.b:F5} (理论值 20/21≈0.95238), 第4通道 A(B_avg)={smoothGrazing.a:F5} (理论值 1/21≈0.04762)");
            Debug.Log($"[光滑正视 (1,0)] R(A)={smoothNormal.r:F4}, G(B)={smoothNormal.g:F4}, R+G={smoothNormal.r + smoothNormal.g:F4}");
            Debug.Log($"[粗糙边缘 (0,1)] R(A)={roughGrazing.r:F4}, G(B)={roughGrazing.g:F4} | 第3通道 B(A_avg)={roughGrazing.b:F4}, 第4通道 A(B_avg)={roughGrazing.a:F4}");
            RenderTexture.active = prev;

            // 编码为 16-bit Half Float 的 .exr 文件并写入硬盘
            byte[] exrBytes = tex.EncodeToEXR(Texture2D.EXRFlags.OutputAsFloat); // 或默认 Half
            string savePath = "Assets/AdvanceExamples/BRDF/Textures/T_SPI_SpecularLUT.exr";
            Directory.CreateDirectory(Path.GetDirectoryName(savePath));
            File.WriteAllBytes(savePath, exrBytes);

            // 清理临时资源并设置贴图导入格式 (必须关闭 sRGB，开启 Clamp！)
            rt.Release();
            Object.DestroyImmediate(rt);
            Object.DestroyImmediate(tex);

            AssetDatabase.Refresh();
            TextureImporter importer = AssetImporter.GetAtPath(savePath) as TextureImporter;
            if (importer != null)
            {
                importer.sRGBTexture = false;                // 绝对不能勾选 sRGB！这是纯数学数据表！
                importer.mipmapEnabled = false;              // LUT 不需要 Mipmap
                importer.wrapMode = TextureWrapMode.Clamp;   // 必须为 Clamp，防止边缘 0 和 1 互相越界污染！
                importer.filterMode = FilterMode.Bilinear;
                importer.textureCompression = TextureImporterCompression.Uncompressed; // 必须不压缩！保留完整的 RGBA 4通道浮点精度！
                importer.SaveAndReimport();
            }

            Debug.Log($"SPI Specular Energy LUT 烘焙成功！已保存至: {savePath}");
        }
    }
}