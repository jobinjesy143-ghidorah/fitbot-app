import 'package:fitbot/api_base.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FitBot());
}

class FitBot extends StatelessWidget {
  const FitBot({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FitBot AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const MainMenu(),
    );
  }
}

// -------------------------------------------------------------------------
// --- 1. MAIN MENU (Versioning: v5.4) ---
// -------------------------------------------------------------------------
class MainMenu extends StatelessWidget {
  const MainMenu({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("FitBot AI Stylist"), centerTitle: true),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            children: [
              const SizedBox(height: 50),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/logo.png',
                  height: 150, width: 150, fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.auto_awesome, size: 100, color: Colors.indigo),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "NIFT JURY: ANNOTATED LOOKS v5.4",
                style: TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 50),
              _btn(context, "Quick Survey Mode", Icons.quiz_outlined, const SurveyScreen()),
              _btn(context, "Precision Entry", Icons.straighten, const MeasurementScreen()),
              _btn(context, "AI Body Mapping", Icons.camera_alt_outlined, const CameraScreen()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _btn(BuildContext context, String t, IconData i, Widget s) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
    child: ElevatedButton.icon(
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => s)),
      icon: Icon(i), label: Text(t, style: const TextStyle(fontSize: 16)),
      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(65), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
    ),
  );
}

