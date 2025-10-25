# WISP

![WISP Logo](offline/assests/logo-full-size.png)

## Overview

WISP is a Windows system management tool designed to collect and process remote system data. The project offers two operational modes to suit different deployment scenarios.

## Modes

### Offline

The offline mode provides a comprehensive system reporting solution that runs directly on Windows machines without requiring network infrastructure.

**Key Features:**

- Generates detailed system reports in JSON for HTML formats
- Supports both local and remote computer analysis
- Utilizes Windows Management Instrumentation (WMI) and PowerShell
- Includes Sysinternals Suite integration for advanced diagnostics
- Produces IT support-ready analysis reports

**Use Cases:**

- Stand-alone system diagnostics
- On-site troubleshooting
- Single machine analysis
- Isolated environments

### Online

**Status: Work in Progress**

The online mode is a Node.js-based server application that acts as a secure PsExec wrapper, enabling centralized remote script execution across multiple Windows machines on a local area network.

**Planned Features:**

- Express.js web server for remote command execution
- Token-based authentication system
- Rate limiting and security controls
- Centralized logging and monitoring
- LAN-only operation for enhanced security
- Automated setup and verification scripts
- Support for executing system reports and diagnostic scripts remotely

**Use Cases:**

- Managing multiple workstations from a central location
- Automated system inventory collection
- Scheduled diagnostics across a network
- IT department tools for enterprise environments

**Note:** This mode requires Node.js 18.0.0 or higher and is designed exclusively for trusted local area networks.

## Getting Started

Navigate to [Releases](https://github.com/JoshWalki/WISP/releases/) to download the latest build.
