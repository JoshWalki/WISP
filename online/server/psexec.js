/**
 * WISP Companion PsExec Wrapper
 * Secure wrapper for PsExec remote execution
 */

const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");
const config = require("./config");
const { logExecution, logError } = require("./logger");
const taskTracker = require("./task-tracker");

/**
 * Check if PsExec exists
 */
function checkPsExec() {
  if (!fs.existsSync(config.psexec.path)) {
    throw new Error(`PsExec not found at: ${config.psexec.path}`);
  }
  return true;
}

/**
 * Get human-readable error message for PsExec exit codes
 */
function getPsExecErrorMessage(exitCode, stderr) {
  const errorMessages = {
    0: "Success",
    1: "General error",
    2: "Access denied - Check credentials and admin rights",
    5: "Access denied - Check credentials, firewall, and admin$ share",
    6: "Access denied - Authentication failure",
    53: "Network path not found - Check hostname/IP and network connectivity",
    64: "Network name not found - Target host unreachable",
    67: "Network name limit exceeded",
    1219: "Multiple connections to a server using more than one username are not allowed",
    1326: "Invalid username or password",
    1327: "Account restrictions prevent login",
    1385: "Logon failure - User not granted requested logon type (add interactive: true to task config)",
    1396: "Login failure - Check credentials",
    1722: "RPC server unavailable - Check firewall and Windows Remote Management settings",
  };

  const baseMessage =
    errorMessages[exitCode] || `Unknown PsExec error (exit code ${exitCode})`;

  if (exitCode === 6) {
    const hasCredentials = config.psexec.credentials.username;

    if (hasCredentials) {
      return `${baseMessage}. The provided credentials are invalid or do not have admin rights on the target machine.`;
    } else {
      return (
        `${baseMessage}. The service account does not have admin rights on the target machine. Either:\n` +
        `1. Run the service as a domain admin account, OR\n` +
        `2. Configure explicit credentials in .env (PSEXEC_USERNAME, PSEXEC_PASSWORD)`
      );
    }
  }

  return baseMessage;
}

/**
 * Build PsExec command arguments
 */
function buildPsExecArgs(hostname, task) {
  const args = [];

  // Target hostname
  args.push(`\\\\${hostname}`);

  // Add credentials if configured
  // If not provided, PsExec will use the current user's credentials (domain admin context)
  if (config.psexec.credentials.username) {
    // Domain\Username or just Username
    const username = config.psexec.credentials.domain
      ? `${config.psexec.credentials.domain}\\${config.psexec.credentials.username}`
      : config.psexec.credentials.username;

    args.push("-u", username);

    if (config.psexec.credentials.password) {
      args.push("-p", config.psexec.credentials.password);
    }
  }

  // Accept EULA automatically
  if (config.psexec.acceptEula) {
    args.push("-accepteula");
  }

  // Run with elevated privileges if needed
  if (task.runAs === "admin") {
    args.push("-h"); // Run with elevated token
  }

  // Special handling for system-report task - use SYSTEM account to avoid session issues
  if (task.useSystemAccount) {
    args.push("-s"); // Run as SYSTEM account (bypasses session/interactive issues)
  }
  // Run in background (no interaction) - unless task requires interactive mode
  // Interactive mode is needed for tasks like shutdown that display messages to users
  else if (task.interactive) {
    // Interactive mode - required for some local accounts
    // If session is specified, use -i [session] to show window in that user's session
    // Otherwise, use -i alone (defaults to Session 0, which is invisible)
    if (task.session) {
      args.push("-i", task.session.toString());
    } else {
      args.push("-i");
    }
  } else {
    args.push("-d"); // Detached mode - don't wait for process
  }

  // Add script/command and its arguments
  if (task.script.endsWith(".bat") || task.script.endsWith(".ps1")) {
    // Full path to script
    const scriptPath = path.join(config.scripts.allowedPath, task.script);

    // Verify script exists and is in allowed directory
    if (!scriptPath.startsWith(config.scripts.allowedPath)) {
      throw new Error("Script path traversal attempt detected");
    }

    if (!fs.existsSync(scriptPath)) {
      throw new Error(`Script not found: ${scriptPath}`);
    }

    // Copy script to remote machine with -c flag
    args.push("-c");

    if (task.script.endsWith(".bat")) {
      args.push("cmd.exe", "/c", scriptPath);
      // Add hostname as first argument to batch scripts
      args.push(hostname);
      // Add any additional task-specific arguments
      if (task.args && task.args.length > 0) {
        args.push(...task.args);
      }
    } else if (task.script.endsWith(".ps1")) {
      args.push(
        "powershell.exe",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        scriptPath
      );
      // Add hostname as first argument to PowerShell scripts
      args.push(hostname);
      // Add any additional task-specific arguments
      if (task.args && task.args.length > 0) {
        args.push(...task.args);
      }
    }
  } else {
    // Direct command (like cmd.exe)
    args.push(task.script);
    if (task.args && task.args.length > 0) {
      args.push(...task.args);
    }
  }

  return args;
}

