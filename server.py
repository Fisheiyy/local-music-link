from http.server import BaseHTTPRequestHandler, HTTPServer
import base64
import json
import time
import threading

USERNAME = 'admin'
PASSWORD = 'password'

class MyServer(BaseHTTPRequestHandler):
    connected_clients = {}
    client_commands = {}
    client_states = {}
    heartbeat_interval = 10  # Interval in seconds
    max_missed_heartbeats = 5  # Number of missed heartbeats before disconnecting

    def authenticate(self):
        auth_header = self.headers.get('Authorization')
        if auth_header is None or not auth_header.startswith('Basic '):
            self.send_response(401)
            self.send_header('WWW-Authenticate', 'Basic realm="Login Required"')
            self.end_headers()
            self.wfile.write(b'401 Unauthorized')
            print("Authentication failed: No or invalid Authorization header")
            return False

        encoded_credentials = auth_header.split(' ')[1]
        decoded_credentials = base64.b64decode(encoded_credentials).decode('utf-8')
        username, password = decoded_credentials.split(':')

        if username == USERNAME and password == PASSWORD:
            #print("Authentication successful")
            return True
        else:
            self.send_response(401)
            self.send_header('WWW-Authenticate', 'Basic realm="Login Required"')
            self.end_headers()
            self.wfile.write(b'401 Unauthorized')
            print("Authentication failed: Incorrect username or password")
            return False

    def do_POST(self):
        if not self.authenticate():
            return

        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length).decode('utf-8')
        command_parts = post_data.split()
        print("\nCommand ", command_parts)

        if len(command_parts) == 1 and command_parts[0] == "GET_CLIENTS":
            response = json.dumps(list(MyServer.connected_clients.keys()))
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(response)))
            self.end_headers()
            self.wfile.write(response.encode())
            print(f"Sent client list: {response}")
            return

        if len(command_parts) < 2:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b'Invalid command format')
            print("Invalid command format")
            return

        command, client_id = command_parts[0], command_parts[1]

        if len(command_parts) > 2:
            value = command_parts[2:]
            print(f"Value: {value}, Uuid: {client_id}")
            if command in ["CHANGE_TRACK", "CHANGE_VOLUME"]:
                if command == "CHANGE_TRACK":
                    track_number = value[0]
                    print(f"Setting client state for {client_id} to Track {track_number}")
                    if client_id not in MyServer.client_states:
                        MyServer.client_states[client_id] = {}
                    MyServer.client_states[client_id]['Track'] = track_number
                    print(f"Client states: {MyServer.client_states}")
                elif command == "CHANGE_VOLUME":
                    volume_number = value[0]
                    print(f"Setting client state for {client_id} to Volume {volume_number}")
                    if client_id not in MyServer.client_states:
                        MyServer.client_states[client_id] = {}
                    MyServer.client_states[client_id]['Volume'] = volume_number
                    print(f"Client states: {MyServer.client_states}")
            else:
                print(f"Setting client state for {client_id} to {value}")
                if client_id not in MyServer.client_states:
                    MyServer.client_states[client_id] = {}
                for i in range(0, len(value), 2):
                    key = value[i]
                    val = value[i + 1] if i + 1 < len(value) else None
                    MyServer.client_states[client_id][key] = val
                print(f"Client states: {MyServer.client_states}")
        else:
            value = command_parts[2] if len(command_parts) > 2 else None

        if client_id not in MyServer.connected_clients:
            MyServer.connected_clients[client_id] = time.time()
            MyServer.client_commands[client_id] = []
            print(f"New client connected: {client_id}")
            print(f"Connected clients: {MyServer.connected_clients.keys()}")

        if command == "HEARTBEAT":
            MyServer.connected_clients[client_id] = time.time()
            print(f"Received heartbeat from client {client_id}")
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'Heartbeat received')
            return

        if command == "POLL_COMMANDS":
            commands = MyServer.client_commands.get(client_id, [])
            response = json.dumps(commands)
            MyServer.client_commands[client_id] = []  # Clear the command queue after sending
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(response)))
            self.end_headers()
            self.wfile.write(response.encode())
            print(f"Sent commands to client {client_id}: {response}")
            return

        if command == "GET_CLIENT_STATE":
            if client_id in MyServer.connected_clients:
                response = json.dumps({
                    "client_id": client_id,
                    "last_heartbeat": MyServer.connected_clients[client_id],
                    "state": MyServer.client_states.get(client_id, {})
                })
            else:
                response = json.dumps({"error": "Client not found"})
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(response)))
            self.end_headers()
            self.wfile.write(response.encode())
            print(f"Sent client state for {client_id}: {response}")
            return

        if command == "SET_CLIENT_STATE":
            if client_id in MyServer.connected_clients:
                MyServer.connected_clients[client_id] = time.time()
                response = json.dumps({
                    "client_id": client_id,
                    "last_heartbeat": MyServer.connected_clients[client_id],
                    "state": value
                })
            else:
                response = json.dumps({"error": "Client not found"})
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(response)))
            self.end_headers()
            self.wfile.write(response.encode())
            print(f"Set client state for {client_id}: {response}")
            return

        print(f"Received command: {command}, Client ID: {client_id}, Value: {value}")

        if command in ["CHANGE_TRACK", "CHANGE_VOLUME"]:
            target_client_id = client_id
            if target_client_id not in MyServer.client_commands:
                MyServer.client_commands[target_client_id] = []
            MyServer.client_commands[target_client_id].append((command, value))
            response = f"Command {command} with value {value} sent to client {target_client_id}"
        else:
            response = "Unknown command"

        self.send_response(200)
        self.end_headers()
        self.wfile.write(response.encode())
        print(f"Response sent: {response}")

    @staticmethod
    def check_heartbeats():
        missed_heartbeats = {client_id: 0 for client_id in MyServer.connected_clients}

        while True:
            current_time = time.time()
            for client_id, last_heartbeat in list(MyServer.connected_clients.items()):
                if current_time - last_heartbeat > MyServer.heartbeat_interval:
                    missed_heartbeats[client_id] += 1
                    if missed_heartbeats[client_id] > MyServer.max_missed_heartbeats:
                        print(f"Client {client_id} disconnected due to missed heartbeats")
                        del MyServer.connected_clients[client_id]
                        del missed_heartbeats[client_id]
                        if client_id in MyServer.client_commands:
                            del MyServer.client_commands[client_id]
                        if client_id in MyServer.client_states:
                            del MyServer.client_states[client_id]
                else:
                    missed_heartbeats[client_id] = 0  # Reset missed heartbeats counter if heartbeat is received

            time.sleep(MyServer.heartbeat_interval)

def run(server_class=HTTPServer, handler_class=MyServer):
    # Read the configuration from the JSON file
    with open('server_config.json', 'r') as file:
        config = json.load(file)
        port = config.get('port', 8000)  # Default to port 8000 if not specified

    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    print(f'Starting server on port {port}...')

    # Start the heartbeat check thread
    heartbeat_thread = threading.Thread(target=MyServer.check_heartbeats)
    heartbeat_thread.daemon = True
    heartbeat_thread.start()

    httpd.serve_forever()

if __name__ == '__main__':
    run()