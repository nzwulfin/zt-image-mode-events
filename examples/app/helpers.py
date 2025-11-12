# helpers.py

import platform
import os
import subprocess
import importlib.metadata
import distro # You'll need to install this: pip install distro
import math

def _get_linux_cpu_info():
    """Helper function to parse /proc/cpuinfo to get the CPU model name on Linux."""
    try:
        with open('/proc/cpuinfo', 'r') as f:
            for line in f:
                # Find the line that starts with "model name"
                if line.strip().startswith("model name"):
                    # The value is after the colon, strip whitespace
                    processor_name = line.split(':', 1)[1].strip()
                    # We only need the first one we find
                    return processor_name
    except FileNotFoundError:
        # This can happen on non-Linux systems or minimalist containers
        return None
    except Exception as e:
        print(f"An error occurred while reading /proc/cpuinfo: {e}")
        return None
    # Return None if the "model name" line was not found
    return None

def get_image_mode_state():
    """Get the operating mode based on the presence of /run/ostree-booted"""
    try:
        os.stat('/run/ostree-booted')
        return f'Image'
    except FileNotFoundError:
        # This file doesn't exist on non-rpm-ostree / bootc hosts
        return f'Package'
    except Exception as e:
        print(f"An error occurred while reading /run/ostree-booted: {e}")
        return None

def get_os_info():
    """
    Retrieves basic OS and kernel information.
    """
    # Start with the default platform.processor() result
    processor_info = platform.processor()

    # On Linux, platform.processor() is often empty. Try our better method.
    if platform.system() == 'Linux':
        linux_cpu = _get_linux_cpu_info()
        if linux_cpu:
            processor_info = linux_cpu

    # If the result is still empty after all attempts, set it to "N/A"
    if not processor_info:
        processor_info = "N/A"

    info = {
        'system': platform.system(),
        'node': platform.node(),
        'release': platform.release(),
        'version': platform.version(),
        'machine': platform.machine(),
        'processor': processor_info, # Use our more reliable variable
    }

    # Add Linux distribution details if available
    if info['system'] == 'Linux':
        try:
            info['distro_name'] = distro.name(pretty=True)
            info['distro_id'] = distro.id()
            info['distro_version'] = distro.version(pretty=True)
            info['distro_codename'] = distro.codename()
        except Exception:
            info['distro_name'] = 'N/A (distro lib error)'
            info['distro_id'] = 'unknown'
    elif info['system'] == 'Darwin':
        try:
            mac_ver = platform.mac_ver()
            info['distro_name'] = f"macOS {mac_ver[0]}"
            info['distro_id'] = 'macos'
        except Exception:
            info['distro_name'] = 'macOS (version unavailable)'
            info['distro_id'] = 'macos'
    elif info['system'] == 'Windows':
        info['distro_name'] = f"Windows {info['release']}"
        info['distro_id'] = 'windows'
    else:
        info['distro_name'] = 'Unknown OS'
        info['distro_id'] = 'unknown'

    return info

def get_system_uptime():
    """Retrieves system uptime (Linux only)."""
    try:
        with open('/proc/uptime', 'r') as f:
            uptime_seconds = float(f.readline().split()[0])
            days = math.floor(uptime_seconds / 86400)
            hours = math.floor((uptime_seconds % 86400) / 3600)
            minutes = math.floor((uptime_seconds % 3600) / 60)
            return f"{days}d {hours}h {minutes}m"
    except FileNotFoundError:
        return "N/A (Linux only)"
    except Exception:
        return "Error"

def get_python_package_version(package_name):
    """
    Retrieves the version of an installed Python package.
    """
    try:
        return importlib.metadata.version(package_name)
    except importlib.metadata.PackageNotFoundError:
        return "Not Found"
    except Exception as e:
        return f"Error: {str(e)}"

def get_system_package_version(package_name, os_id='unknown'):
    """
    Retrieves the version of an installed system package.
    """
    command = []
    if not package_name:
        return "N/A (No package name)"

    os_id_lower = os_id.lower()

    if any(dist in os_id_lower for dist in ['ubuntu', 'debian', 'mint']):
        command = ['dpkg-query', '-W', '-f=${Version}', package_name]
    elif any(dist in os_id_lower for dist in ['centos', 'rhel', 'fedora', 'almalinux', 'rocky']):
        command = ['rpm', '-q', '--qf', '%{VERSION}', package_name]
    elif 'arch' in os_id_lower:
        command = ['pacman', '-Q', package_name]
    elif 'macos' in os_id_lower:
        command = ['brew', 'info', '--json=v2', package_name]
    else:
        return "Unsupported OS for system package check"

    try:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        stdout, stderr = process.communicate(timeout=5)

        if process.returncode == 0:
            version_output = stdout.strip()
            if 'arch' in os_id_lower and version_output:
                parts = version_output.split()
                return parts[1] if len(parts) > 1 and parts[0] == package_name else version_output
            elif 'macos' in os_id_lower and version_output:
                import json
                try:
                    data = json.loads(version_output)
                    if data.get('formulae') and data['formulae']:
                        return data['formulae'][0]['versions']['stable']
                    elif data.get('casks') and data['casks']:
                        return data['casks'][0]['version']
                    return "Version not found in brew output"
                except (json.JSONDecodeError, KeyError, IndexError):
                    return "Failed to parse brew JSON output"
            return version_output if version_output else "Not Found (empty output)"
        else:
            if "not found" in stderr.lower() or "no packages found" in stderr.lower() or process.returncode == 1:
                return "Not Found"
            return f"Error (code {process.returncode})"
    except FileNotFoundError:
        return f"Command not found ({command[0]})"
    except subprocess.TimeoutExpired:
        return "Command timed out"
    except Exception as e:
        return f"Execution error: {str(e)}"
