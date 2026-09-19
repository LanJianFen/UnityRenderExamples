using UnityEngine;

namespace AdvanceExamples.Skin.SSSSS.Scripts
{
    public static class SeparableScreenSubsurfaceScatteringDiffusionProfile
    {
        private static Vector3 Gaussian(float variance, float r, Vector3 falloff)
        {
            Vector3 g = Vector3.zero;
            // rgb 三个通道，通过 falloff 来控制形状
            float rrx = r / Mathf.Max(0.001f, falloff.x); // float rr = r / (0.001f + falloff[i]);
            g.x = Mathf.Exp((-(rrx * rrx)) / (2.0f * variance)) / (2.0f * 3.14f * variance);

            float rry = r / Mathf.Max(0.001f, falloff.y); // float rr = r / (0.001f + falloff[i]);
            g.y = Mathf.Exp((-(rry * rry)) / (2.0f * variance)) / (2.0f * 3.14f * variance);

            float rrz = r / Mathf.Max(0.001f, falloff.z); // float rr = r / (0.001f + falloff[i]);
            g.z = Mathf.Exp((-(rrz * rrz)) / (2.0f * variance)) / (2.0f * 3.14f * variance);

            return g;
        }

        // Jimenez ：只用原版 d'Eon 的红光方差基底
        private static Vector3 JimenezDiffusionProfile(float r, Vector3 falloff)
        {
            return 0.100f * Gaussian(0.0484f, r, falloff) +
                   0.118f * Gaussian(0.187f, r, falloff) +
                   0.113f * Gaussian(0.567f, r, falloff) +
                   0.358f * Gaussian(1.99f, r, falloff) +
                   0.078f * Gaussian(7.41f, r, falloff);
        }

        public static void CalculateKernel(Vector4[] kernel, int nSamples, Vector3 strength, Vector3 falloff)
        {
            float range = 3.0f;
            float exponent = 2.0f;

            // 计算 nSamples 个采样点
            float step = 2.0f * range / (nSamples - 1); //步长
            for (int i = 0; i < nSamples; ++i)
            {
                float o = -range + i * step;
                float sign = o > 0.0f ? 1.0f : -1.0f;
                // 在 [-range, range] 上取采样点，Pow 使采样点更靠近中心，而不是均匀分布
                float sampleR = range * sign * Mathf.Abs(Mathf.Pow(o, exponent) / Mathf.Pow(range, exponent));
                kernel[i] = new Vector4(0.0f, 0.0f, 0.0f, sampleR);
            }

            // X 轴的积分公式是 EU = ∫ (Σ GaussianX) * irradiance du
            // Y 轴的积分公式是 EV = ∫ (Σ GaussianY) EX dv
            // 算黎曼和 GaussianX * du 和 GaussianY * dv (注意没有 Σ，因为存在 kernel 的 nSamples 个通道里了
            for (int i = 0; i < nSamples; ++i)
            {
                // 每个点负责一个 du 长度。第 i 个采样点需要乘的长度是 0.5 * (第 i + 1 个采样点- 第 i - 1 个采样点)
                float leftDelta = i > 0 ? Mathf.Abs(kernel[i].w - kernel[i - 1].w) : 0.0f;
                float rightDelta = i < nSamples - 1 ? Mathf.Abs(kernel[i + 1].w - kernel[i].w) : 0.0f;
                float halfDelta = 0.5f * (rightDelta + leftDelta);

                Vector3 diffusionProfile = JimenezDiffusionProfile(kernel[i].w, falloff);
                // 记录 rgb 通道的黎曼和 ( 不包括 irradiance ）
                kernel[i].x = diffusionProfile.x * halfDelta;
                kernel[i].y = diffusionProfile.y * halfDelta;
                kernel[i].z = diffusionProfile.z * halfDelta;
            }

            // 把中心采样点挪到 第 1 位
            Vector4 center = kernel[nSamples / 2];
            for (int i = nSamples / 2; i > 0; --i)
                kernel[i] = kernel[i - 1];
            kernel[0] = center;

            // 记录 rgb 通道此时的权重总数 (面积, 高斯函数积分起来是 1，但是因为积分域不是无穷大，且是离散采样，所以需要归一化)
            Vector4 weightSum = Vector4.zero;
            for (int i = 0; i < nSamples; ++i)
            {
                weightSum.x += kernel[i].x;
                weightSum.y += kernel[i].y;
                weightSum.z += kernel[i].z;
            }

            // 归一化
            for (int i = 0; i < nSamples; ++i)
            {
                kernel[i].x /= weightSum.x;
                kernel[i].y /= weightSum.y;
                kernel[i].z /= weightSum.z;
            }

            // 本来是 6 个高斯核，其中一个能量全集中在中心了，黎曼和算不准，所以给中心点补上
            kernel[0].x = (1.0f - strength.x) + strength.x * kernel[0].x;
            kernel[0].y = (1.0f - strength.y) + strength.y * kernel[0].y;
            kernel[0].z = (1.0f - strength.z) + strength.z * kernel[0].z;

            // 其他的采样点要重新归一化一下
            for (int i = 1; i < nSamples; ++i)
            {
                kernel[i].x *= strength.x;
                kernel[i].y *= strength.y;
                kernel[i].z *= strength.z;
            }
        }
        