/**
 * Execute task locally without PsExec
 */
async function executeLocalTask(taskName, task, metadata = {}, taskId = null) {
  const hostname = require("os").hostname();

  let command, args;

  if (task.script.endsWith(".bat") || task.script.endsWith(".ps1")) {
    const scriptPath = path.join(config.scripts.allowedPath, task.script);

    if (!fs.existsSync(scriptPath)) {
      throw new Error(`Script not found: ${scriptPath}`);
    }

    if (task.script.endsWith(".bat")) {
      command = "cmd.exe";
      args = ["/c", scriptPath, hostname];
    } else {
      command = "powershell.exe";
      args = ["-ExecutionPolicy", "Bypass", "-File", scriptPath, hostname];
    }

    // Add any additional args
    if (task.args && task.args.length > 0) {
      args.push(...task.args);
    }
  } else {
    command = task.script;
    args = task.args || [];
  }

  // Log execution
  logExecution(taskName, hostname, metadata.username, metadata.ip, {
    task: task.description,
    command: `${command} ${args.join(" ")}`,
    local: true,
  });

  // Execute locally
  return new Promise((resolve, reject) => {
    const proc = spawn(command, args, {
      cwd: path.join(config.scripts.allowedPath, ".."), // Run from root directory
      windowsHide: false, // Show window for debugging
      detached: false, // Don't detach - wait for completion
      stdio: ["ignore", "pipe", "pipe"],
      env: { ...process.env, PYTHONUNBUFFERED: "1" }, // Disable Python buffering
    });

    let stdout = "";
    let stderr = "";

    if (proc.stdout) {
      proc.stdout.setEncoding("utf8"); // Set encoding for immediate string conversion
      proc.stdout.resume(); // Force stream to flowing mode to prevent buffering
      proc.stdout.on("data", (data) => {
        const output = data.toString();
        stdout += output;
        // Emit incremental output to task tracker if taskId is provided
        if (taskId) {
          taskTracker.appendStdout(taskId, output);
        }
      });
    }

    if (proc.stderr) {
      proc.stderr.setEncoding("utf8"); // Set encoding for immediate string conversion
      proc.stderr.resume(); // Force stream to flowing mode to prevent buffering
      proc.stderr.on("data", (data) => {
        const output = data.toString();
        stderr += output;
        // Emit incremental output to task tracker if taskId is provided
        if (taskId) {
          taskTracker.appendStderr(taskId, output);
          console.log(
            `[executeLocalTask] Appended stderr (${output.length} chars) to task ${taskId}`
          );
        }
      });
    }

    // Set timeout (use task-specific timeout if defined, otherwise use global default)
    const timeoutMs = task.timeout || config.psexec.timeout;
    const timeout = setTimeout(() => {
      proc.kill();
      reject(new Error("Execution timeout exceeded"));
    }, timeoutMs);

    proc.on("close", (code) => {
      clearTimeout(timeout);

      const result = {
        success: code === 0,
        exitCode: code,
        stdout: stdout.trim(),
        stderr: stderr.trim(),
        taskName,
        hostname,
        timestamp: new Date().toISOString(),
      };

      if (code === 0) {
        logExecution(taskName, hostname, metadata.username, metadata.ip, {
          status: "completed",
          exitCode: code,
        });
        // Update task tracker if taskId is provided
        if (taskId) {
          taskTracker.completeTask(taskId, result);
        }
        resolve(result);
      } else {
        logError(new Error(`Task exited with code ${code}`), {
          taskName,
          hostname,
          stderr: stderr.trim(),
        });
        // Update task tracker if taskId is provided
        if (taskId) {
          taskTracker.failTask(taskId, `Task exited with code ${code}`);
        }
        resolve(result); // Still resolve for local execution
      }
    });

    proc.on("error", (error) => {
      clearTimeout(timeout);
      logError(error, { taskName, hostname });
      reject(error);
    });

    // Don't unref for local execution - we need to wait for completion
  });
}

/**
 * Execute task on remote host using PsExec
 * @param {string} taskName - Name of the task from allow-list
 * @param {string} hostname - Target hostname
 * @param {object} metadata - Additional execution metadata
 * @param {string} taskId - Optional task ID for tracking
 * @returns {Promise} Promise that resolves with execution result
 */
