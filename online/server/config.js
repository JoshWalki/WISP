/**
 * WISP Companion Configuration
 * Security-critical settings for task and host allow-lists
 */

const path = require("path");
const fs = require("fs");

// Load environment variables from .env file (custom loader)
const { loadEnv } = require("./env-loader");
loadEnv();

/**
 * Find PsExec in common locations
 */
function findPsExec() {
  const appRoot = path.join(__dirname, "..");

  // Check environment variable first
  if (process.env.PSEXEC_PATH && fs.existsSync(process.env.PSEXEC_PATH)) {
    return process.env.PSEXEC_PATH;
  }

  // Check in app directory (D:\GeneralSupportApp\SysinternalsSuite\)
  const localSuite = path.join(appRoot, "SysinternalsSuite", "PsExec.exe");
  if (fs.existsSync(localSuite)) {
    return localSuite;
  }

  // Check in app root (D:\GeneralSupportApp\PsExec.exe)
  const localRoot = path.join(appRoot, "PsExec.exe");
  if (fs.existsSync(localRoot)) {
    return localRoot;
  }

  // Fall back to C:\SysinternalsSuite\
  return "C:\\SysinternalsSuite\\PsExec.exe";
}

module.exports = {
  // Server configuration
  server: {
    host: "127.0.0.1", // SECURITY: Bind to localhost only
    port: process.env.WISP_PORT || 8765,
    environment: process.env.NODE_ENV || "production",
  },

  // Authentication
  auth: {
    // Token stored in environment variable or Windows Credential Manager
    token: process.env.WISP_TOKEN || null,
    headerName: "X-WISP-Token",
  },

  // PsExec configuration
  psexec: {
    // Path to PsExec.exe (Sysinternals Suite)
    // Automatically searches: env var, script dir\SysinternalsSuite\, script dir\, then C:\SysinternalsSuite\
    path: findPsExec(),
    // Default timeout in milliseconds (5 minutes)
    timeout: 300000,
    // Auto-accept EULA
    acceptEula: true,
    // Remote credentials (optional - uses current user context if not provided)
    // Domain environment: Leave null to use service account credentials
    // Workgroup environment: Provide explicit credentials
    credentials: {
      username: process.env.PSEXEC_USERNAME || null,
      password: process.env.PSEXEC_PASSWORD || null,
      domain: process.env.PSEXEC_DOMAIN || null,
    },
  },

  // Scripts directory (secured with NTFS ACLs)
  scripts: {
    basePath: path.join(__dirname, "..", "scripts"),
    // Allowed scripts directory - defaults to app directory, falls back to C:\WISP\scripts
    allowedPath:
      process.env.WISP_SCRIPTS_PATH ||
      (fs.existsSync(path.join(__dirname, "..", "scripts"))
        ? path.join(__dirname, "..", "scripts")
        : "C:\\WISP\\scripts"),
  },

  // Task allow-list - SECURITY CRITICAL
  // Only these named tasks can be executed
  allowedTasks: {
    "system-report": {
      description: "Run comprehensive system report",
      script: "SystemReport.bat",
      args: [],
      runAs: "admin", // requires admin rights
    },
    gpupdate: {
      description: "Force Group Policy update",
      script: "cmd.exe",
      args: ["/c", "gpupdate", "/force"],
      runAs: "admin",
    },
    "test-connection": {
      description: "Test network connectivity",
      script: "cmd.exe",
      args: ["/c", "ping", "-n", "4", "127.0.0.1"],
      runAs: "user",
    },
    "ipconfig-renew": {
      description: "Renew DHCP lease",
      script: "cmd.exe",
      args: ["/c", "ipconfig", "/renew"],
      runAs: "admin",
    },
    "ipconfig-release": {
      description: "Release DHCP lease",
      script: "cmd.exe",
      args: ["/c", "ipconfig", "/release"],
      runAs: "admin",
    },
    "ipconfig-flushdns": {
      description: "Flush DNS resolver cache",
      script: "cmd.exe",
      args: ["/c", "ipconfig", "/flushdns"],
      runAs: "admin",
    },
    "dism-restorehealth": {
      description: "DISM repair Windows image",
      script: "cmd.exe",
      args: ["/c", "DISM", "/Online", "/Cleanup-Image", "/RestoreHealth"],
      runAs: "admin",
    },
    "sfc-scannow": {
      description: "System File Checker scan",
      script: "cmd.exe",
      args: ["/c", "sfc", "/scannow"],
      runAs: "admin",
    },
    "restart-computer": {
      description: "Restart computer with 10 second warning",
      script: "cmd.exe",
      args: [
        "/c",
        "shutdown",
        "/r",
        "/t",
        "10",
        "/c",
        '"WISP: System restart initiated by administrator. Please save your work."',
      ],
      runAs: "admin",
      interactive: true  // Run interactively so shutdown message is displayed to users
    },
  },

  // Host allow-list patterns - SECURITY CRITICAL
  // Regex patterns for allowed target hostnames/IPs
  allowedHostPatterns: [
    /^[A-Z0-9\-]{1,15}$/i, // Standard NetBIOS names
    /^192\.168\.\d{1,3}\.\d{1,3}$/, // 192.168.x.x subnet
    /^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$/, // 10.x.x.x subnet
    /^172\.(1[6-9]|2[0-9]|3[0-1])\.\d{1,3}\.\d{1,3}$/, // 172.16-31.x.x subnet
  ],

  // Audit logging
  logging: {
    level: process.env.LOG_LEVEL || "info",
    file: path.join(__dirname, "logs", "audit.log"),
    maxFiles: 30,
    maxSize: "10m",
  },

  // Rate limiting
  rateLimit: {
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // limit each IP to 100 requests per windowMs
    message: "Too many requests from this IP, please try again later",
  },

  // CORS settings (localhost only)
  cors: {
    origin: ["http://127.0.0.1:8765", "http://localhost:8765", "null"], // 'null' for file:// protocol
    credentials: true,
    methods: ["GET", "POST"],
    allowedHeaders: ["Content-Type", "X-WISP-Token"],
  },
};
