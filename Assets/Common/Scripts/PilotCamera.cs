using Unity.VisualScripting;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace Common.Scripts
{
    public class PilotCamera : MonoBehaviour
    {
        [SerializeField] float speed = 5.0f;
        [SerializeField] float rotateSpeed = 2.0f;

        private float _pitch;
        private float _yaw;
        private void OnEnable()
        {
            Camera cam = GetComponent<Camera>();
            if (cam == null) return;
        
            UniversalAdditionalCameraData cameraData = cam.GetUniversalAdditionalCameraData();
            if (cameraData == null) return;
        
            cameraData.requiresDepthTexture = true;
            cameraData.requiresColorTexture = true;
        
            Vector3 eulerAngles = transform.eulerAngles;
            _pitch = eulerAngles.y;
            _yaw = eulerAngles.x;
        }

        // Update is called once per frame
        void Update()
        {
            if (Input.GetMouseButton(1))
            {
                float mouseX = Input.GetAxis("Mouse X");
                float mouseY = Input.GetAxis("Mouse Y");
                _yaw += mouseX * rotateSpeed;
                _pitch -= mouseY * rotateSpeed;
                _pitch = Mathf.Clamp(_pitch, -90f, 90f);
                transform.rotation = Quaternion.Euler(_pitch, _yaw, 0.0f);
            }
        
            Vector3 moveDir = Vector3.zero;
            if (Input.GetKey(KeyCode.W)) moveDir += transform.forward;
            if (Input.GetKey(KeyCode.A)) moveDir += -transform.right;
            if (Input.GetKey(KeyCode.S)) moveDir += -transform.forward;
            if (Input.GetKey(KeyCode.D)) moveDir += transform.right;
            if (Input.GetKey(KeyCode.Q)) moveDir -= transform.up;
            if (Input.GetKey(KeyCode.E)) moveDir += transform.up;
        
            moveDir.Normalize();
        
            transform.position += moveDir * (speed * Time.deltaTime);
        }
    }

    [CustomEditor(typeof(PilotCamera))]
    public class PilotCameraEditor : Editor
    {
        public override void OnInspectorGUI()
        {
            DrawDefaultInspector();
            GUILayout.Space(10);

            if (GUILayout.Button("Align With View"))
            {
                Camera pilotCamera = target.GetComponent<Camera>();
                Camera sceneCamera =  SceneView.lastActiveSceneView?.camera;
                if (sceneCamera == null) return;
            
                // Ctrl + Z 可以撤回
                Undo.RecordObject(pilotCamera.transform, "Align With View");
            
                pilotCamera.transform.position = sceneCamera.transform.position;
                pilotCamera.transform.rotation = sceneCamera.transform.rotation;
            }
        }
    }
}