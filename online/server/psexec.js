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
    2250: "Network connection not found - clear a stale session with 'net use \\\\<host> /delete' on this machine, or check the target's local policy for 'Network access: Sharing and security model for local accounts' (must not be Guest only)",
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
 * Resolve the configured PsExec username, expanding the "." workgroup
 * shorthand (meaning "a local account on the TARGET machine") to the actual
 * per-call target hostname - "." itself resolves against the machine running
 * PsExec, not the remote target, so it can't be passed through literally.
 */
function getQualifiedUsername(hostname) {
  let domainQualifier = config.psexec.credentials.domain;
  if (domainQualifier === ".") {
    domainQualifier = hostname;
  }

  return domainQualifier
    ? `${domainQualifier}\\${config.psexec.credentials.username}`
    : config.psexec.credentials.username;
}

/**
 * Substitute "{{key}}" placeholders in task args with caller-supplied
 * values (e.g. a user-typed message for the show-message task). Only args
 * that are an exact "{{key}}" token get replaced - params have no effect on
 * tasks whose config doesn't declare a matching placeholder.
 */
function substitutePlaceholders(args, params) {
  if (!params) {
    return args;
  }
  return args.map((arg) => {
    const match = /^\{\{(\w+)\}\}$/.exec(arg);
    return match && Object.prototype.hasOwnProperty.call(params, match[1])
      ? params[match[1]]
      : arg;
  });
}

/**
 * Build PsExec command arguments
 */
function buildPsExecArgs(hostname, task, params) {
  const taskArgs = substitutePlaceholders(task.args || [], params);
  const args = [];

  // Target hostname
  args.push(`\\\\${hostname}`);

  // Add credentials if configured
  // If not provided, PsExec will use the current user's credentials (domain admin context)
  if (config.psexec.credentials.username) {
    args.push("-u", getQualifiedUsername(hostname));

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

    if (task.script.endsWith(".bat")) {
      // -c copies scriptPath itself to the remote machine and executes that
      // copy directly (via its .bat file association). The previous version
      // put "cmd.exe" right after -c, which copied cmd.exe (a no-op, it's
      // already on every Windows machine) and then told the REMOTE cmd.exe
      // to open scriptPath at its LOCAL path on this WISP host - a path that
      // doesn't exist on the target, so the script never actually ran there.
      args.push("-c", scriptPath);
      // Add hostname as first argument to batch scripts
      args.push(hostname);
      // Add any additional task-specific arguments
      if (taskArgs.length > 0) {
        args.push(...taskArgs);
      }
    } else if (task.script.endsWith(".ps1")) {
      // NOTE: -c can only copy+execute a single file, so it can't be used to
      // copy a .ps1 while executing powershell.exe. Staging (plain SMB copy)
      // the script to the remote machine first, then invoking powershell.exe
      // -File against that path without -c, would be required before any
      // .ps1 task is added to allowedTasks - this branch is unused today.
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
      if (taskArgs.length > 0) {
        args.push(...taskArgs);
      }
    }
  } else {
    // Direct command (like cmd.exe)
    args.push(task.script);
    if (taskArgs.length > 0) {
      args.push(...taskArgs);
    }
  }

  return args;
}

/**
 * Convert a local Windows path (as seen ON the target machine, e.g.
 * "C:\Windows\Temp") into the equivalent admin-share UNC path reachable from
 * this host (e.g. "\\hostname\C$\Windows\Temp").
 */
function toAdminShareUncPath(hostname, localPath) {
  const match = localPath.match(/^([A-Za-z]):\\(.*)$/);
  if (!match) {
    throw new Error(`Cannot convert to admin-share path: ${localPath}`);
  }
  const [, driveLetter, rest] = match;
  return `\\\\${hostname}\\${driveLetter}$\\${rest}`;
}

/**
 * Run a `net` command (used to establish/tear down the SMB session needed to
 * read the target's admin share) and resolve/reject on completion.
 */
function runNetCommand(args) {
  return new Promise((resolve, reject) => {
    const proc = spawn("net", args, { windowsHide: true });
    let stderr = "";
    if (proc.stderr) {
      proc.stderr.on("data", (data) => (stderr += data.toString()));
    }
    proc.on("close", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(stderr.trim() || `net exited with code ${code}`));
      }
    });
    proc.on("error", reject);
  });
}

/**
 * Quick reachability check - a single 2-second ping. Used to fail fast with
 * a clear "offline" message rather than stumbling through a slow session
 * retry sequence and surfacing a confusing low-level SMB/filesystem error
 * when the real problem is simply that the device isn't on the network.
 */
