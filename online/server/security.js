/**
 * Custom Security Headers Middleware
 * Replaces helmet package with manual header configuration
 */

/**
 * Security headers middleware
 * Sets HTTP security headers to protect against common vulnerabilities
 */
function securityHeaders(req, res, next) {
  // Content Security Policy - prevents XSS attacks
  res.setHeader(
    'Content-Security-Policy',
    "default-src 'self'; " +
    "connect-src 'self' http://127.0.0.1:8765; " +
    "img-src 'self' data:; " +
    "font-src 'self'; " +
    "style-src 'self' 'unsafe-inline'; " +
    "script-src 'self'; " +
    "base-uri 'self'; " +
    "frame-ancestors 'self'; " +
    "upgrade-insecure-requests"
  );

  // Cross-Origin Embedder Policy
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');

  // Cross-Origin Opener Policy
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');

  // Cross-Origin Resource Policy
  res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');

  // Origin-Agent-Cluster
  res.setHeader('Origin-Agent-Cluster', '?1');

  // Referrer Policy - controls how much referrer info is sent
  res.setHeader('Referrer-Policy', 'no-referrer');

  // Strict-Transport-Security - forces HTTPS (commented for localhost)
  // res.setHeader('Strict-Transport-Security', 'max-age=15552000; includeSubDomains');

  // X-Content-Type-Options - prevents MIME type sniffing
  res.setHeader('X-Content-Type-Options', 'nosniff');

  // X-DNS-Prefetch-Control - controls DNS prefetching
  res.setHeader('X-DNS-Prefetch-Control', 'off');

  // X-Download-Options - prevents downloads in IE
  res.setHeader('X-Download-Options', 'noopen');

  // X-Frame-Options - prevents clickjacking
  res.setHeader('X-Frame-Options', 'SAMEORIGIN');

  // X-Permitted-Cross-Domain-Policies - controls Adobe products
  res.setHeader('X-Permitted-Cross-Domain-Policies', 'none');

  // X-XSS-Protection - legacy XSS protection (modern browsers use CSP)
  res.setHeader('X-XSS-Protection', '0');

  next();
}

module.exports = {
  securityHeaders
};
