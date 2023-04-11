import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_gl/flutter_gl.dart';
import 'package:three_dart/three_dart.dart' as THREE;
import 'package:three_dart/three_dart.dart' hide Texture, Mesh, Color;
import 'package:three_dart_jsm/three_dart_jsm.dart' as JSM;

import 'package:apple_vision_hand/apple_vision_hand.dart' as Hand;
import 'package:apple_vision_pose/apple_vision_pose.dart' as Pose;
import 'package:camera_macos/camera_macos_controller.dart';
import 'package:camera_macos/camera_macos_device.dart';
import 'package:camera_macos/camera_macos_file.dart';
import 'package:camera_macos/camera_macos_platform_interface.dart';
import 'package:camera_macos/camera_macos_view.dart';

import 'package:image_compression/image_compression.dart';
import 'package:path_provider/path_provider.dart';

class ARScreen extends StatefulWidget {
  const ARScreen(
      {Key? key,
      this.database = '',
      this.offset = const Offset(0, 0),
      this.size = const Size(750, 750),
      this.onScanned})
      : super(key: key);

  final String database;
  final Offset offset;

  final Size size;
  final Function(dynamic data)? onScanned;

  @override
  _ARScreenState createState() => _ARScreenState();
}

class _ARScreenState extends State<ARScreen> {
  dynamic objFiles;
  bool loaded = false;
  List<String> mtl = [];
  List<double> angle = [180, 0, 0];
  List<double> tops = [10, 170, 330];
  double zoom = 1;
  List<Object> obj = [];

  late FlutterGlPlugin three3dRender;
  THREE.WebGLRenderer? renderer;
  int? fboId;
  late double width;
  late double height;
  Size? screenSize;
  late THREE.Scene scene;
  late THREE.Camera camera;
  double dpr = 1.0;
  bool verbose = false;
  bool disposed = false;
  late THREE.Object3D object;
  THREE.Object3D? intersected;
  late THREE.TextureLoader textureLoader;
  THREE.WebGLRenderTarget? renderTarget;
  final GlobalKey<JSM.DomLikeListenableState> _globalKey =
      GlobalKey<JSM.DomLikeListenableState>();
  // late var controls;
  Vector2 mousePosition = Vector2(1, 1);
  THREE.Raycaster raycaster = THREE.Raycaster();
  dynamic sourceTexture;
  bool hasRemove = false;
  List<int> colorLocation = [];

  bool didClick = false;
  bool openPicker = false;
  Offset? pickerLocation;
  bool isHovering = kIsWeb ? true : false;

  final GlobalKey cameraKey = GlobalKey(debugLabel: "cameraKey");
  late Pose.AppleVisionPoseController cameraController;
  late Hand.AppleVisionHandController handCamController;
  late List<CameraMacOSDevice> _cameras;
  CameraMacOSController? controller;
  String? deviceId;

  Pose.PoseData? poseData;
  Hand.HandData? handData;

  late double deviceWidth;
  late double deviceHeight;

  double locationX = 320;
  double locationY = 240;
  bool isVisible = false;

  var point1;
  var point2;

  var rightElbow;
  var rightShoulder;
  var rightWrist;

  var leftElbow;
  var leftShoulder;
  var leftWrist;

  var vec = THREE.Vector3();
  var pos = THREE.Vector3();

  @override
  void initState() {
    cameraController = Pose.AppleVisionPoseController();
    handCamController = Hand.AppleVisionHandController();
    CameraMacOS.instance
        .listDevices(deviceType: CameraMacOSDeviceType.video)
        .then((value) {
      _cameras = value;
      deviceId = _cameras.first.deviceId;
    });
    super.initState();
  }

  @override
  void dispose() {
    controller?.destroy();
    super.dispose();
  }

  // Function that will take a picture/frame and send it to Vision Pose
  void onTakePictureButtonPressed() async {
    CameraMacOSFile? file = await controller?.takePicture();
    Directory tempDir = await getTemporaryDirectory();
    String tempPath = tempDir.path;

    if (file != null && mounted) {
      Uint8List? image = file.bytes;

      // Compresses the image to save space
      var input = ImageFile(rawBytes: image!, filePath: tempPath);
      var output = await compressInQueue(ImageFileConfiguration(
          input: input,
          config:
              const Configuration(jpgQuality: 10, outputType: OutputType.jpg)));

      // handCamController.processImage(output.rawBytes, const Size(640, 480)).then((data) {
      //   handData = data;
      //   setState(() {});
      // });

      // Sends image to Vision pose and processes it
      cameraController
          .process(output.rawBytes, const Size(640, 480))
          .then((data) {
        poseData = data;
        setState(() {});
      });
    }
  }