async function executeRemoteTask(
  taskName,
  hostname,
  metadata = {},
  taskId = null
) {
  try {
    // Get task configuration
    const task = config.allowedTasks[taskName];
    if (!task) {
      throw new Error(`Task '${taskName}' not found in allow-list`);
    }

    // Check if this is local execution
    const localHostname = require("os").hostname();
    if (
      hostname.toLowerCase() === localHostname.toLowerCase() ||
      hostname.toLowerCase() === "localhost" ||
      hostname === "127.0.0.1"
    ) {
      // Execute locally without PsExec
      return executeLocalTask(taskName, task, metadata, taskId);
    }

    // Verify PsExec exists for remote execution
    checkPsExec();

    // Build command arguments
    const args = buildPsExecArgs(hostname, task);

    // Log execution attempt
    logExecution(taskName, hostname, metadata.username, metadata.ip, {
      task: task.description,
      args: args.join(" "),
    });

    // Spawn PsExec process
    return new Promise((resolve, reject) => {
      const psexec = spawn(config.psexec.path, args, {
        windowsHide: true,
        detached: true,
        stdio: ["ignore", "pipe", "pipe"],
        env: { ...process.env, PYTHONUNBUFFERED: "1" }, // Disable Python buffering
      });

      let stdout = "";
      let stderr = "";

      // Capture output
      if (psexec.stdout) {
        psexec.stdout.setEncoding("utf8"); // Set encoding for immediate string conversion
        psexec.stdout.resume(); // Force stream to flowing mode to prevent buffering
        psexec.stdout.on("data", (data) => {
          const output = data.toString();
          stdout += output;
          // Emit incremental output to task tracker if taskId is provided
          if (taskId) {
            taskTracker.appendStdout(taskId, output);
            console.log(
              `[executeRemoteTask] Appended stdout (${output.length} chars) to task ${taskId}`
            );
          }
        });
      }

      if (psexec.stderr) {
        psexec.stderr.setEncoding("utf8"); // Set encoding for immediate string conversion
        psexec.stderr.resume(); // Force stream to flowing mode to prevent buffering
        psexec.stderr.on("data", (data) => {
          const output = data.toString();
          stderr += output;
          // Emit incremental output to task tracker if taskId is provided
          if (taskId) {
            taskTracker.appendStderr(taskId, output);
            console.log(
              `[executeRemoteTask] Appended stderr (${output.length} chars) to task ${taskId}`
            );
          }
        });
      }

      // Set timeout (use task-specific timeout if defined, otherwise use global default)
      const timeoutMs = task.timeout || config.psexec.timeout;
      const timeout = setTimeout(() => {
        psexec.kill();
        reject(new Error("Execution timeout exceeded"));
      }, timeoutMs);

      // Handle process completion
      psexec.on("close", (code) => {
        clearTimeout(timeout);

        const result = {
          success: code === 0,
          exitCode: code,
          stdout: stdout.trim(),
          stderr: stderr.trim(),
          taskName,
          hostname,
          timestamp: new Date().toISOString(),
        };

        if (code === 0) {
          logExecution(taskName, hostname, metadata.username, metadata.ip, {
            status: "completed",
            exitCode: code,
          });
          // Update task tracker if taskId is provided
          if (taskId) {
            taskTracker.completeTask(taskId, result);
          }
          resolve(result);
        } else {
          const errorMessage = getPsExecErrorMessage(code, stderr.trim());
          logError(
            new Error(`PsExec exited with code ${code}: ${errorMessage}`),
            {
              taskName,
              hostname,
              exitCode: code,
              stderr: stderr.trim(),
            }
          );
          // Update task tracker if taskId is provided
          if (taskId) {
            taskTracker.failTask(taskId, errorMessage);
          }
          reject(new Error(`${errorMessage}\n\nDetails: ${stderr.trim()}`));
        }
      });

      psexec.on("error", (error) => {
        clearTimeout(timeout);
        logError(error, { taskName, hostname });
        // Update task tracker if taskId is provided
        if (taskId) {
          taskTracker.failTask(taskId, error.message);
        }
        reject(error);
      });

      // Unref to allow process to continue in background for fire-and-forget tasks
      psexec.unref();
    });
  } catch (error) {
    logError(error, { taskName, hostname });
    throw error;
  }
}

/**
 * Get list of available tasks
 */
function getAvailableTasks() {
  return Object.entries(config.allowedTasks).map(([name, task]) => ({
    name,
    description: task.description,
    requiresAdmin: task.runAs === "admin",
  }));
}

module.exports = {
  executeRemoteTask,
  getAvailableTasks,
  checkPsExec,
};