function isHostReachable(hostname) {
  return new Promise((resolve) => {
    const proc = spawn("ping", ["-n", "1", "-w", "2000", hostname], {
      windowsHide: true,
    });
    proc.on("close", (code) => resolve(code === 0));
    proc.on("error", () => resolve(false));
  });
}

/**
 * Run fn() (a synchronous function touching \\hostname\C$\... paths) against
 * the target's admin share. Tries it directly first, since PsExec (or
 * whatever else touched this host) likely already left a usable
 * authenticated session in place, and proactively opening a second
 * explicit-credential connection on top of that is exactly what causes
 * "multiple connections, different usernames" (1219) errors. Only falls back
 * to establishing our own connection - and only tears it down afterward - if
 * the direct attempt didn't work.
 */
async function withAdminShareAccess(hostname, fn) {
  try {
    return fn();
  } catch (directError) {
    if (!config.psexec.credentials.username) {
      throw directError;
    }
  }

  const reachable = await isHostReachable(hostname);
  if (!reachable) {
    throw new Error(
      `${hostname} appears to be offline or unreachable on the network`
    );
  }

  let openedOwnSession = false;
  try {
    await runNetCommand([
      "use",
      `\\\\${hostname}\\C$`,
      config.psexec.credentials.password,
      `/user:${getQualifiedUsername(hostname)}`,
    ]);
    openedOwnSession = true;
  } catch (netError) {
    if (!/already/i.test(netError.message)) {
      throw new Error(`Could not open admin share: ${netError.message}`);
    }
  }

  try {
    return fn();
  } catch (retryError) {
    // Transient SMB hiccups against this fleet have shown up repeatedly
    // throughout this project (1219 conflicts, stale sessions, etc.) - give
    // it one more chance after a short pause before giving up. If it still
    // fails, surface whatever extra detail Node attached (code/syscall),
    // since "UNKNOWN: unknown error" alone isn't actionable - that's Node's
    // generic fallback message for a Windows/UNC I/O failure it can't map
    // to a clean errno.
    await new Promise((resolve) => setTimeout(resolve, 1500));
    try {
      return fn();
    } catch (finalError) {
      const details = [finalError.message];
      if (finalError.code) details.push(`code=${finalError.code}`);
      if (finalError.syscall) details.push(`syscall=${finalError.syscall}`);
      if (finalError.errno !== undefined) details.push(`errno=${finalError.errno}`);
      throw new Error(details.join(" "));
    }
  } finally {
    if (openedOwnSession) {
      try {
        await runNetCommand(["use", `\\\\${hostname}`, "/delete"]);
      } catch (_) {
        // Best-effort cleanup - not fatal if it was already gone.
      }
    }
  }
}

/**
 * Copy generate_json.ps1 onto the target before the batch script runs there.
 * PsExec's -c only copies the single .bat file being executed, not its
 * assests\ dependency, so the script's own JSON-generation step (which shells
 * out to "%ROOT_DIR%\assests\generate_json.ps1") would otherwise silently
 * fail to find it. This matters beyond just "the file is missing": that
 * script does its own live queries (installed apps, recent event log errors,
 * battery, network adapter config) which must run ON the target - if it ran
 * anywhere else, those fields would reflect the wrong machine.
 */
async function stageRemoteAssets(hostname, task) {
  if (!task.remoteWorkDir) {
    return;
  }

  const remoteAssetsDir = path.join(
    toAdminShareUncPath(hostname, task.remoteWorkDir),
    "assests"
  );
  const localGenerator = path.join(
    __dirname,
    "..",
    "assests",
    "generate_json.ps1"
  );

  try {
    await withAdminShareAccess(hostname, () => {
      fs.mkdirSync(remoteAssetsDir, { recursive: true });
      fs.copyFileSync(
        localGenerator,
        path.join(remoteAssetsDir, "generate_json.ps1")
      );
    });
  } catch (error) {
    logError(
      new Error(`Could not stage generate_json.ps1 on ${hostname}: ${error.message}`),
      { hostname }
    );
  }
}

/**
 * Fetch a report a remote task wrote to its (pinned, via remoteWorkDir)
 * remote working directory back into this host's local reports/ folder,
 * where the /reports/:host/latest endpoint expects to find it. Best-effort:
 * logs and returns quietly on failure rather than failing the overall task,
 * since the remote command itself already completed successfully by now.
 */
