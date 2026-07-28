/**
 * Task Tracker - In-memory tracking of running tasks
 * Stores task state, output, and status for live streaming
 */

class TaskTracker {
  constructor() {
    // Store: { taskId: { status, output, stdout, stderr, startTime, endTime, error } }
    this.tasks = new Map();

    // Cleanup completed tasks after 5 minutes
    setInterval(() => this.cleanup(), 60000);
  }

  /**
   * Create a new task
   */
  createTask(taskId, taskName, hostname, metadata = {}) {
    this.tasks.set(taskId, {
      taskId,
      taskName,
      hostname,
      status: 'running',
      stdout: '',
      stderr: '',
      startTime: new Date().toISOString(),
      endTime: null,
      error: null,
      metadata
    });
    return taskId;
  }

  /**
   * Append stdout data to a task
   */
  appendStdout(taskId, data) {
    const task = this.tasks.get(taskId);
    if (task) {
      task.stdout += data;
    }
  }

  /**
   * Append stderr data to a task
   */
  appendStderr(taskId, data) {
    const task = this.tasks.get(taskId);
    if (task) {
      task.stderr += data;
    }
  }

  /**
   * Mark task as completed
   */
  completeTask(taskId, result = {}) {
    const task = this.tasks.get(taskId);
    if (task) {
      task.status = 'completed';
      task.endTime = new Date().toISOString();
      if (result.stdout) task.stdout = result.stdout;
      if (result.stderr) task.stderr = result.stderr;
    }
  }

  /**
   * Mark task as failed
   */
  failTask(taskId, error) {
    const task = this.tasks.get(taskId);
    if (task) {
      task.status = 'failed';
      task.endTime = new Date().toISOString();
      task.error = error;
    }
  }

  /**
   * Get task status and output
   */
  getTask(taskId) {
    return this.tasks.get(taskId) || null;
  }

  /**
   * Check if task exists
   */
  hasTask(taskId) {
    return this.tasks.has(taskId);
  }

  /**
   * Get all tasks (for debugging)
   */
  getAllTasks() {
    return Array.from(this.tasks.values());
  }

  /**
   * Clean up old completed tasks (older than 5 minutes)
   */
  cleanup() {
    const now = Date.now();
    const maxAge = 5 * 60 * 1000; // 5 minutes

    for (const [taskId, task] of this.tasks.entries()) {
      if (task.status !== 'running' && task.endTime) {
        const endTime = new Date(task.endTime).getTime();
        if (now - endTime > maxAge) {
          this.tasks.delete(taskId);
        }
      }
    }
  }

  /**
   * Delete a specific task
   */
  deleteTask(taskId) {
    this.tasks.delete(taskId);
  }
}

// Singleton instance
const taskTracker = new TaskTracker();

module.exports = taskTracker;