// -------------------------------------------------------------------------
// --- 2. AI BODY MAPPING (With Volumetric Accuracy & Text Annotations) ---
// -------------------------------------------------------------------------
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});
  @override State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with SingleTickerProviderStateMixin {
  CameraController? _controller;
  bool _isReady = false, _isScanning = false;
  Map<String, dynamic>? _res;
  int _optIdx = 0; 
  late AnimationController _anim;
  double _userHeightInches = 65.0;

  final PoseDetector _poseDetector = PoseDetector(options: PoseDetectorOptions());

  @override
  void initState() {
    super.initState();
    _initCamera();
    _anim = AnimationController(duration: const Duration(seconds: 2), vsync: this)..repeat(reverse: true);
  }

  Future<void> _initCamera() async {
    if (await Permission.camera.request().isGranted) {
      final cams = await availableCameras();
      if (cams.isNotEmpty) {
        _controller = CameraController(cams[0], ResolutionPreset.high);
        await _controller!.initialize();
        if (mounted) setState(() => _isReady = true);
      }
    }
  }

  Future<void> _captureMapping() async {
    if (!_controller!.value.isInitialized) return;
    setState(() { _isScanning = true; _res = null; });
    
    try {
      final XFile photo = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(photo.path);
      final List<Pose> poses = await _poseDetector.processImage(inputImage);
      
      if (poses.isEmpty) { _showError("No body detected."); return; }

      final pose = poses.first;
      final nose = pose.landmarks[PoseLandmarkType.nose];
      final lAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
      final lS = pose.landmarks[PoseLandmarkType.leftShoulder];
      final rS = pose.landmarks[PoseLandmarkType.rightShoulder];
      final lH = pose.landmarks[PoseLandmarkType.leftHip];
      final rH = pose.landmarks[PoseLandmarkType.rightHip];

      if (nose != null && lAnkle != null && lS != null && rS != null && lH != null && rH != null) {
        double pHeight = (lAnkle.y - nose.y).abs();
        double scalar = _userHeightInches / (pHeight * 1.08); 

        double sPx = sqrt(pow(lS.x - rS.x, 2) + pow(lS.y - rS.y, 2));
        double hPx = sqrt(pow(lH.x - rH.x, 2) + pow(lH.y - rH.y, 2));

        // PRESERVING SUCCESSFUL MATH: (Skeletal Width * 1.3) * 3.14 for 360 Girth
        double realS = (sPx * scalar) * 1.25; 
        double skeletalH = hPx * scalar;
        double realH360 = (skeletalH * 1.3) * 3.14; 

        _sendToAI(realS, realH360, realH360 * 0.76, realS * 2.2);
      }
    } catch (e) { setState(() => _isScanning = false); }
  }

  Future<void> _sendToAI(double s, double h, double w, double c, {bool isFeedback = false, String? trueShape}) async {
    try {
      final response = await http.post(
        Uri.parse(apiBase),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'shoulders': s, 'hips': h, 'waist': w, 'chest': c, 'gender': 'Female', 'is_feedback': isFeedback, 'true_shape': trueShape}),
      );
      if (response.statusCode == 200 && mounted) {
        setState(() { _res = json.decode(response.body); _optIdx = 0; _isScanning = false; });
      }
    } catch (e) { setState(() => _isScanning = false); }
  }

  void _showRetrainDialog() {
    final sC = TextEditingController(text: _res!['measurements']['shoulders'].replaceAll('"', ''));
    final hC = TextEditingController(text: _res!['measurements']['hips'].replaceAll('"', ''));
    String selectedShape = "Rectangle"; 
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setD) => AlertDialog(
        title: const Text("Train AI Model"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: sC, decoration: const InputDecoration(labelText: "Correct Shoulder (\")")),
          TextField(controller: hC, decoration: const InputDecoration(labelText: "Correct Hip Circumference (\")")),
          const SizedBox(height: 15),
          DropdownButtonFormField<String>(
            value: selectedShape, 
            decoration: const InputDecoration(labelText: "NIFT Body Shape Label"),
            items: ["Hourglass", "Pear/Triangle", "Apple/Inverted Triangle", "Rectangle", "Spoon"]
                .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), 
            onChanged: (v) => setD(() => selectedShape = v!),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(onPressed: () { 
            Navigator.pop(ctx); 
            _sendToAI(double.tryParse(sC.text) ?? 15, double.tryParse(hC.text) ?? 34, 28, 36, isFeedback: true, trueShape: selectedShape); 
          }, child: const Text("Update AI"))
        ],
      )),
    );
  }

  void _showError(String msg) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red)); setState(() => _isScanning = false); }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(backgroundColor: Colors.black, body: Stack(children: [
      CameraPreview(_controller!),
      if (_isScanning) _laser(),
      if (_res != null) _sheet(),
      if (_res == null) _controls(),
    ]));
  }

  Widget _laser() => AnimatedBuilder(animation: _anim, builder: (c, child) => Positioned(top: 200 + (400 * _anim.value), left: 40, right: 40, child: Container(height: 3, decoration: const BoxDecoration(color: Colors.cyanAccent, boxShadow: [BoxShadow(color: Colors.cyanAccent, blurRadius: 15)]))));

  Widget _sheet() {
    final recs = _res!['recommendations'] as List?;
    return Container(color: Colors.black.withOpacity(0.9), padding: const EdgeInsets.all(30), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text("${_res!['shape']} Type", style: const TextStyle(color: Colors.cyanAccent, fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      Text("S: ${_res!['measurements']['shoulders']} | H: ${_res!['measurements']['hips']}", style: const TextStyle(color: Colors.white70)),
      const SizedBox(height: 15),
      OutlinedButton.icon(icon: const Icon(Icons.model_training, color: Colors.amberAccent), label: const Text("Train AI", style: TextStyle(color: Colors.amberAccent)), onPressed: _showRetrainDialog),
      const SizedBox(height: 25),
      
      // --- IMAGES WITH ANNOTATIONS ---
      if (recs != null) Row(children: [
        Expanded(child: Column(children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(recs[_optIdx]['t_url'], height: 160, fit: BoxFit.cover)),
          const SizedBox(height: 8),
          Text(recs[_optIdx]['top'] ?? "Top", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        ])),
        const SizedBox(width: 10),
        Expanded(child: Column(children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(recs[_optIdx]['b_url'], height: 160, fit: BoxFit.cover)),
          const SizedBox(height: 8),
          Text(recs[_optIdx]['bottom'] ?? "Bottom", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        ])),
      ]),
      
      const SizedBox(height: 20),
      if (recs != null && recs.length > 1) ElevatedButton.icon(
        icon: const Icon(Icons.style),
        onPressed: () => setState(() => _optIdx = (_optIdx + 1) % recs.length), 
        label: Text("Alternative Style ${_optIdx + 1}")
      ),
      TextButton(onPressed: () => setState(() => _res = null), child: const Text("Close Scanner", style: TextStyle(color: Colors.white))),
    ]));
  }

  Widget _controls() => Align(alignment: Alignment.bottomCenter, child: Container(padding: const EdgeInsets.all(25), decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Text("Anchor Height: ${_userHeightInches.toInt()}\" (${(_userHeightInches / 12).floor()}'${_userHeightInches.toInt() % 12}\")", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    Slider(value: _userHeightInches, min: 48, max: 84, divisions: 36, activeColor: Colors.cyanAccent, onChanged: (v) => setState(() => _userHeightInches = v)),
    ElevatedButton(onPressed: _isScanning ? null : _captureMapping, child: const Text("RUN VOLUMETRIC SCAN")),
  ])));

  @override
  void dispose() { _poseDetector.close(); _controller?.dispose(); _anim.dispose(); super.dispose(); }
}

