/**
 * WISP Companion Server
 * Secure Node.js companion for PsExec-based remote execution
 *
 * SECURITY: Binds to 127.0.0.1 only, requires token authentication,
 * enforces strict allow-lists for tasks and hosts
 */

const express = require('express');
const config = require('./config');
const { validateToken, validateTask, validateHost } = require('./auth');
const { executeRemoteTask, getAvailableTasks, checkPsExec, captureScreenshot } = require('./psexec');
const { listProfiles, deleteProfile } = require('./profiles');
const { logger, logSecurity } = require('./logger');
const { securityHeaders } = require('./security');
const { createRateLimiter } = require('./rate-limiter');
const taskTracker = require('./task-tracker');

const app = express();

// ============================================================================
// SECURITY MIDDLEWARE
// ============================================================================

// Custom security headers (replaces helmet)
app.use(securityHeaders);

// CORS handling - Manual implementation (localhost only)
app.use((req, res, next) => {
  const origin = req.headers.origin;
  const allowedOrigins = ['http://127.0.0.1:8765', 'http://localhost:8765', 'null'];

  // Allow null origin (for file:// protocol when opening HTML files directly)
  if (allowedOrigins.includes(origin) || origin === null || origin === 'null') {
    res.setHeader('Access-Control-Allow-Origin', origin || 'null');
    res.setHeader('Access-Control-Allow-Credentials', 'true');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-WISP-Token');
  }

  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

// Custom rate limiting (replaces express-rate-limit)
const limiter = createRateLimiter(config.rateLimit);
app.use(limiter);

// JSON body parser
app.use(express.json({ limit: '1mb' }));

// Request logging
app.use((req, res, next) => {
  const clientIp = req.ip || req.connection.remoteAddress;
  logger.info(`${req.method} ${req.path}`, { ip: clientIp });
  next();
});

// ============================================================================
// ROUTES
// ============================================================================

/**
 * Root endpoint - API information
 */
app.get('/', (req, res) => {
  res.json({
    success: true,
    service: 'WISP Companion',
    version: '1.0.0',
    status: 'running',
    endpoints: {
      health: 'GET /health',
      config: 'GET /config (localhost only)',
      tasks: 'GET /tasks (auth required)',
      execute: 'POST /run/:task/:host (auth required)',
      executeSync: 'POST /run-sync/:task/:host (auth required)',
      latestReport: 'GET /reports/:host/latest (auth required)'
    },
    documentation: 'See README.md for full API documentation'
  });
});

/**
 * Health check endpoint (no auth required)
 */
app.get('/health', (req, res) => {
  try {
    checkPsExec();
    res.json({
      success: true,
      status: 'healthy',
      version: '1.0.0',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      status: 'unhealthy',
      error: error.message
    });
  }
});

/**
 * Get configuration (no auth required - localhost only)
 * Returns the API token for client-side use
 */
app.get('/config', (req, res) => {
  const clientIp = req.ip || req.connection.remoteAddress;

  // Only allow localhost access
  if (clientIp !== '127.0.0.1' && clientIp !== '::1' && !clientIp.includes('127.0.0.1')) {
    logger.warn('Config endpoint accessed from non-localhost IP', { ip: clientIp });
    return res.status(403).json({
      success: false,
      error: 'Access denied - localhost only'
    });
  }

  res.json({
    success: true,
    apiUrl: `http://${config.server.host}:${config.server.port}`,
    token: config.auth.token
  });
});

/**
 * Get available tasks (requires auth)
 */
app.get('/tasks', validateToken, (req, res) => {
  try {
    const tasks = getAvailableTasks();
    res.json({
      success: true,
      tasks
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * Execute remote task (requires auth)
 * POST /run/:task/:host
 *
 * Example: POST /run/system-report/PC-001
 *          POST /run/gpupdate/192.168.1.100
 */
app.post('/run/:task/:host', validateToken, async (req, res) => {
  const clientIp = req.ip || req.connection.remoteAddress;
  const { task: taskName, host: hostname } = req.params;

  try {
    // Validate task name
    const taskValidation = validateTask(taskName);
    if (!taskValidation.valid) {
      logSecurity('Invalid task attempt', clientIp, {
        taskName,
        error: taskValidation.error
      });
      return res.status(400).json({
        success: false,
        error: taskValidation.error,
        allowedTasks: taskValidation.allowedTasks
      });
    }

    // Validate hostname
    const hostValidation = validateHost(hostname);
    if (!hostValidation.valid) {
      logSecurity('Invalid host attempt', clientIp, {
        hostname,
        error: hostValidation.error
      });
      return res.status(400).json({
        success: false,
        error: hostValidation.error
      });
    }

    const sanitizedHost = hostValidation.hostname;
    const task = taskValidation.task;

    // Tasks that embed a "{{message}}" placeholder need free-text input
    // from the caller - validate/sanitize it here before it ever reaches
    // PsExec's argument list.
    let params = null;
    if (taskName === 'show-message') {
      const userMessage = req.body && req.body.message;
      if (typeof userMessage !== 'string' || userMessage.trim() === '') {
        return res.status(400).json({
          success: false,
          error: 'A non-empty "message" field is required for show-message'
        });
      }
      if (userMessage.length > 500) {
        return res.status(400).json({
          success: false,
          error: 'message must be 500 characters or fewer'
        });
      }
      // Strip embedded double quotes - PsExec wraps args containing spaces
      // in quotes when reconstructing the remote command line, so a literal
      // " in the message could break that argument boundary.
      params = { message: userMessage.trim().replace(/"/g, "'") };
    }

    // Generate unique task ID
    const taskId = `task-${taskName}-${sanitizedHost}-${Date.now()}`;

    // Create task in tracker
    taskTracker.createTask(taskId, taskName, sanitizedHost, {
      username: process.env.USERNAME || 'UNKNOWN',
      ip: clientIp
    });

    // Fire-and-forget execution (return 202 Accepted immediately)
    // PsExec will run in background
    res.status(202).json({
      success: true,
      message: `Task '${taskName}' initiated on ${sanitizedHost}`,
      taskId: taskId,
      task: {
        name: taskName,
        description: task.description,
        host: sanitizedHost
      },
      timestamp: new Date().toISOString()
    });

    // Execute task asynchronously with task tracking
    executeRemoteTask(taskName, sanitizedHost, {
      username: process.env.USERNAME || 'UNKNOWN',
      ip: clientIp
    }, taskId, params).catch(error => {
      // Error is already logged in psexec.js
      logger.error('Background task failed', {
        taskName,
        hostname: sanitizedHost,
        error: error.message
      });
    });

  } catch (error) {
    logger.error('Execution request failed', {
      taskName,
      hostname,
      error: error.message
    });
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * Capture a screenshot of the target device's screen (requires auth)
 * POST /screenshot/:host
 *
 * Returns the image as a base64 data URI - it is never written to disk on
 * this host, and the copy on the target is deleted immediately after
 * transfer. Synchronous (awaits the full capture) since the response body
 * IS the result, unlike the fire-and-forget /run endpoint.
 */
app.post('/screenshot/:host', validateToken, async (req, res) => {
  const clientIp = req.ip || req.connection.remoteAddress;
  const { host: hostname } = req.params;

  const hostValidation = validateHost(hostname);
  if (!hostValidation.valid) {
    logSecurity('Invalid host attempt', clientIp, {
      hostname,
      error: hostValidation.error
    });
    return res.status(400).json({
      success: false,
      error: hostValidation.error
    });
  }

  const sanitizedHost = hostValidation.hostname;

  try {
    const imageBuffer = await captureScreenshot(sanitizedHost);
    res.json({
      success: true,
      image: `data:image/png;base64,${imageBuffer.toString('base64')}`
    });
  } catch (error) {
    logger.error('Screenshot capture failed', {
      hostname: sanitizedHost,
      error: error.message
    });
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * List user profiles on the target device (requires auth)
 * GET /profiles/:host
 */
app.get('/profiles/:host', validateToken, async (req, res) => {
  const clientIp = req.ip || req.connection.remoteAddress;
  const { host: hostname } = req.params;

  const hostValidation = validateHost(hostname);
  if (!hostValidation.valid) {
    logSecurity('Invalid host attempt', clientIp, {
      hostname,
      error: hostValidation.error
    });
    return res.status(400).json({
      success: false,
      error: hostValidation.error
    });
  }

  const sanitizedHost = hostValidation.hostname;

  try {
    const profiles = await listProfiles(sanitizedHost);
    res.json({ success: true, profiles });
  } catch (error) {
    logger.error('Profile listing failed', {
      hostname: sanitizedHost,
      error: error.message
    });
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * Delete a single user profile on the target device (requires auth)
 * POST /profiles/:host/delete
 * Body: { sid }
 *
 * The frontend calls this once per selected profile so it can drive its own
 * progress bar across a bulk delete, rather than this endpoint handling a
 * batch itself.
 */
app.post('/profiles/:host/delete', validateToken, async (req, res) => {
  const clientIp = req.ip || req.connection.remoteAddress;
  const { host: hostname } = req.params;
  const { sid } = req.body || {};

  const hostValidation = validateHost(hostname);
  if (!hostValidation.valid) {
    logSecurity('Invalid host attempt', clientIp, {
      hostname,
      error: hostValidation.error
    });
    return res.status(400).json({
      success: false,
      error: hostValidation.error
    });
  }

  if (!sid || typeof sid !== 'string') {
    return res.status(400).json({
      success: false,
      error: 'A "sid" field is required'
    });
  }

  const sanitizedHost = hostValidation.hostname;

  try {
    await deleteProfile(sanitizedHost, sid);
    res.json({ success: true, sid });
  } catch (error) {
    logger.error('Profile deletion failed', {
      hostname: sanitizedHost,
      sid,
      error: error.message
    });
    res.status(500).json({
      success: false,
      sid,
      error: error.message
    });
  }
});

/**
 * Get task status and live output (requires auth)
 * GET /task-status/:taskId
 *
 * Polls for task status, stdout, and stderr
 */
app.get('/task-status/:taskId', validateToken, (req, res) => {
  const { taskId } = req.params;

  try {
    const task = taskTracker.getTask(taskId);

    if (!task) {
      return res.status(404).json({
        success: false,
        error: 'Task not found'
      });
    }

    res.json({
      success: true,
      task: {
        taskId: task.taskId,
        taskName: task.taskName,
        hostname: task.hostname,
        status: task.status,
        stdout: task.stdout,
        stderr: task.stderr,
        startTime: task.startTime,
        endTime: task.endTime,
        error: task.error
      }
    });
  } catch (error) {
    logger.error('Failed to get task status', {
      taskId,
      error: error.message
    });
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * Get the latest report for a host (requires auth)
 * GET /reports/:host/latest
 */
app.get('/reports/:host/latest', validateToken, (req, res) => {
  let { host } = req.params;
  const fs = require('fs');
  const path = require('path');
  const os = require('os');

  logger.info(`Fetching latest report for host: ${host}`);

  // Handle 'localhost' by converting to actual hostname
  if (host.toLowerCase() === 'localhost' || host === '127.0.0.1') {
    const actualHostname = os.hostname();
    logger.info(`Converting 'localhost' to actual hostname: ${actualHostname}`);
    host = actualHostname;
  }

  try {
    const reportsDir = path.join(__dirname, '..', 'reports');

    logger.info(`Checking reports directory: ${reportsDir}`);

    if (!fs.existsSync(reportsDir)) {
      logger.error('Reports directory does not exist', { reportsDir });
      return res.status(404).json({
        success: false,
        error: 'No reports directory found'
      });
    }

    // Find all directories starting with the hostname
    const allDirs = fs.readdirSync(reportsDir);
    logger.info(`All directories in reports: ${allDirs.join(', ')}`);
    logger.info(`Looking for directories starting with: "${host.toLowerCase()}_"`);

    const dirs = allDirs
      .filter(dir => {
        const stat = fs.statSync(path.join(reportsDir, dir));
        const isDir = stat.isDirectory();
        const dirLower = dir.toLowerCase();
        const hostLower = host.toLowerCase();
        const matches = dirLower.startsWith(hostLower + '_');

        logger.info(`  Checking: "${dir}" | isDir=${isDir} | dirLower="${dirLower}" | hostLower="${hostLower}" | matches=${matches}`);

        return isDir && matches;
      })
      .map(dir => ({
        name: dir,
        path: path.join(reportsDir, dir),
        time: fs.statSync(path.join(reportsDir, dir)).mtime.getTime()
      }))
      .sort((a, b) => b.time - a.time); // Sort by newest first

    logger.info(`Found ${dirs.length} matching directories for host ${host}`);

    if (dirs.length === 0) {
      logger.error(`No reports found for host: ${host}`);
      return res.status(404).json({
        success: false,
        error: `No reports found for host: ${host}`
      });
    }

    // Get the latest report
    const latestDir = dirs[0];
    const jsonPath = path.join(latestDir.path, 'comprehensive_report.json');

    logger.info(`Latest report directory: ${latestDir.name}`);
    logger.info(`Looking for JSON at: ${jsonPath}`);

    if (!fs.existsSync(jsonPath)) {
      logger.error('Report JSON file not found', { jsonPath });
      return res.status(404).json({
        success: false,
        error: 'Report JSON file not found'
      });
    }

    // Read and return the JSON content
    let jsonContent = fs.readFileSync(jsonPath, 'utf8');

    // Remove BOM (Byte Order Mark) if present
    if (jsonContent.charCodeAt(0) === 0xFEFF) {
      jsonContent = jsonContent.slice(1);
      logger.info('Removed BOM from JSON file');
    }

    const reportData = JSON.parse(jsonContent);

    logger.info(`Successfully loaded report for ${host}`);

    res.json({
      success: true,
      report: reportData,
      reportPath: jsonPath,
      timestamp: latestDir.name.split('_')[1]
    });

  } catch (error) {
    logger.error('Failed to fetch latest report', {
      host: req.params.host,
      error: error.message,
      stack: error.stack
    });
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * Execute with output streaming (requires auth)
 * POST /run-sync/:task/:host
 *
 * Returns output when execution completes (synchronous)
 */
app.post('/run-sync/:task/:host', validateToken, async (req, res) => {
  const clientIp = req.ip || req.connection.remoteAddress;
  const { task: taskName, host: hostname } = req.params;

  try {
    // Validate task name
    const taskValidation = validateTask(taskName);
    if (!taskValidation.valid) {
      logSecurity('Invalid task attempt', clientIp, {
        taskName,
        error: taskValidation.error
      });
      return res.status(400).json({
        success: false,
        error: taskValidation.error,
        allowedTasks: taskValidation.allowedTasks
      });
    }

    // Validate hostname
    const hostValidation = validateHost(hostname);
    if (!hostValidation.valid) {
      logSecurity('Invalid host attempt', clientIp, {
        hostname,
        error: hostValidation.error
      });
      return res.status(400).json({
        success: false,
        error: hostValidation.error
      });
    }

    const sanitizedHost = hostValidation.hostname;

    // Execute task and wait for completion
    const result = await executeRemoteTask(taskName, sanitizedHost, {
      username: process.env.USERNAME || 'UNKNOWN',
      ip: clientIp
    });

    // Return result directly with all fields (success, stdout, stderr, exitCode, etc.)
    res.json(result);

  } catch (error) {
    logger.error('Sync execution failed', {
      taskName,
      hostname,
      error: error.message
    });
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * 404 handler
 */
app.use((req, res) => {
  logSecurity('404 Not Found', req.ip, { path: req.path });
  res.status(404).json({
    success: false,
    error: 'Endpoint not found'
  });
});

/**
 * Error handler
 */
app.use((err, req, res, next) => {
  logger.error('Unhandled error', {
    error: err.message,
    stack: err.stack,
    path: req.path
  });
  res.status(500).json({
    success: false,
    error: 'Internal server error'
  });
});

// ============================================================================
// SERVER STARTUP
// ============================================================================

function startServer() {
  // Verify configuration
  if (!config.auth.token) {
    console.error('ERROR: WISP_TOKEN environment variable not set!');
    console.error('Generate a token using: node scripts/generate-token.js');
    process.exit(1);
  }

  // Verify PsExec
  try {
    checkPsExec();
    logger.info(`PsExec found at: ${config.psexec.path}`);
  } catch (error) {
    console.error(`ERROR: ${error.message}`);
    console.error('Please install Sysinternals Suite and configure PSEXEC_PATH');
    process.exit(1);
  }

  // Start server (bind to 127.0.0.1 ONLY for security)
  app.listen(config.server.port, config.server.host, () => {
    logger.info('='.repeat(60));
    logger.info('WISP Companion Server Started');
    logger.info('='.repeat(60));
    logger.info(`Host: ${config.server.host}:${config.server.port} (LOCALHOST ONLY)`);
    logger.info(`Environment: ${config.server.environment}`);
    logger.info(`PsExec: ${config.psexec.path}`);
    logger.info(`Allowed tasks: ${Object.keys(config.allowedTasks).length}`);
    logger.info(`Audit log: ${config.logging.file}`);
    logger.info('='.repeat(60));
    logger.info('SECURITY: Server bound to 127.0.0.1 only');
    logger.info('SECURITY: Token authentication required');
    logger.info('SECURITY: Task and host allow-lists enforced');
    logger.info('='.repeat(60));
  });
}

// Handle graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down gracefully');
  process.exit(0);
});

process.on('SIGINT', () => {
  logger.info('SIGINT received, shutting down gracefully');
  process.exit(0);
});

// Start the server
if (require.main === module) {
  startServer();
}

module.exports = app;