async function fetchRemoteReport(hostname, task) {
  if (!task.remoteWorkDir) {
    return;
  }

  const remoteBase = toAdminShareUncPath(hostname, task.remoteWorkDir);
  const remoteReportsDir = path.join(remoteBase, "reports");
  const remoteAssetsDir = path.join(remoteBase, "assests");

  try {
    await withAdminShareAccess(hostname, () => {
      if (!fs.existsSync(remoteReportsDir)) {
        throw new Error(`Remote reports folder not found: ${remoteReportsDir}`);
      }

      const hostPrefix = `${hostname.toLowerCase()}_`;
      const candidates = fs
        .readdirSync(remoteReportsDir)
        .filter((name) => name.toLowerCase().startsWith(hostPrefix))
        .map((name) => {
          const fullPath = path.join(remoteReportsDir, name);
          return { name, fullPath, mtime: fs.statSync(fullPath).mtimeMs };
        })
        .sort((a, b) => b.mtime - a.mtime);

      if (candidates.length === 0) {
        throw new Error(`No report folder for ${hostname} in ${remoteReportsDir}`);
      }

      const latest = candidates[0];
      const localReportsDir = path.join(__dirname, "..", "reports");
      const localDest = path.join(localReportsDir, latest.name);

      fs.mkdirSync(localReportsDir, { recursive: true });
      fs.cpSync(latest.fullPath, localDest, { recursive: true });

      // Don't leave IT diagnostic data (hardware/software/network detail)
      // sitting on the end-user's machine once we have our own copy.
      fs.rmSync(latest.fullPath, { recursive: true, force: true });

      // Also remove the staged generator script - it's tooling, not
      // something that should live on the endpoint permanently.
      fs.rmSync(remoteAssetsDir, { recursive: true, force: true });

      logExecution("system-report", hostname, null, null, {
        status: "report-fetched",
        localPath: localDest,
      });
    });
  } catch (error) {
    logError(new Error(`Failed to fetch report from ${hostname}: ${error.message}`), {
      hostname,
    });
  }
}

/**
 * Execute task locally without PsExec
 */