  // Initializes 3D Scene
  Future<void> initPage() async {
    scene = THREE.Scene();

    camera = THREE.Camera();
    camera = THREE.PerspectiveCamera(60, width / height, 1, 1000);
    camera.position.set(0, 0, 450);
    camera.lookAt(scene.position);

    // // controls
    // if (kIsWeb) {
    //   JSM.TrackballControls _controls =
    //       JSM.TrackballControls(camera, _globalKey);
    //   _controls.rotateSpeed = 10.0;
    //   controls = _controls;
    // } else {
    //   JSM.OrbitControls _controls = JSM.OrbitControls(camera, _globalKey);
    //   controls = _controls;
    // }

    Loader loader = JSM.OBJLoader(null);
    object = await loader.loadAsync('assets/V3_ARMandFingers.obj');
    object.traverse((child) {
      if (child is THREE.Mesh) {
        MeshPhongMaterial mat = child.material;
        mat.shininess = 15.078431;
        mat.specular = THREE.Color(0.5, 0.5, 0.5);
        mat.color = THREE.Color(0xff414141);
      }
    });

    object.visible = false;
    scene.add(object);

    var axesHelper = THREE.AxesHelper(1000);
    scene.add(axesHelper);

    // lights
    AmbientLight ambientLight = AmbientLight(0x404040);
    DirectionalLight dirLight1 = DirectionalLight(0xC0C090);
    dirLight1.position.set(-100, -50, 100);
    DirectionalLight dirLight2 = DirectionalLight(0xC0C090);
    dirLight2.position.set(100, 50, -100);

    scene.add(dirLight1);
    scene.add(dirLight2);
    scene.add(ambientLight);
    textureLoader = TextureLoader(null);
  }

  void render() {
    final _gl = three3dRender.gl;
    renderer!.render(scene, camera);
    _gl.flush();
    //controls.update();
    checkIntersection();
    if (!kIsWeb) {
      three3dRender.updateTexture(sourceTexture);
    }
  }

  Vector2 convertPosition(Vector2 location) {
    double _x = (location.x / (width - widget.offset.dx)) * 2 - 1;
    double _y = -(location.y / (height - widget.offset.dy)) * 2 + 1;
    return Vector2(_x, _y);
  }

  void checkIntersection() {
    raycaster.setFromCamera(convertPosition(mousePosition), camera);
    List<Intersection> intersects =
        raycaster.intersectObjects(object.children, false);
    void materialEmmisivity(double emmisive) {
      MeshPhongMaterial mat = intersected!.material;
      List<String> split = mat.name.split('|');
      if (split.length > 1 && split[1] == 'g') {
        if (emmisive == 0) {
          mat.emissive!.r = .5;
          mat.emissive!.g = .5;
          mat.emissive!.b = .5;
        } else {
          mat.emissive!.r = 1;
          mat.emissive!.g = 1;
          mat.emissive!.b = 1;
        }
      } else {
        mat.emissive!.r = emmisive;
        mat.emissive!.g = emmisive;
        mat.emissive!.b = emmisive;
      }
    }

    if (intersects.isNotEmpty) {
      if (intersected != intersects.first.object) {
        if (intersected != null) {
          materialEmmisivity(0);
        }
        intersected = intersects.first.object;
        materialEmmisivity(0.55);
      }
    } else if (intersected != null && !openPicker) {
      materialEmmisivity(0);
      intersected = null;
      setState(() {
        openPicker = false;
      });
    }

    if (didClick && intersected != null && !openPicker) {
      setState(() {
        pickerLocation = Offset(mousePosition.x, mousePosition.y);
        openPicker = true;
      });
    } else if (didClick && intersects.isEmpty && openPicker) {
      materialEmmisivity(0);
      intersected = null;
      setState(() {
        openPicker = false;
      });
    }

    didClick = false;
    isHovering = kIsWeb ? true : false;
  }

  void initScene() async {
    await initPage();
    initRenderer();

    animate();
  }

