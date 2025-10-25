/**
 * Custom Rate Limiter Middleware
 * Replaces express-rate-limit with in-memory tracking
 */

/**
 * Simple in-memory rate limiter
 * Tracks IP addresses and their request counts
 */
class RateLimiter {
  constructor(options = {}) {
    this.windowMs = options.windowMs || 60000; // Default: 1 minute
    this.maxRequests = options.max || 100; // Default: 100 requests per window
    this.message = options.message || 'Too many requests, please try again later';

    // Store: { ip: { count: number, resetTime: number } }
    this.requests = new Map();

    // Cleanup old entries every minute
    setInterval(() => this.cleanup(), 60000);
  }

  /**
   * Clean up expired entries
   */
  cleanup() {
    const now = Date.now();
    for (const [ip, data] of this.requests.entries()) {
      if (now > data.resetTime) {
        this.requests.delete(ip);
      }
    }
  }

  /**
   * Middleware function
   */
  middleware() {
    return (req, res, next) => {
      const ip = req.ip || req.connection.remoteAddress;
      const now = Date.now();

      // Get or create request data for this IP
      let ipData = this.requests.get(ip);

      if (!ipData || now > ipData.resetTime) {
        // First request or window expired - reset
        ipData = {
          count: 1,
          resetTime: now + this.windowMs
        };
        this.requests.set(ip, ipData);
        return next();
      }

      // Increment request count
      ipData.count++;

      // Check if limit exceeded
      if (ipData.count > this.maxRequests) {
        return res.status(429).json({
          success: false,
          error: this.message,
          retryAfter: Math.ceil((ipData.resetTime - now) / 1000)
        });
      }

      next();
    };
  }
}

/**
 * Create rate limiter middleware
 * @param {object} options - Rate limiter options
 * @returns {function} - Express middleware
 */
function createRateLimiter(options) {
  const limiter = new RateLimiter(options);
  return limiter.middleware();
}

module.exports = {
  createRateLimiter
};
