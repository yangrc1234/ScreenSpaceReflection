Shader "Hidden/ScreenSpaceReflection"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}
	SubShader
	{
		// No culling or depth
		Cull Off ZWrite Off ZTest Always

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
				float3 csRay : TEXCOORD1;
			};

			sampler2D _MainTex;
			float4 _MainTex_TexelSize;
			sampler2D _CameraGBufferTexture1;
			sampler2D _CameraGBufferTexture2;
			sampler2D _CameraDepthTexture;
			sampler2D _BackfaceTex;
			float4x4 _Projection;
			float4x4 _WorldToView;
			float4x4 _InverseProjection; // different from UNITY_MATRIX_V, unity_CameraInvProjection just works,don't know why.
			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				float4 cameraRay = float4(v.uv * 2.0 - 1.0, 1.0, 1.0);
				cameraRay = mul(unity_CameraInvProjection, cameraRay);
				o.csRay = cameraRay / cameraRay.w;
				return o;
			}

			bool RayIntersect(float raya, float rayb, float2 sspt) {
				float screenPCameraDepth = Linear01Depth(tex2Dlod(_CameraDepthTexture, float4(sspt / 2 + 0.5, 0, 0)));
				float backZ = tex2Dlod(_BackfaceTex, float4(sspt / 2 + 0.5, 0, 0)).r;

				if (raya > rayb) {
					float t = raya;
					raya = rayb;
					rayb = t;
				}
				return raya < backZ && rayb > screenPCameraDepth;
			}
