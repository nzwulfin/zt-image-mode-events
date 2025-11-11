# In app.py

import json
import os
from datetime import datetime
from flask import Flask, render_template, jsonify # <-- Add jsonify
from helpers import get_os_info, get_python_package_version, get_system_package_version, get_system_uptime, get_image_mode_state

app = Flask(__name__)

# Path to the config file
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(BASE_DIR, 'config.json')

def load_config():
    """Loads the configuration from config.json."""
    try:
        with open(CONFIG_FILE, 'r') as f:
            config = json.load(f)
        return config
    except FileNotFoundError:
        print(f"Error: {CONFIG_FILE} not found. Returning empty config.")
        return {"python_packages": [], "system_packages": []}
    except json.JSONDecodeError:
        print(f"Error: Could not decode {CONFIG_FILE}. Returning empty config.")
        return {"python_packages": [], "system_packages": []}

def get_all_data():
    """Helper function to gather all system data."""
    config = load_config()
    os_details = get_os_info()
   
    os_details['uptime'] = get_system_uptime()

    current_os_id = os_details.get('distro_id', 'unknown')
    if os_details.get('system') == 'Darwin':
        current_os_id = 'macos'
    elif os_details.get('system') == 'Windows':
        current_os_id = 'windows'

    os_details['mode'] = get_image_mode_state()

    python_pkg_versions = [
        {"name": pkg_name, "version": get_python_package_version(pkg_name)}
        for pkg_name in config.get("python_packages", [])
    ]

    system_pkg_versions = [
        {"name": pkg_name, "version": get_system_package_version(pkg_name, current_os_id)}
        for pkg_name in config.get("system_packages", [])
    ]
    
    return {
        "os_details": os_details,
        "python_packages": python_pkg_versions,
        "system_packages": system_pkg_versions,
        "last_updated": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }

@app.route('/')
def index():
    """Main route to render the HTML page."""
    # The initial page load can be faster if it doesn't wait for all data
    # But for simplicity, we'll load it once initially.
    # The JS will handle subsequent updates.
    return render_template('index.html')

@app.route('/data')
def data():
    """API endpoint to serve system data as JSON."""
    all_data = get_all_data()
    return jsonify(all_data)

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