  void initRenderer() {
    Map<String, dynamic> _options = {
      "alpha": true,
      "width": width,
      "height": height,
      "gl": three3dRender.gl,
      "antialias": true,
      "canvas": three3dRender.element,
    };

    if (!kIsWeb && Platform.isAndroid) {
      _options['logarithmicDepthBuffer'] = true;
    }

    renderer = WebGLRenderer(_options);
    renderer!.setPixelRatio(dpr);
    renderer!.setSize(640, 480, false);
    renderer!.shadowMap.enabled = true;

    if (!kIsWeb) {
      WebGLRenderTargetOptions pars =
          WebGLRenderTargetOptions({"format": RGBAFormat, "samples": 8});
      renderTarget = WebGLRenderTarget(
          (width * dpr).toInt(), (height * dpr).toInt(), pars);
      renderTarget!.samples = 4;
      renderer!.setRenderTarget(renderTarget);
      sourceTexture = renderer!.getRenderTargetGLTexture(renderTarget!);
    } else {
      renderTarget = null;
    }
  }

  Future<void> initPlatformState() async {
    width = 640;
    height = 480;

    three3dRender = FlutterGlPlugin();

    Map<String, dynamic> _options = {
      "antialias": true,
      "alpha": true,
      "width": width.toInt(),
      "height": height.toInt(),
      "dpr": dpr,
      'precision': 'highp'
    };
    await three3dRender.initialize(options: _options);

    setState(() {});

    // TODO web wait dom ok!!!
    Future.delayed(const Duration(milliseconds: 100), () async {
      await three3dRender.prepareContext();
      initScene();
    });
  }

  void initSize(BuildContext context) {
    if (screenSize != null) {
      return;
    }

    final mqd = MediaQuery.of(context);

    screenSize = mqd.size;
    dpr = mqd.devicePixelRatio;

    initPlatformState();
  }

  void animate() {
    if (!mounted || disposed) {
      return;
    }

    render();
    Future.delayed(const Duration(milliseconds: 40), () {
      animate();
    });
  }

  Widget threeDart() {
    return Container(
        height: 480,
        width: 640,
        color: Colors.transparent,
        child: JSM.DomLikeListenable(
            key: _globalKey,
            builder: (BuildContext context) {
              return Container(
                  width: width,
                  height: height,
                  color: Colors.transparent,
                  child: Builder(builder: (BuildContext context) {
                    if (kIsWeb) {
                      return three3dRender.isInitialized
                          ? HtmlElementView(
                              viewType: three3dRender.textureId!.toString())
                          : Container();
                    } else {
                      return three3dRender.isInitialized
                          ? Texture(textureId: three3dRender.textureId!)
                          : Container();
                    }
                  }));
            }));
  }