// -------------------------------------------------------------------------
// --- 3. SURVEY MODE (Linked with Annotations) ---
// -------------------------------------------------------------------------
class SurveyScreen extends StatefulWidget {
  const SurveyScreen({super.key});
  @override State<SurveyScreen> createState() => _SurveyScreenState();
}
class _SurveyScreenState extends State<SurveyScreen> {
  Map<String, dynamic>? _res; bool _load = false; int _idx = 0;
  Future<void> _analyze(double s, double h, double w, double c) async {
    setState(() => _load = true);
    try {
      final response = await http.post(Uri.parse(apiBase), headers: {'Content-Type': 'application/json'}, body: json.encode({'shoulders': s, 'hips': h, 'waist': w, 'chest': c, 'gender': 'Female', 'is_feedback': false}));
      if (response.statusCode == 200) setState(() { _res = json.decode(response.body); _idx = 0; _load = false; });
    } catch (e) { setState(() => _load = false); }
  }
  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text("Survey Mode")), body: SingleChildScrollView(padding: const EdgeInsets.all(30), child: Column(children: [
      _card("Hourglass Profile", 18, 18, 26, 36),
      _card("Pear/Triangle Profile", 15, 22, 28, 34),
      _card("Apple/Inverted Triangle Profile", 22, 15, 30, 40),
      _card("Rectangle Profile", 18, 18, 32, 36),
      _card("Spoon Profile", 16, 24, 25, 35),
      if (_load) const CircularProgressIndicator(),
      if (_res != null) _resultView(),
    ])));
  }
  Widget _card(String l, double s, double h, double w, double c) => Padding(padding: const EdgeInsets.only(bottom: 10), child: OutlinedButton(onPressed: () => _analyze(s, h, w, c), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)), child: Text(l)));
  
  Widget _resultView() {
    final recs = _res!['recommendations'] as List?;
    return Column(children: [
      const Divider(height: 40),
      Text("${_res!['shape']} Recommended Looks", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo)),
      const SizedBox(height: 20),
      if (recs != null) Column(children: [
        Row(children: [
          Expanded(child: Column(children: [
            ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(recs[_idx]['t_url'], height: 200, fit: BoxFit.cover)),
            const SizedBox(height: 8),
            Text(recs[_idx]['top'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
          ])),
          const SizedBox(width: 10),
          Expanded(child: Column(children: [
            ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(recs[_idx]['b_url'], height: 200, fit: BoxFit.cover)),
            const SizedBox(height: 8),
            Text(recs[_idx]['bottom'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
          ])),
        ]),
        const SizedBox(height: 15),
        ElevatedButton(onPressed: () => setState(() => _idx = (_idx + 1) % recs.length), child: const Text("Next Option")),
      ]),
    ]);
  }
}

// -------------------------------------------------------------------------
// --- 4. PRECISION ENTRY (Annotated) ---
// -------------------------------------------------------------------------
class MeasurementScreen extends StatefulWidget {
  const MeasurementScreen({super.key});
  @override State<MeasurementScreen> createState() => _MeasurementScreenState();
}
class _MeasurementScreenState extends State<MeasurementScreen> {
  final _s = TextEditingController(), _h = TextEditingController(), _w = TextEditingController(), _c = TextEditingController();
  Map<String, dynamic>? _res; bool _load = false; int _idx = 0;
  Future<void> _submit() async {
    setState(() => _load = true);
    try {
      final response = await http.post(Uri.parse(apiBase), headers: {'Content-Type': 'application/json'}, body: json.encode({'shoulders': double.tryParse(_s.text), 'hips': double.tryParse(_h.text), 'waist': double.tryParse(_w.text), 'chest': double.tryParse(_c.text), 'gender': 'Female', 'is_feedback': false}));
      if (response.statusCode == 200) setState(() { _res = json.decode(response.body); _idx = 0; _load = false; });
    } catch (e) { setState(() => _load = false); }
  }
  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text("Precision Entry")), body: SingleChildScrollView(padding: const EdgeInsets.all(30), child: Column(children: [
      _f(_s, "Shoulder"), _f(_c, "Chest"), _f(_w, "Waist"), _f(_h, "Hip (360°)"),
      const SizedBox(height: 30),
      ElevatedButton(onPressed: _submit, child: _load ? const CircularProgressIndicator() : const Text("Analyze Data")),
      if (_res != null) _resultView(),
    ])));
  }
  Widget _f(TextEditingController c, String l) => Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: c, decoration: InputDecoration(labelText: "$l (Inches)", border: const OutlineInputBorder()), keyboardType: TextInputType.number));
  
  Widget _resultView() {
    final recs = _res!['recommendations'] as List?;
    return Column(children: [
      const Divider(height: 40),
      Text("${_res!['shape']} Type", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo)),
      const SizedBox(height: 20),
      if (recs != null) Column(children: [
        Row(children: [
          Expanded(child: Column(children: [
            ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(recs[_idx]['t_url'], height: 200, fit: BoxFit.cover)),
            const SizedBox(height: 8),
            Text(recs[_idx]['top'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
          ])),
          const SizedBox(width: 10),
          Expanded(child: Column(children: [
            ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(recs[_idx]['b_url'], height: 200, fit: BoxFit.cover)),
            const SizedBox(height: 8),
            Text(recs[_idx]['bottom'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
          ])),
        ]),
        const SizedBox(height: 15),
        ElevatedButton(onPressed: () => setState(() => _idx = (_idx + 1) % recs.length), child: const Text("Next Option")),
      ]),
    ]);
  }
}