async function executeLocalTask(
  taskName,
  task,
  metadata = {},
  taskId = null,
  target = null
) {
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

  // Substitute {{target}} placeholder with the device this task is checking,
  // e.g. "test-connection" pings the target hostname from this machine.
  if (target) {
    args = args.map((arg) => (arg === "{{target}}" ? target : arg));
  }

  // Fire-and-forget: launch and return immediately, without waiting for the
  // process to exit or capturing its output. Needed for tasks that open a
  // GUI window the user keeps open indefinitely (e.g. launching a VNC
  // viewer) - the normal wait-for-close behavior below would hold the task
  // "running" until the user closes that window, and eventually kill it at
  // the task timeout.
  if (task.fireAndForget) {
    logExecution(taskName, target || hostname, metadata.username, metadata.ip, {
      task: task.description,
      command: `${command} ${args.join(" ")}`,
      local: true,
      fireAndForget: true,
    });

    const proc = spawn(command, args, {
      cwd: path.join(config.scripts.allowedPath, ".."),
      detached: true,
      stdio: "ignore",
    });
    proc.unref();

    const result = {
      success: true,
      exitCode: 0,
      stdout: "",
      stderr: "",
      taskName,
      hostname: target || hostname,
      timestamp: new Date().toISOString(),
    };

    if (taskId) {
      taskTracker.completeTask(taskId, result);
    }

    return result;
  }

  // Log execution
  logExecution(taskName, target || hostname, metadata.username, metadata.ip, {
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
  taskId = null,
  params = null
) {
  try {
    // Get task configuration
    const task = config.allowedTasks[taskName];
    if (!task) {
      throw new Error(`Task '${taskName}' not found in allow-list`);
    }

    // Tasks marked "local" always run on the WISP host itself, targeting
    // the requested hostname (e.g. "test-connection" pings WS01 from here,
    // rather than PsExec-ing into WS01 and pinging its own loopback).
    if (task.execution === "local") {
      return executeLocalTask(taskName, task, metadata, taskId, hostname);
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
    const args = buildPsExecArgs(hostname, task, params);

    // Stage any files the script depends on (e.g. generate_json.ps1) before
    // it runs, since -c only copies the script being executed itself.
    if (task.remoteWorkDir) {
      await stageRemoteAssets(hostname, task);
    }

    // Log execution attempt (redact the password so it never lands in
    // audit.log in plaintext)
    const redactedArgs = args.map((arg, i) =>
      args[i - 1] === "-p" ? "***" : arg
    );
    logExecution(taskName, hostname, metadata.username, metadata.ip, {
      task: task.description,
      args: redactedArgs.join(" "),
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
      psexec.on("close", async (code) => {
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
          if (task.remoteWorkDir) {
            await fetchRemoteReport(hostname, task);
          }
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

const SCREENSHOT_REMOTE_DIR = "C:\\Windows\\Temp\\wisp_screenshot";
const SCREENSHOT_TIMEOUT_MS = 60000;

/**
 * Capture a screenshot of the target device's actual desktop and return it
 * as an in-memory Buffer - it is never written to disk on this host. The
 * capture script is staged onto the target, then run via PsExec targeting
 * the interactive console session (session 1): GDI screen capture only sees
 * whatever desktop the calling process is actually attached to, unlike
 * msg.exe's WTS-based messaging which reaches any session regardless of
 * where it runs, so this can't use the default invisible Session 0 the way
 * other background tasks do. Assumes session 1 is the interactive console
 * session - true for a typical single-user desktop, but not guaranteed for
 * a machine with an active RDP session instead.
 *
 * Both the staged script and the resulting image are deleted from the
 * target immediately after the image is read back, regardless of whether
 * capture succeeded or failed.
 */
async function captureScreenshot(hostname) {
  checkPsExec();

  const remoteDirUnc = toAdminShareUncPath(hostname, SCREENSHOT_REMOTE_DIR);
  const remoteImageUnc = path.join(remoteDirUnc, "screenshot.png");
  const localScript = path.join(
    __dirname,
    "..",
    "assests",
    "capture_screenshot.ps1"
  );

  await withAdminShareAccess(hostname, () => {
    fs.mkdirSync(remoteDirUnc, { recursive: true });
    fs.copyFileSync(
      localScript,
      path.join(remoteDirUnc, "capture_screenshot.ps1")
    );
  });

  try {
    const args = [`\\\\${hostname}`];

    if (config.psexec.credentials.username) {
      args.push("-u", getQualifiedUsername(hostname));
      if (config.psexec.credentials.password) {
        args.push("-p", config.psexec.credentials.password);
      }
    }

    if (config.psexec.acceptEula) {
      args.push("-accepteula");
    }

    // -h: elevated token. -i 1: run in session 1 so the capture sees the
    // user's actual screen rather than an invisible session. -WindowStyle
    // Hidden keeps the PowerShell console window from flashing up on the
    // user's desktop while it runs.
    args.push(
      "-h",
      "-i",
      "1",
      "powershell.exe",
      "-NoProfile",
      "-NoLogo",
      "-WindowStyle",
      "Hidden",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      `${SCREENSHOT_REMOTE_DIR}\\capture_screenshot.ps1`,
      "-OutputPath",
      `${SCREENSHOT_REMOTE_DIR}\\screenshot.png`
    );

    await new Promise((resolve, reject) => {
      const proc = spawn(config.psexec.path, args, {
        windowsHide: true,
        stdio: ["ignore", "pipe", "pipe"],
      });

      let stderr = "";
      if (proc.stderr) {
        proc.stderr.on("data", (data) => (stderr += data.toString()));
      }

      const timeout = setTimeout(() => {
        proc.kill();
        reject(new Error("Screenshot capture timed out"));
      }, SCREENSHOT_TIMEOUT_MS);

      proc.on("close", (code) => {
        clearTimeout(timeout);
        if (code === 0) {
          resolve();
        } else {
          reject(
            new Error(
              `Screenshot capture failed (exit ${code}): ${stderr.trim()}`
            )
          );
        }
      });

      proc.on("error", (error) => {
        clearTimeout(timeout);
        reject(error);
      });
    });

    let imageBuffer;
    await withAdminShareAccess(hostname, () => {
      if (!fs.existsSync(remoteImageUnc)) {
        throw new Error("Screenshot file not found on target after capture");
      }
      imageBuffer = fs.readFileSync(remoteImageUnc);
    });

    logExecution("screen-capture", hostname, null, null, {
      status: "captured",
      bytes: imageBuffer.length,
    });

    return imageBuffer;
  } finally {
    // Always clean up, whether capture succeeded or failed - never leave
    // this sitting on the target.
    try {
      await withAdminShareAccess(hostname, () => {
        fs.rmSync(remoteDirUnc, { recursive: true, force: true });
      });
    } catch (cleanupError) {
      logError(
        new Error(
          `Failed to clean up screenshot staging dir on ${hostname}: ${cleanupError.message}`
        ),
        { hostname }
      );
    }
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
  captureScreenshot,
  // Shared low-level helpers, reused by server/profiles.js rather than
  // duplicating the admin-share staging/fetch logic there.
  toAdminShareUncPath,
  withAdminShareAccess,
  getQualifiedUsername,
};
