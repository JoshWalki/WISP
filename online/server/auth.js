/**
 * WISP Companion Authentication Middleware
 * Token-based authentication using X-WISP-Token header
 */

const crypto = require('crypto');
const config = require('./config');
const { logAuth, logSecurity } = require('./logger');

/**
 * Constant-time check of a candidate token against the configured one.
 * Standalone (no req/res coupling) so non-Express callers - like the
 * WebSocket shell handler - can reuse the same check.
 * SECURITY: Constant-time comparison to prevent timing attacks
 */
function isValidToken(providedToken) {
  if (!config.auth.token || !providedToken) {
    return false;
  }

  const expectedToken = Buffer.from(config.auth.token, 'utf8');
  const providedBuffer = Buffer.from(String(providedToken), 'utf8');

  if (expectedToken.length !== providedBuffer.length) {
    return false;
  }

  return crypto.timingSafeEqual(expectedToken, providedBuffer);
}

/**
 * Validates the X-WISP-Token header
 */
function validateToken(req, res, next) {
  const clientIp = req.ip || req.connection.remoteAddress;
  const providedToken = req.headers[config.auth.headerName.toLowerCase()];

  // Check if token is configured
  if (!config.auth.token) {
    logSecurity('No token configured - rejecting all requests', clientIp);
    return res.status(500).json({
      success: false,
      error: 'Server configuration error'
    });
  }

  // Check if token was provided
  if (!providedToken) {
    logAuth(false, clientIp, { reason: 'No token provided' });
    return res.status(401).json({
      success: false,
      error: 'Authentication required',
      message: `Missing ${config.auth.headerName} header`
    });
  }

  if (!isValidToken(providedToken)) {
    logAuth(false, clientIp, { reason: 'Token mismatch' });
    logSecurity('Invalid token attempt', clientIp, {
      providedTokenHash: crypto.createHash('sha256').update(providedToken).digest('hex')
    });
    return res.status(403).json({
      success: false,
      error: 'Invalid authentication token'
    });
  }

  // Token is valid
  logAuth(true, clientIp);
  next();
}

/**
 * Validates task name against allow-list
 */
function validateTask(taskName) {
  if (!taskName || typeof taskName !== 'string') {
    return { valid: false, error: 'Task name is required' };
  }

  // Check if task exists in allow-list
  const task = config.allowedTasks[taskName];
  if (!task) {
    return {
      valid: false,
      error: `Task '${taskName}' is not in allow-list`,
      allowedTasks: Object.keys(config.allowedTasks)
    };
  }

  return { valid: true, task };
}

/**
 * Validates hostname/IP against allow-list patterns
 */
function validateHost(hostname) {
  if (!hostname || typeof hostname !== 'string') {
    return { valid: false, error: 'Hostname is required' };
  }

  // Sanitize hostname - remove any path traversal or special chars
  const sanitized = hostname.trim().replace(/[^\w\.\-]/g, '');

  if (sanitized !== hostname) {
    return {
      valid: false,
      error: 'Hostname contains invalid characters'
    };
  }

  // Check against allow-list patterns
  const isAllowed = config.allowedHostPatterns.some(pattern =>
    pattern.test(sanitized)
  );

  if (!isAllowed) {
    return {
      valid: false,
      error: `Hostname '${sanitized}' does not match any allowed patterns`
    };
  }

  return { valid: true, hostname: sanitized };
}

module.exports = {
  validateToken,
  validateTask,
  validateHost
};