        public static Vector4[] JimenezSeparateGaussianDiffusionProfileWeightsAndSamplePoints()
        {
            return new Vector4[25]
            {
                new Vector4(0.530605f, 0.613514f, 0.739601f, 0.0000000f), // center
                new Vector4(0.000973794f, 1.11862e-05f, 9.43437e-07f, -3.0000000f),
                new Vector4(0.00333804f, 7.85443e-05f, 1.29450e-05f, -2.5208333f),
                new Vector4(0.00500364f, 0.000200940f, 5.28136e-05f, -2.0833333f),
                new Vector4(0.00700976f, 0.000493350f, 0.000151938f, -1.6875000f),
                new Vector4(0.00943890f, 0.001391190f, 0.000416598f, -1.3333333f),
                new Vector4(0.01284960f, 0.003563290f, 0.001320160f, -1.0208333f),
                new Vector4(0.01792400f, 0.007116910f, 0.003471940f, -0.7500000f),
                new Vector4(0.02636420f, 0.011971500f, 0.006845980f, -0.5208333f),
                new Vector4(0.04101720f, 0.019989900f, 0.011848100f, -0.3333333f),
                new Vector4(0.04935880f, 0.027290500f, 0.017331600f, -0.1875000f),
                new Vector4(0.05210490f, 0.034070000f, 0.021997400f, -0.0833333f),

                new Vector4(0.05210490f, 0.034070000f, 0.021997400f, 0.0833333f),
                new Vector4(0.04935880f, 0.027290500f, 0.017331600f, 0.1875000f),
                new Vector4(0.04101720f, 0.019989900f, 0.011848100f, 0.3333333f),
                new Vector4(0.02636420f, 0.011971500f, 0.006845980f, 0.5208333f),
                new Vector4(0.01792400f, 0.007116910f, 0.003471940f, 0.7500000f),
                new Vector4(0.01284960f, 0.003563290f, 0.001320160f, 1.0208333f),
                new Vector4(0.00943890f, 0.001391190f, 0.000416598f, 1.3333333f),
                new Vector4(0.00700976f, 0.000493350f, 0.000151938f, 1.6875000f),
                new Vector4(0.00500364f, 0.000200940f, 5.28136e-05f, 2.0833333f),
                new Vector4(0.00333804f, 7.85443e-05f, 1.29450e-05f, 2.5208333f),
                new Vector4(0.000973794f, 1.11862e-05f, 9.43437e-07f, 3.0000000f),

                Vector4.zero, Vector4.zero // padding to fit float4[25]
            };
        }

        // GPU Gem3  d'Eon 的数学正确版
        /*private static Vector3 dEonDiffusionProfile(float r) //r是扩散半径，右边的float3是RGB权重，一般红色散射多权重大
        {
            Vector3 falloff = Vector3.one;
            return Gaussian(0.0064f * 1.414f, r, falloff) * new Vector3(0.233f, 0.455f, 0.649f) +
                   Gaussian(0.0484f * 1.414f, r, falloff) * new Vector3(0.100f, 0.336f, 0.344f) +
                   Gaussian(0.1870f * 1.414f, r, falloff) * new Vector3(0.118f, 0.198f, 0.000f) +
                   Gaussian(0.5670f * 1.414f, r, falloff) * new Vector3(0.113f, 0.007f, 0.007f) +
                   Gaussian(1.9900f * 1.414f, r, falloff) * new Vector3(0.358f, 0.004f, 0.000f) +
                   Gaussian(7.4100f * 1.414f, r, falloff) * new Vector3(0.078f, 0.000f, 0.000f);
        }*/
    }
}
