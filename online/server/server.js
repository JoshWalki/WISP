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
const { executeRemoteTask, getAvailableTasks, checkPsExec } = require('./psexec');
const { logger, logSecurity } = require('./logger');
const { securityHeaders } = require('./security');
const { createRateLimiter } = require('./rate-limiter');

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

  if (allowedOrigins.includes(origin) || !origin) {
    res.setHeader('Access-Control-Allow-Origin', origin || '*');
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

    // Fire-and-forget execution (return 202 Accepted immediately)
    // PsExec will run in background
    res.status(202).json({
      success: true,
      message: `Task '${taskName}' initiated on ${sanitizedHost}`,
      task: {
        name: taskName,
        description: task.description,
        host: sanitizedHost
      },
      timestamp: new Date().toISOString()
    });

    // Execute task asynchronously
    executeRemoteTask(taskName, sanitizedHost, {
      username: process.env.USERNAME || 'UNKNOWN',
      ip: clientIp
    }).catch(error => {
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
 * Get the latest report for a host (requires auth)
 * GET /reports/:host/latest
 */
app.get('/reports/:host/latest', validateToken, (req, res) => {
  const { host } = req.params;
  const fs = require('fs');
  const path = require('path');

  logger.info(`Fetching latest report for host: ${host}`);

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

    const dirs = allDirs
      .filter(dir => {
        const stat = fs.statSync(path.join(reportsDir, dir));
        return stat.isDirectory() && dir.toLowerCase().startsWith(host.toLowerCase() + '_');
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

    res.json({
      success: true,
      result
    });

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
