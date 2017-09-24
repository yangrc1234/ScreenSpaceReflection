using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
[RequireComponent(typeof(Camera))]
public class ScreenSpaceReflection : MonoBehaviour {
    public Material mat;
    public Shader backfaceShader;
    private void Start() {
        GetComponent<Camera>().depthTextureMode = DepthTextureMode.Depth;
        backfaceCamera = null;
    }

    private Camera backfaceCamera;
    [ImageEffectOpaque]
    private void OnRenderImage(RenderTexture source, RenderTexture destination) {
        RenderBackface();
        mat.SetTexture("_BackfaceTex", GetBackfaceTexture());
        mat.SetMatrix("_WorldToView", GetComponent<Camera>().worldToCameraMatrix);
        Graphics.Blit(source, destination, mat,0);
    }

    private void RenderBackface() {
        if (backfaceCamera == null) {
            var t = new GameObject();
            var mainCamera = Camera.main;
            t.transform.SetParent(mainCamera.transform);
            t.hideFlags = HideFlags.HideAndDontSave;
            backfaceCamera = t.AddComponent<Camera>();
            backfaceCamera.CopyFrom(mainCamera);
            backfaceCamera.enabled = false;
            backfaceCamera.clearFlags = CameraClearFlags.SolidColor;
            backfaceCamera.backgroundColor = Color.white;
            backfaceCamera.renderingPath = RenderingPath.Forward;
            backfaceCamera.SetReplacementShader(backfaceShader, "RenderType");
            backfaceCamera.targetTexture = GetBackfaceTexture();
        }
        backfaceCamera.Render();
        
    }

    private RenderTexture backfaceText;
    private RenderTexture GetBackfaceTexture() {
        if (backfaceText == null) { 
            backfaceText = new RenderTexture(Screen.width, Screen.height, 24, RenderTextureFormat.RFloat);
            backfaceText.filterMode = FilterMode.Point;     //VERY FUCKING IMPORTANT! COST ME TOATL 5 HOURS TO DEBUG
        }
        return backfaceText;
    }
}
