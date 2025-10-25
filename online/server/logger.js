/**
 * WISP Companion Audit Logger
 * Custom lightweight logger (replaces winston)
 */

const path = require('path');
const fs = require('fs');
const config = require('./config');

// Ensure logs directory exists
const logsDir = path.join(__dirname, 'logs');
if (!fs.existsSync(logsDir)) {
  fs.mkdirSync(logsDir, { recursive: true });
}

// Log files
const auditLogFile = config.logging.file;
const errorLogFile = path.join(logsDir, 'error.log');

/**
 * Format log message
 */
function formatLog(level, message, meta = {}) {
  const timestamp = new Date().toISOString().replace('T', ' ').substring(0, 19);
  let log = `${timestamp} [${level.toUpperCase()}] ${message}`;
  if (Object.keys(meta).length > 0) {
    log += ` ${JSON.stringify(meta)}`;
  }
  return log + '\n';
}

/**
 * Write log to file
 */
function writeLog(filePath, level, message, meta = {}) {
  const logMessage = formatLog(level, message, meta);

  try {
    fs.appendFileSync(filePath, logMessage, 'utf8');

    // Also log to console in development
    if (config.server.environment !== 'production') {
      console.log(logMessage.trim());
    }
  } catch (error) {
    console.error('Failed to write to log file:', error.message);
  }
}

/**
 * Logger object with winston-compatible interface
 */
const logger = {
  info: (message, meta = {}) => {
    writeLog(auditLogFile, 'info', message, meta);
  },

  warn: (message, meta = {}) => {
    writeLog(auditLogFile, 'warn', message, meta);
  },

  error: (message, meta = {}) => {
    writeLog(auditLogFile, 'error', message, meta);
    writeLog(errorLogFile, 'error', message, meta);
  }
};

/**
 * Log authentication attempt
 */
function logAuth(success, ip, details = {}) {
  logger.info('Authentication attempt', {
    success,
    ip,
    timestamp: new Date().toISOString(),
    ...details
  });
}

/**
 * Log task execution
 */
function logExecution(task, host, username, ip, details = {}) {
  logger.info('Task execution', {
    task,
    host,
    username: username || 'UNKNOWN',
    ip,
    timestamp: new Date().toISOString(),
    ...details
  });
}

/**
 * Log security event
 */
function logSecurity(event, ip, details = {}) {
  logger.warn('Security event', {
    event,
    ip,
    timestamp: new Date().toISOString(),
    ...details
  });
}

/**
 * Log error
 */
function logError(error, context = {}) {
  logger.error('Error occurred', {
    message: error.message,
    stack: error.stack,
    timestamp: new Date().toISOString(),
    ...context
  });
}

module.exports = {
  logger,
  logAuth,
  logExecution,
  logSecurity,
  logError
};
