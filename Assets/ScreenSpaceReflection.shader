Shader "Hidden/ScreenSpaceReflection"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}
	SubShader
	{
		Cull Off 
		ZWrite Off
		ZTest Always

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
			float4x4 _WorldToView;		//UNITY_MATRIX_V doesn't work here. We need to manually set from script. Don't know why :C
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

			#include "ScreenSpaceRaytrace.cginc"
			/*
#define RAY_LENGTH 40.0	//maximum ray length.
#define STEP_COUNT 16	//maximum sample count.
#define PIXEL_STRIDE 16 //sample multiplier. it's recommend 16 or 8.
#define PIXEL_THICKNESS (0.03 * PIXEL_STRIDE)	//how thick is a pixel. correct value reduces noise.

			bool RayIntersect(float raya, float rayb, float2 sspt) {
				if (raya > rayb) {
					float t = raya;
					raya = rayb;
					rayb = t;
				}

				float screenPCameraDepth = -LinearEyeDepth(tex2Dlod(_CameraDepthTexture, float4(sspt / 2 + 0.5, 0, 0)).r);
				return raya < screenPCameraDepth && rayb > screenPCameraDepth - PIXEL_THICKNESS;
			}

			bool traceRay(float3 start, float3 direction, float jitter, float4 texelSize, out float2 hitPixel, out float marchPercent,out float hitZ) {
				//clamp raylength to near clip plane.
				float rayLength = ((start.z + direction.z * RAY_LENGTH) > -_ProjectionParams.y) ?
					(-_ProjectionParams.y - start.z) / direction.z : RAY_LENGTH;

				float3 end = start + direction * rayLength;

				float4 H0 = mul(unity_CameraProjection, float4(start, 1));
				float4 H1 = mul(unity_CameraProjection, float4(end, 1));

				float2 screenP0 = H0.xy / H0.w;
				float2 screenP1 = H1.xy / H1.w;	

				float k0 = 1.0 / H0.w;
				float k1 = 1.0 / H1.w;

				float Q0 = start.z * k0;
				float Q1 = end.z * k1;

				if (abs(dot(screenP1 - screenP0, screenP1 - screenP0)) < 0.00001) {
					screenP1 += texelSize.xy;
				}
				float2 deltaPixels = (screenP1 - screenP0) * texelSize.zw;
				float step;	//the sample rate.
				step = min(1 / abs(deltaPixels.y), 1 / abs(deltaPixels.x)); //make at least one pixel is sampled every time.

				//make sample faster.
				step *= PIXEL_STRIDE;		
				float sampleScaler = 1.0 - min(1.0, -start.z / 100); //sample is slower when far from the screen.
				step *= 1.0 + sampleScaler;	

				float interpolationCounter = step;	//by default we use step instead of 0. this avoids some glitch.

				float4 pqk = float4(screenP0, Q0, k0);
				float4 dpqk = float4(screenP1 - screenP0, Q1 - Q0, k1 - k0) * step;

				pqk += jitter * dpqk;

				float prevZMaxEstimate = start.z;

				bool intersected = false;
				UNITY_LOOP		//the logic here is a little different from PostProcessing or (casual-effect). but it's all about raymarching.
					for (int i = 1;
						i <= STEP_COUNT && interpolationCounter <= 1 && !intersected;
						i++,
						interpolationCounter += step
						) {
					pqk += dpqk;
					float rayZMin = prevZMaxEstimate;
					float rayZMax = ( pqk.z) / ( pqk.w);

					if (RayIntersect(rayZMin, rayZMax, pqk.xy - dpqk.xy / 2)) {
						hitPixel = (pqk.xy - dpqk.xy / 2) / 2 + 0.5;
						marchPercent = (float)i / STEP_COUNT;
						intersected = true;
					}
					else {
						prevZMaxEstimate = rayZMax;
					}
				}

#if 1	  //binary search
				if (intersected) {
					pqk -= dpqk;	//one step back
					UNITY_LOOP
						for (float gapSize = PIXEL_STRIDE; gapSize > 1.0; gapSize /= 2) {
							dpqk /= 2;
							float rayZMin = prevZMaxEstimate;
							float rayZMax = (pqk.z) / ( pqk.w);

							if (RayIntersect(rayZMin, rayZMax, pqk.xy - dpqk.xy / 2)) {		//hit, stay the same.(but ray length is halfed)

							}
							else {							//miss the hit. we should step forward
								pqk += dpqk;
								prevZMaxEstimate = rayZMax;
							}
						}
					hitPixel = (pqk.xy - dpqk.xy / 2) / 2 + 0.5;
				}
#endif
				hitZ = pqk.z / pqk.w;

				return intersected;
			}
			*/
#define SCREEN_EDGE_MASK 0.9
			float alphaCalc(float3 rayDirection, float2 hitPixel, float marchPercent, float hitZ) {
				float res = 1;
				res *= saturate(-5 * (rayDirection.z - 0.2));
				float2 screenPCurrent = 2 * (hitPixel - 0.5);
				res *= 1 - max(
					(clamp(abs(screenPCurrent.x), SCREEN_EDGE_MASK, 1.0) - SCREEN_EDGE_MASK) / (1 - SCREEN_EDGE_MASK),
					(clamp(abs(screenPCurrent.y), SCREEN_EDGE_MASK, 1.0) - SCREEN_EDGE_MASK) / (1 - SCREEN_EDGE_MASK)
				);
				res *= 1 - marchPercent;
				res *= 1 - (-(hitZ - 0.2) * _ProjectionParams.w);
				return res;
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

				float3 reflectionDir = normalize(reflect(csRayOrigin, csNormal));

				float2 uv2 = i.uv * _MainTex_TexelSize.zw;
				float c = (uv2.x + uv2.y) * 0.25;
				float jitter = fmod(c,1.0);

				float marchPercent;
				float hitZ;
				float rayBump = max(-0.018*csRayOrigin.z, 0.001);
				if (traceRay(
					csRayOrigin + csNormal * rayBump,
					reflectionDir,
					jitter,
					_MainTex_TexelSize,
					hitPixel,
					marchPercent,
					hitZ)) {
					alpha = alphaCalc(reflectionDir, hitPixel, marchPercent,hitZ);
				}
				reflection = tex2D(_MainTex, hitPixel);	
				return tex2D(_MainTex, i.uv) + half4(reflection,1) * alpha;
			}
			ENDCG
		}
	}
}
