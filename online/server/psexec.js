/**
 * WISP Companion PsExec Wrapper
 * Secure wrapper for PsExec remote execution
 */

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const config = require('./config');
const { logExecution, logError } = require('./logger');

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
 * Build PsExec command arguments
 */
function buildPsExecArgs(hostname, task) {
  const args = [];

  // Target hostname
  args.push(`\\\\${hostname}`);

  // Accept EULA automatically
  if (config.psexec.acceptEula) {
    args.push('-accepteula');
  }

  // Run with elevated privileges if needed
  if (task.runAs === 'admin') {
    args.push('-h'); // Run with elevated token
  }

  // Run in background (no interaction)
  args.push('-d');

  // Add script/command and its arguments
  if (task.script.endsWith('.bat') || task.script.endsWith('.ps1')) {
    // Full path to script
    const scriptPath = path.join(config.scripts.allowedPath, task.script);

    // Verify script exists and is in allowed directory
    if (!scriptPath.startsWith(config.scripts.allowedPath)) {
      throw new Error('Script path traversal attempt detected');
    }

    if (!fs.existsSync(scriptPath)) {
      throw new Error(`Script not found: ${scriptPath}`);
    }

    if (task.script.endsWith('.bat')) {
      args.push('cmd.exe', '/c', scriptPath);
      // Add hostname as first argument to batch scripts
      args.push(hostname);
      // Add any additional task-specific arguments
      if (task.args && task.args.length > 0) {
        args.push(...task.args);
      }
    } else if (task.script.endsWith('.ps1')) {
      args.push('powershell.exe', '-ExecutionPolicy', 'Bypass', '-File', scriptPath);
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
async function executeLocalTask(taskName, task, metadata = {}) {
  const hostname = require('os').hostname();

  let command, args;

  if (task.script.endsWith('.bat') || task.script.endsWith('.ps1')) {
    const scriptPath = path.join(config.scripts.allowedPath, task.script);

    if (!fs.existsSync(scriptPath)) {
      throw new Error(`Script not found: ${scriptPath}`);
    }

    if (task.script.endsWith('.bat')) {
      command = 'cmd.exe';
      args = ['/c', scriptPath, hostname];
    } else {
      command = 'powershell.exe';
      args = ['-ExecutionPolicy', 'Bypass', '-File', scriptPath, hostname];
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
    command: `${command} ${args.join(' ')}`,
    local: true
  });

  // Execute locally
  return new Promise((resolve, reject) => {
    const proc = spawn(command, args, {
      cwd: path.join(config.scripts.allowedPath, '..'), // Run from root directory
      windowsHide: false, // Show window for debugging
      detached: false, // Don't detach - wait for completion
      stdio: ['ignore', 'pipe', 'pipe']
    });

    let stdout = '';
    let stderr = '';

    if (proc.stdout) {
      proc.stdout.on('data', (data) => {
        stdout += data.toString();
      });
    }

    if (proc.stderr) {
      proc.stderr.on('data', (data) => {
        stderr += data.toString();
      });
    }

    const timeout = setTimeout(() => {
      proc.kill();
      reject(new Error('Execution timeout exceeded'));
    }, config.psexec.timeout);

    proc.on('close', (code) => {
      clearTimeout(timeout);

      const result = {
        success: code === 0,
        exitCode: code,
        stdout: stdout.trim(),
        stderr: stderr.trim(),
        taskName,
        hostname,
        timestamp: new Date().toISOString()
      };

      if (code === 0) {
        logExecution(taskName, hostname, metadata.username, metadata.ip, {
          status: 'completed',
          exitCode: code
        });
        resolve(result);
      } else {
        logError(new Error(`Task exited with code ${code}`), {
          taskName,
          hostname,
          stderr: stderr.trim()
        });
        resolve(result); // Still resolve for local execution
      }
    });

    proc.on('error', (error) => {
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
 * @returns {Promise} Promise that resolves with execution result
 */
async function executeRemoteTask(taskName, hostname, metadata = {}) {
  try {
    // Get task configuration
    const task = config.allowedTasks[taskName];
    if (!task) {
      throw new Error(`Task '${taskName}' not found in allow-list`);
    }

    // Check if this is local execution
    const localHostname = require('os').hostname();
    if (hostname.toLowerCase() === localHostname.toLowerCase() ||
        hostname.toLowerCase() === 'localhost' ||
        hostname === '127.0.0.1') {
      // Execute locally without PsExec
      return executeLocalTask(taskName, task, metadata);
    }

    // Verify PsExec exists for remote execution
    checkPsExec();

    // Build command arguments
    const args = buildPsExecArgs(hostname, task);

    // Log execution attempt
    logExecution(taskName, hostname, metadata.username, metadata.ip, {
      task: task.description,
      args: args.join(' ')
    });

    // Spawn PsExec process
    return new Promise((resolve, reject) => {
      const psexec = spawn(config.psexec.path, args, {
        windowsHide: true,
        detached: true,
        stdio: ['ignore', 'pipe', 'pipe']
      });

      let stdout = '';
      let stderr = '';

      // Capture output
      if (psexec.stdout) {
        psexec.stdout.on('data', (data) => {
          stdout += data.toString();
        });
      }

      if (psexec.stderr) {
        psexec.stderr.on('data', (data) => {
          stderr += data.toString();
        });
      }

      // Set timeout
      const timeout = setTimeout(() => {
        psexec.kill();
        reject(new Error('Execution timeout exceeded'));
      }, config.psexec.timeout);

      // Handle process completion
      psexec.on('close', (code) => {
        clearTimeout(timeout);

        const result = {
          success: code === 0,
          exitCode: code,
          stdout: stdout.trim(),
          stderr: stderr.trim(),
          taskName,
          hostname,
          timestamp: new Date().toISOString()
        };

        if (code === 0) {
          logExecution(taskName, hostname, metadata.username, metadata.ip, {
            status: 'completed',
            exitCode: code
          });
          resolve(result);
        } else {
          logError(new Error(`PsExec exited with code ${code}`), {
            taskName,
            hostname,
            stderr: stderr.trim()
          });
          reject(new Error(`Execution failed with exit code ${code}: ${stderr}`));
        }
      });

      psexec.on('error', (error) => {
        clearTimeout(timeout);
        logError(error, { taskName, hostname });
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
    requiresAdmin: task.runAs === 'admin'
  }));
}

module.exports = {
  executeRemoteTask,
  getAvailableTasks,
  checkPsExec
};