/*
RAY_LENGTH是采样光线的最大长度
STEP_COUNT是最多的采样次数，超过采样次数会立刻返回
PIXEL_STRIDE是每次采样的间隔像素数量。越大，质量越低，但是采样范围越大。
*/
#define RAY_LENGTH 40.0
#define STEP_COUNT 32	//maximum sample count.
#define PIXEL_STRIDE 8 //sample every 8 pixel.
#define SCREEN_EDGE_MASK 0.9

			bool traceRay(float3 start, float3 direction,float jitter, out float2 hitPixel,out float alpha,out float3 debugCol ) {
				debugCol = 0;
				alpha = 1;
				//clamp raylength to near clip plane.
				float rayLength = ((start.z + direction.z * RAY_LENGTH) > -_ProjectionParams.y) ?
					(-_ProjectionParams.y - start.z) / direction.z : RAY_LENGTH;

				float3 end = start + direction * rayLength;

				float4 H0 = mul(unity_CameraProjection, float4(start, 1));		//H0.xy / H0.w is in [-1,1]
				float4 H1 = mul(unity_CameraProjection, float4(end, 1));

				float2 screenP0 = H0.xy / H0.w;
				float2 screenP1 = H1.xy / H1.w;		//。屏幕空间的采样坐标。

				float4 texelSize = _MainTex_TexelSize;
				if (abs(dot(screenP1 - screenP0, screenP1 - screenP0)) < 1.0) {
					screenP1 += texelSize.xy;
				}
				float2 deltaPixels = (screenP1 - screenP0) * texelSize.zw;	//屏幕上两点的像素间隔。
				float step;	//线性插值的步长。/
				step = min( 1 / abs(deltaPixels.y), 1 / abs(deltaPixels.x)); // 使每次采样都会间隔一个像素
				step *= PIXEL_STRIDE;		//加大采样距离（加快插值进度）。 
				float sampleScaler = 1.0 - min(1.0, -start.z / 100);	
				step *= 1.0 + sampleScaler;				//距离较近时（不容易采偏），插值进度更快

				float interpolationCounter = step;	//记录当前插值的进度。

				float oneOverzCurrent = 1 / start.z;
				float2 screenPCurrent = screenP0;

				float dOneOverZCurrent = step * (1 / end.z - 1 / start.z);
				float2 dScreenPCurrent = step * (screenP1 - screenP0);
				oneOverzCurrent += jitter * dOneOverZCurrent;
				screenPCurrent += jitter * dScreenPCurrent;
				float intersect = 0;
				float prevDepth = 1 / (oneOverzCurrent + 0.1 * dOneOverZCurrent) / -_ProjectionParams.z;	//步进方向面向相机时，可能会因为z值精度问题出现鬼影
				UNITY_LOOP
				for (int i = 1; i <= STEP_COUNT && interpolationCounter <= 1; i++) {
					oneOverzCurrent += dOneOverZCurrent;
					screenPCurrent += dScreenPCurrent;
					interpolationCounter += step;
					float screenPTrueDepth = 1 / oneOverzCurrent/ -_ProjectionParams.z;
					if (RayIntersect(screenPTrueDepth,prevDepth, screenPCurrent)){
#if 1	  //binary search
						float gapSize = PIXEL_STRIDE;
						float2 screenPBegin = screenPCurrent - dScreenPCurrent;
						float oneOverZBegin = oneOverzCurrent - dOneOverZCurrent;
						prevDepth = 1 / oneOverZBegin / -_ProjectionParams.z;
						UNITY_LOOP
						for (int j = 1; j <= 8 && gapSize > 1.0; j++) {
							gapSize /= 2;
							dScreenPCurrent /= 2;
							dOneOverZCurrent /= 2;
							screenPCurrent = screenPBegin + dScreenPCurrent;
							oneOverzCurrent = oneOverZBegin + dOneOverZCurrent;
							screenPTrueDepth = 1 / oneOverzCurrent / -_ProjectionParams.z;
							if (RayIntersect(screenPTrueDepth, prevDepth, screenPCurrent)) {		//命中了，不用动
							}
							else {							//没命中，往后压一压
								prevDepth = screenPTrueDepth;
								screenPBegin = screenPCurrent;
								oneOverZBegin = oneOverzCurrent;
							}
						}	 
#endif
						hitPixel = (screenPCurrent) / 2 + 0.5;
						intersect = 1;
						alpha *= 1 - (float)i / STEP_COUNT;
						debugCol = float3(hitPixel,0);
						break;
					}
					prevDepth = screenPTrueDepth;
				}

				alpha *= 1 - max(
					(clamp(abs(screenPCurrent.x), SCREEN_EDGE_MASK,1.0) - SCREEN_EDGE_MASK) / (1 - SCREEN_EDGE_MASK),
					(clamp(abs(screenPCurrent.y), SCREEN_EDGE_MASK, 1.0) - SCREEN_EDGE_MASK) / (1 - SCREEN_EDGE_MASK)
				);
				alpha *= intersect;
				alpha *= (1 - saturate(2 * direction.z));
				float farclipPlaneDist = 1 - (end.z / -_ProjectionParams.z);	//距离far clip plane的距离(0,1)
				alpha *= saturate((farclipPlaneDist - 0.1) * 8);	//淡出距离far clip plane小于0.1的反射。
				return false;
			}
			

			fixed4 frag (v2f i) : SV_Target
			{
				float decodedDepth = Linear01Depth(tex2D(_CameraDepthTexture, i.uv).r);
				float3 csRayOrigin = decodedDepth * i.csRay;
				float3 wsNormal = tex2D(_CameraGBufferTexture2, i.uv).rgb * 2.0 - 1.0;
				float3 csNormal = normalize(mul((float3x3)_WorldToView, wsNormal));
				float2 hitPixel;
				float3 debugCol;

				half3 reflection = 0;
				float alpha = 0;

				float2 uv2 = i.uv * _MainTex_TexelSize.zw;
				float c = (uv2.x + uv2.y) * 0.25;
				float jitter = fmod(c,1.0);

				traceRay(
						csRayOrigin, 
						normalize(reflect(csRayOrigin, csNormal)),
						jitter,
						hitPixel,
						alpha,
					debugCol);
				reflection = tex2D(_MainTex, hitPixel);
				return tex2D(_MainTex, i.uv) + half4(reflection,1) * alpha;
			}
			ENDCG
		}
	}
}