  List<Widget> showPoints() {
    if (poseData == null || poseData!.poses.isEmpty) return [];
    // if (handData == null || handData!.poses.isEmpty) return [];
    Map<Pose.Joint, Color> colors = {
      // Elbow
      Pose.Joint.rightForearm: Colors.yellow,
      // Hip
      Pose.Joint.rightUpLeg: Colors.green,
      // Wrist
      Pose.Joint.rightHand: Colors.blue,
      Pose.Joint.rightShoulder: Colors.red,
      Pose.Joint.leftShoulder: Colors.red,
      // Elbow
      Pose.Joint.leftForearm: Colors.yellow,
      // Hip
      Pose.Joint.leftUpLeg: Colors.green,
      // Wrist
      Pose.Joint.leftHand: Colors.blue,
    };

    // Map<Hand.FingerJoint, Color> handColors = {
    //   Hand.FingerJoint.thumbCMC: Colors.amber,
    //   Hand.FingerJoint.thumbIP: Colors.amber,
    //   Hand.FingerJoint.thumbMP: Colors.amber,
    //   Hand.FingerJoint.thumbTip: Colors.amber,
    //   Hand.FingerJoint.indexDIP: Colors.green,
    //   // Use this
    //   Hand.FingerJoint.indexMCP: Colors.green,
    //   Hand.FingerJoint.indexPIP: Colors.green,
    //   Hand.FingerJoint.indexTip: Colors.green,
    //   Hand.FingerJoint.middleDIP: Colors.purple,
    //   Hand.FingerJoint.middleMCP: Colors.purple,
    //   Hand.FingerJoint.middlePIP: Colors.purple,
    //   Hand.FingerJoint.middleTip: Colors.purple,
    //   Hand.FingerJoint.ringDIP: Colors.pink,
    //   Hand.FingerJoint.ringMCP: Colors.pink,
    //   Hand.FingerJoint.ringPIP: Colors.pink,
    //   Hand.FingerJoint.ringTip: Colors.pink,
    //   Hand.FingerJoint.littleDIP: Colors.cyanAccent,
    //   // Use this compare to length 50 pixels
    //   Hand.FingerJoint.littleMCP: Colors.cyanAccent,
    //   Hand.FingerJoint.littlePIP: Colors.cyanAccent,
    //   Hand.FingerJoint.littleTip: Colors.cyanAccent
    // };

    List<Widget> widgets = [];

    // for (int i = 0; i < handData!.poses.length; i++) {
    //   if (handData!.poses[i].confidence > 0.5) {
    //     widgets.add(Positioned(
    //         bottom: handData!.poses[i].location.y,
    //         left: handData!.poses[i].location.x,
    //         child: Container(
    //           width: 10,
    //           height: 10,
    //           decoration: BoxDecoration(
    //               color: handColors[handData!.poses[i].joint],
    //               borderRadius: BorderRadius.circular(5)),
    //         )));
    //   }
    // }

    isVisible = false;

    for (int i = 0; i < poseData!.poses.length; i++) {
      if (poseData!.poses[i].confidence > 0.25) {
        // Sets point1 as the X and Y given by wrist
        if (poseData!.poses[i].joint == Pose.Joint.rightHand) {
          isVisible = true;
          rightWrist.x = poseData!.poses[i].location.x;
          rightWrist.y = poseData!.poses[i].location.y;
          point1 = rightWrist;
        }

        // Sets Point2 and Elbow as the X and Y given by elbow
        if (poseData!.poses[i].joint == Pose.Joint.rightForearm) {
          rightElbow.x = locationX = poseData!.poses[i].location.x;
          rightElbow.y = locationY = poseData!.poses[i].location.y;
          point2 = rightElbow;
        }

        // Sets Shoulder as the X and Y given by shoulder
        if (poseData!.poses[i].joint == Pose.Joint.rightShoulder) {
          rightShoulder.x = poseData!.poses[i].location.x;
          rightShoulder.y = poseData!.poses[i].location.y;
        }

        widgets.add(Positioned(
            bottom: poseData!.poses[i].location.y,
            left: poseData!.poses[i].location.x,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: colors[poseData!.poses[i].joint],
                  borderRadius: BorderRadius.circular(5)),
            )));
      }
    }

    setLocation();
    return widgets;
  }

  // Will show camera preview and periodically send frames to Vision Pose
  Widget _getScanWidgetByPlatform() {
    return CameraMacOSView(
      key: cameraKey,
      fit: BoxFit.fill,
      cameraMode: CameraMacOSMode.photo,
      enableAudio: false,
      onCameraLoading: (ob) {
        return Container(
            width: deviceWidth,
            height: deviceHeight,
            color: Theme.of(context).canvasColor,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(color: Colors.blue));
      },
      onCameraInizialized: (CameraMacOSController controller) {
        setState(() {
          this.controller = controller;
          Timer.periodic(const Duration(milliseconds: 500), (_) {
            onTakePictureButtonPressed();
          });
        });
      },
    );
  }

  // Calculates the length/distance between two cartesian points
  double length(double x, double y, double x2, double y2) {
    return Math.sqrt(Math.pow(x2 - x, 2) + Math.pow(y2 - y, 2));
  }

  // This function is responsible for the responsive movement of the arm object
  void setLocation() {
    if (isVisible) {
      // This code block converts 2D X and Y to 3D coordinates using Z = 0.5
      vec.set((locationX / 640) * 2 - 1, ((locationY) / 480) * 2 - 1, 0.5);
      vec.unproject(camera);
      vec.sub(camera.position).normalize();
      var distance = -camera.position.z / vec.z;
      pos.copy(camera.position).add(vec.multiplyScalar(distance));
      object.position = pos;

      // Set angle of arm based on two points (most likely elbow and wrist)
      object.rotation.z = Math.atan2(point1.y - point2.y, point1.x - point2.x);

      // Set size of object
      object.scale.setScalar(
          2.25 * length(point1.x, point1.y, rightElbow.x, rightElbow.y) / 260);

      object.visible = true;
      return;
    }

    object.visible = false;
  }

  @override
  Widget build(BuildContext context) {
    deviceWidth = MediaQuery.of(context).size.width;
    deviceHeight = MediaQuery.of(context).size.height;
    initSize(context);

    return Stack(
      children: <Widget>[
            SizedBox(
                width: 640, height: 480, child: _getScanWidgetByPlatform()),
            threeDart(),
          ] +
          showPoints(),
    );
  }
}
