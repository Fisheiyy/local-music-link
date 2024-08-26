import requests
import base64
import json
import uuid
import threading
import time

class Client:
    active_clients = []

    def __init__(self, config_file='client_config.json'):
        # Read the configuration from the JSON file
        with open(config_file, 'r') as file:
            config = json.load(file)
            self.username = config['username']
            self.password = config['password']
            self.hostname = config['hostname']
            self.port = config['port']
            # Generate a unique ID for this client instance
            self.unique_id = str(uuid.uuid4())
        
        print(f"Client initialized with username: {self.username}, unique_id: {self.unique_id}")
        Client.active_clients.append(self.unique_id)

        # Start the heartbeat thread
        self.heartbeat_thread = threading.Thread(target=self.send_heartbeat)
        self.heartbeat_thread.daemon = True
        self.heartbeat_thread.start()

        # Start the command polling thread
        self.polling_thread = threading.Thread(target=self.poll_commands)
        self.polling_thread.daemon = True
        self.polling_thread.start()

    def send_command(self, command):
        url = f'http://{self.hostname}:{self.port}'
        credentials = f"{self.username}:{self.password}"
        encoded_credentials = base64.b64encode(credentials.encode()).decode('utf-8')
        headers = {
            'Authorization': f'Basic {encoded_credentials}',
            'Content-Type': 'text/plain'
        }

        retry_interval = 5  # Initial retry interval in seconds
        max_retry_interval = 20  # Maximum retry interval in seconds
        retry_duration = 60  # Duration to retry every 5 seconds before switching to max_retry_interval

        start_time = time.time()
        while True:
            try:
                response = requests.post(url, headers=headers, data=command, timeout=10)  # Set timeout to 10 seconds
                print(f"Received response: {response.text}")
                return response.text
            except requests.exceptions.ConnectionError as e:
                print(f"Connection error: {e}")
            except requests.exceptions.ReadTimeout as e:
                print(f"Read timeout: {e}")

            elapsed_time = time.time() - start_time
            if elapsed_time > retry_duration:
                retry_interval = max_retry_interval
            print(f"Retrying in {retry_interval} seconds...")
            time.sleep(retry_interval)

    def send_heartbeat(self):
        while True:
            command = f"HEARTBEAT {self.unique_id}"
            self.send_command(command)
            time.sleep(10)  # Send heartbeat every 10 seconds

    def poll_commands(self):
        while True:
            command = f"POLL_COMMANDS {self.unique_id}"
            response = self.send_command(command)
            commands = json.loads(response)
            for cmd, value in commands:
                if cmd == "CHANGE_TRACK":
                    print(f"Changing track to {value}")
                elif cmd == "CHANGE_VOLUME":
                    print(f"Changing volume to {value}")
            time.sleep(5)  # Poll for commands every 5 seconds

    def get_clients(self):
        command = "GET_CLIENTS"
        response = self.send_command(command)
        print(f"Received client list: {response}")
        if not response:
            print("Error: Received empty response from server")
            return []
        try:
            return json.loads(response)
        except json.JSONDecodeError:
            print("Error: Failed to decode JSON response")
            return []

    def change_track(self, client_id, new_track_number):
        command = f"CHANGE_TRACK {client_id} {new_track_number}"
        self.send_command(command)

    def change_volume(self, client_id, new_volume_number):
        command = f"CHANGE_VOLUME {client_id} {new_volume_number}"
        self.send_command(command)

def main():
    client = Client()

    while True:
        print("\nOptions:")
        print("1. Change Track")
        print("2. Change Volume")
        print("3. Exit")
        choice = input("Enter your choice: ")

        if choice in ['1', '2']:
            clients = client.get_clients()
            if not clients:
                print("No active clients found.")
                continue

            print("Active clients:")
            for idx, client_id in enumerate(clients, start=1):
                print(f"{idx}. {client_id}")

            try:
                client_choice = int(input("Enter the number of the client: "))
                if 1 <= client_choice <= len(clients):
                    client_id = clients[client_choice - 1]
                else:
                    print("Invalid choice. Please try again.")
                    continue
            except ValueError:
                print("Invalid input. Please enter a number.")
                continue

            if choice == '1':
                new_track_number = input("Enter new track number: ")
                client.change_track(client_id, new_track_number)
            elif choice == '2':
                new_volume_number = input("Enter new volume number: ")
                client.change_volume(client_id, new_volume_number)
        elif choice == '3':
            print("Exiting...")
            break
        else:
            print("Invalid choice. Please try again.")

if __name__ == "__main__":
    main()