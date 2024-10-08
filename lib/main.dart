import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; // Import dart:async for Timer
import 'package:uuid/uuid.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:universal_platform/universal_platform.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Client App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Client App Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String hostname = '';
  int port = 8000;
  String username = 'admin';
  String password = 'password';
  final String uniqueId = const Uuid().v4(); // Generate a unique ID
  List<String> clients = [];
  String? selectedClient;
  String responseMessage = '';
  int externalClientcurrentTrack = 0;
  int externalClientcurrentVolume = 0;
  String? selectedExternalClient = '';
  int currentTrack = 0;
  int currentVolume = 0;
  int volumeIncrement = 1; // global default placeholder
  String platform = UniversalPlatform.operatingSystem.toString();
  Map<String, dynamic>? clientState; // Define clientState

  @override
  void initState() {
    super.initState();
    clientInit(); // initialize client details
  }

  Future<void> clientInit() async {
    switch (platform) {
      case 'OperatingSystem.android':
        volumeIncrement =
            8; // Android volume increment 100/15 = 6.67 + 1 for vol to incr
        break;
      case 'OperatingSystem.ios':
        volumeIncrement =
            7; // iOS volume increment 100/16 = 6.25 + 1 for vol to incr
        break;
      default:
        volumeIncrement = 1; // default volume increment
    }
    startHeartbeat();
    fetchClients();
    _getVolume();
    sendClientState();
    FlutterVolumeController.addListener(
      (volume) {
        print('Volume changed: $volume');
        setState(() {
          currentVolume = (volume * 100).toInt(); // Convert to percentage
        });
        sendCommand('CHANGE_VOLUME $uniqueId $currentVolume');
      },
    );
  }

  Future<void> _getVolume() async {
    double? volume = await FlutterVolumeController.getVolume();
    setState(() {
      currentVolume = (volume! * 100).toInt(); // Convert to percentage
    });
  }

  Future<void> _setVolume(int volume) async {
    if (volume == currentVolume) {
      print('Volume already set to $volume');
      return;
    } else if (volume != currentVolume) {
      print('Setting volume to $volume');
      await FlutterVolumeController.setVolume(
          volume / 100); // Convert to 0-1 range
      _getVolume();
    }
  }

  Future<void> fetchClients() async {
    final url = Uri.http('$hostname:$port', '/clients');
    final credentials = base64Encode(utf8.encode('$username:$password'));
    final headers = {
      'Authorization': 'Basic $credentials',
      'Content-Type': 'text/plain',
    };

    try {
      final response = await http
          .post(url, headers: headers, body: 'GET_CLIENTS')
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        setState(() {
          if (response.body == '[]') {
            responseMessage = 'No clients found';
          }
          clients = List<String>.from(jsonDecode(response.body));
          if (response.body.contains(uniqueId)) {
            // If the current clients unique ID is found in the response, remove it
            clients.remove(uniqueId);
          }
        });
      } else {
        setState(() {
          responseMessage = 'Failed to fetch clients';
        });
      }
    } catch (e) {
      setState(() {
        responseMessage = 'Error: $e';
      });
    }
  }

  Future<void> fetchClientState(String clientId) async {
    if (clientId == '') {
      return;
    }
    final url = Uri.http('$hostname:$port', '/client_state');
    final credentials = base64Encode(utf8.encode('$username:$password'));
    final headers = {
      'Authorization': 'Basic $credentials',
      'Content-Type': 'text/plain',
    };

    try {
      final response = await http
          .post(url, headers: headers, body: 'GET_CLIENT_STATE $clientId')
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        setState(() {
          clientState = jsonDecode(response.body);
          if (selectedClient == null) {
          } else if (clientState!['client_id'] == uniqueId) {
            currentTrack = int.parse(clientState!['state']['Track']);
            currentVolume = int.parse(clientState!['state']['Volume']);
            _setVolume(currentVolume); // Set the device volume
          } else {
            print("set external");
            externalClientcurrentTrack =
                int.parse(clientState!['state']['Track']);
            externalClientcurrentVolume =
                int.parse(clientState!['state']['Volume']);
          }
        });
        //sendClientState();
      } else {
        setState(() {
          responseMessage = 'Failed to fetch client state';
        });
      }
    } catch (e) {
      setState(() {
        responseMessage = 'Error: $e';
      });
    }
  }

  // send state for current client to server
  Future<void> sendClientState() async {
    final url = Uri.http('$hostname:$port', '/client_state');
    final credentials = base64Encode(utf8.encode('$username:$password'));
    final headers = {
      'Authorization': 'Basic $credentials',
      'Content-Type': 'text/plain',
    };

    try {
      final response = await http
          .post(url,
              headers: headers,
              body:
                  'SET_CLIENT_STATE $uniqueId\n Track $externalClientcurrentTrack\nVolume $externalClientcurrentVolume\n Platform $platform')
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        print('Failed to send client state');
      }
    } catch (e) {
      print('Error sending client state: $e');
    }
  }

  Future<void> sendCommand(String command) async {
    final url = Uri.http('$hostname:$port', '');
    final credentials = base64Encode(utf8.encode('$username:$password'));
    final headers = {
      'Authorization': 'Basic $credentials',
      'Content-Type': 'text/plain',
    };

    try {
      final response = await http
          .post(url, headers: headers, body: command)
          .timeout(const Duration(seconds: 10));
      setState(() {
        responseMessage = response.body;
      });
    } catch (e) {
      setState(() {
        responseMessage = 'Error: $e';
      });
    }
  }

  void changeTrack(int delta, [String? selectedClient]) {
    if (selectedClient != null) {
      if (selectedClient == uniqueId) {
        setState(() {
          currentTrack += delta;
        });
        sendCommand('CHANGE_TRACK $selectedClient $currentTrack');
      } else if (selectedClient == selectedExternalClient) {
        setState(() {
          externalClientcurrentTrack += delta;
        });
        sendCommand('CHANGE_TRACK $selectedClient $externalClientcurrentTrack');
      } else {
        print('Invalid client');
      }
    }
  }

  void changeVolume(int delta, [String? selectedClient]) {
    print(currentVolume);
    _getVolume();
    if (selectedClient != null) {
      if (selectedClient == uniqueId) {
        setState(() {
          currentVolume = (currentVolume + delta)
              .clamp(0, 100); // Ensure volume stays within 0-100
        });
        _setVolume(currentVolume); // Set the device volume
        sendCommand('CHANGE_VOLUME $selectedClient $currentVolume');
      } else if (selectedClient == selectedExternalClient) {
        setState(() {
          externalClientcurrentVolume += delta;
        });
        sendCommand(
            'CHANGE_VOLUME $selectedClient $externalClientcurrentVolume');
      } else {
        print('Invalid client');
      }
    }
  }

  void startHeartbeat() {
    Timer.periodic(const Duration(seconds: 15), (timer) async {
      final url = Uri.http('$hostname:$port', '/heartbeat');
      final credentials = base64Encode(utf8.encode('$username:$password'));
      final headers = {
        'Authorization': 'Basic $credentials',
        'Content-Type': 'text/plain',
      };

      try {
        print('Sending heartbeat');
        final response = await http
            .post(url, headers: headers, body: 'HEARTBEAT $uniqueId')
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) {
          print('Failed to send heartbeat');
        }
        if (response.body == 'Heartbeat received') {
          print('Heartbeat successful: ${response.body}');
          fetchClientState(uniqueId);
          fetchClients();
          if (selectedExternalClient != null || selectedExternalClient != '') {
            fetchClientState(selectedExternalClient!);
          }
        } else {
          print('Heartbeat failed: ${response.body}');
        }
      } catch (e) {
        print('Error sending heartbeat: $e');
      }
    });
  }

  void navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(
          hostname: hostname,
          port: port,
          username: username,
          password: password,
          uniqueId: uniqueId,
          onSettingsChanged: (newHostname, newPort, newUsername, newPassword) {
            setState(() {
              hostname = newHostname;
              port = newPort;
              username = newUsername;
              password = newPassword;
            });
          },
        ),
      ),
    );
  }

  void refreshConnection() {
    fetchClients();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: navigateToSettings,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButton<String>(
              hint: const Text('Select Client'),
              value: clients.contains(selectedClient) ? selectedClient : null,
              onChanged: (String? newValue) {
                setState(() {
                  selectedClient = newValue;
                  selectedExternalClient = newValue;
                  if (newValue != null) {
                    fetchClientState(newValue);
                  }
                });
              },
              items: clients
                  .toSet()
                  .map<DropdownMenuItem<String>>((String client) {
                return DropdownMenuItem<String>(
                  value: client,
                  child: Text(client),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            if (clientState != null) ...[
              Text('Client State: $clientState'),
              const SizedBox(height: 20),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () => changeTrack(-1, selectedExternalClient),
                  ),
                ),
                Text('Ext Track: $externalClientcurrentTrack'),
                Expanded(
                  child: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => changeTrack(1, selectedExternalClient),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () => changeVolume(-1, selectedExternalClient),
                  ),
                ),
                Text('Ext Volume: $externalClientcurrentVolume'),
                Expanded(
                  child: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () =>
                        changeVolume(volumeIncrement, selectedExternalClient),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () => changeTrack(-1, uniqueId),
                  ),
                ),
                Text('Track: $currentTrack'),
                Expanded(
                  child: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => changeTrack(1, uniqueId),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () => changeVolume(-1, uniqueId),
                  ),
                ),
                Text('Volume: $currentVolume'),
                Expanded(
                  child: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => changeVolume(volumeIncrement, uniqueId),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('uuid: $uniqueId'),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('ext track: $externalClientcurrentTrack'),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('ext volume: $externalClientcurrentVolume'),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('track: $currentTrack'),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('volume: $currentVolume'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final String hostname;
  final int port;
  final String username;
  final String password;
  final String uniqueId;
  final Function(String, int, String, String) onSettingsChanged;

  const SettingsPage({
    super.key,
    required this.hostname,
    required this.port,
    required this.username,
    required this.password,
    required this.uniqueId,
    required this.onSettingsChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController hostnameController;
  late TextEditingController portController;
  late TextEditingController usernameController;
  late TextEditingController passwordController;

  @override
  void initState() {
    super.initState();
    hostnameController = TextEditingController(text: widget.hostname);
    portController = TextEditingController(text: widget.port.toString());
    usernameController = TextEditingController(text: widget.username);
    passwordController = TextEditingController(text: widget.password);
  }

  @override
  void dispose() {
    hostnameController.dispose();
    portController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    FlutterVolumeController.removeListener();
    super.dispose();
  }

  void saveSettings() {
    widget.onSettingsChanged(
      hostnameController.text,
      int.parse(portController.text),
      usernameController.text,
      passwordController.text,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: hostnameController,
              decoration: const InputDecoration(labelText: 'Hostname'),
            ),
            TextField(
              controller: portController,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            Text('Unique ID: ${widget.uniqueId}'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: saveSettings,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
