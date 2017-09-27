#ifndef _YRC_SCREEN_SPACE_RAYTRACE_
#define _YRC_SCREEN_SPACE_RAYTRACE_

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

#if 1		//by default we use fixed thickness.
	float screenPCameraDepth = -LinearEyeDepth(tex2Dlod(_CameraDepthTexture, float4(sspt / 2 + 0.5, 0, 0)).r);
	return raya < screenPCameraDepth && rayb > screenPCameraDepth - PIXEL_THICKNESS;
#else
	//float backZ = tex2Dlod(_BackfaceTex, float4(sspt / 2 + 0.5, 0, 0)).r;
	//return raya < backZ && rayb > screenPCameraDepth;
#endif
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

#endif