import { DurableObject } from 'cloudflare:workers';

/**
 * Durable Object for managing WebSocket connections per job
 * One instance per jobId - stores WebSocket connection and forwards progress messages
 *
 * Migrated from progress-websocket-durable-object/src/index.js
 */
// Pipeline-specific throttling configuration
const THROTTLE_CONFIG = {
  batch_enrichment: { updateCount: 5, timeSeconds: 10 },
  csv_import: { updateCount: 20, timeSeconds: 30 },  // Reduced writes
  ai_scan: { updateCount: 1, timeSeconds: 60 }       // Minimal writes
};

export class ProgressWebSocketDO extends DurableObject {
  constructor(state, env) {
    super(state, env);
    this.storage = state.storage; // Durable Object storage for cancellation state
    this.webSocket = null;
    this.jobId = null;
    this.isReady = false; // NEW: Track if client sent ready signal
    this.readyPromise = null; // NEW: Promise to await ready signal
    this.readyResolver = null; // NEW: Resolver for ready promise
    this.refreshInProgress = false; // Prevents concurrent refresh race conditions

    // State persistence tracking
    this.updatesSinceLastPersist = 0;
    this.lastPersistTime = 0;
    this.currentPipeline = null;
  }

  /**
   * Handle WebSocket upgrade request from iOS client
   */
  async fetch(request) {
    const url = new URL(request.url);
    const upgradeHeader = request.headers.get('Upgrade');

    console.log('[ProgressDO] Incoming request', {
      url: url.toString(),
      upgradeHeader,
      method: request.method
    });

    // Validate WebSocket upgrade
    if (!upgradeHeader || upgradeHeader !== 'websocket') {
      console.warn('[ProgressDO] Invalid upgrade header', { upgradeHeader });
      return new Response('Expected Upgrade: websocket', {
        status: 426,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Content-Type': 'text/plain'
        }
      });
    }

    // Extract jobId from query params
    const jobId = url.searchParams.get('jobId');
    if (!jobId) {
      console.error('[ProgressDO] Missing jobId parameter');
      return new Response('Missing jobId parameter', { status: 400 });
    }

    // SECURITY: Validate authentication token
    const providedToken = url.searchParams.get('token');
    const storedToken = await this.storage.get('authToken');
    const expiration = await this.storage.get('authTokenExpiration');

    if (!storedToken || !providedToken || storedToken !== providedToken) {
      console.warn(`[${jobId}] WebSocket authentication failed - invalid token`);
      return new Response('Unauthorized', {
        status: 401,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Content-Type': 'text/plain'
        }
      });
    }

    if (Date.now() > expiration) {
      console.warn(`[${jobId}] WebSocket authentication failed - token expired`);
      return new Response('Token expired', {
        status: 401,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Content-Type': 'text/plain'
        }
      });
    }

    console.log(`[${jobId}] ✅ WebSocket authentication successful`);

    console.log(`[ProgressDO] Creating WebSocket for job ${jobId}`);

    // Create WebSocket pair
    const [client, server] = Object.values(new WebSocketPair());

    // Store server-side WebSocket
    this.webSocket = server;
    this.jobId = jobId;

    // Accept connection
    this.webSocket.accept();

    // Initialize ready promise
    this.readyPromise = new Promise((resolve) => {
      this.readyResolver = resolve;
    });

    console.log(`[${this.jobId}] WebSocket connection accepted, waiting for ready signal`);

    // Setup event handlers
    this.webSocket.addEventListener('message', (event) => {
      console.log(`[${this.jobId}] Received message:`, event.data);

      // Parse incoming message
      try {
        const msg = JSON.parse(event.data);

        // Validate message structure
        if (!msg || typeof msg !== 'object') {
          console.warn(`[${this.jobId}] Invalid message structure: not an object`);
          return;
        }

        if (!msg.type || typeof msg.type !== 'string') {
          console.warn(`[${this.jobId}] Invalid message structure: missing or invalid 'type' field`, msg);
          return;
        }

        // Handle ready signal
        if (msg.type === 'ready') {
          console.log(`[${this.jobId}] ✅ Client ready signal received`);
          this.isReady = true;

          // Resolve the ready promise to unblock processing
          if (this.readyResolver) {
            this.readyResolver();
            this.readyResolver = null; // Prevent multiple resolves
          }

          // Send acknowledgment back to client
          this.webSocket.send(JSON.stringify({
            type: 'ready_ack',
            timestamp: Date.now()
          }));
        } else {
          console.log(`[${this.jobId}] Unknown message type: ${msg.type}`);
        }
      } catch (error) {
        console.error(`[${this.jobId}] Failed to parse message:`, error);
      }
    });

    this.webSocket.addEventListener('close', (event) => {
      console.log(`[${this.jobId}] WebSocket closed:`, event.code, event.reason);
      this.cleanup();
    });

    this.webSocket.addEventListener('error', (event) => {
      console.error(`[${this.jobId}] WebSocket error:`, event);
      this.cleanup();
    });

    // Return client-side WebSocket to iOS app
    return new Response(null, {
      status: 101,
      webSocket: client,
      headers: {
        'Access-Control-Allow-Origin': '*'
      }
    });
  }

  /**
   * RPC Method: Set authentication token for WebSocket connection
   * Called by handlers before starting background processing
   *
   * @param {string} token - Authentication token (UUID)
   * @returns {Promise<{success: boolean}>}
   */
  async setAuthToken(token) {
    await this.storage.put('authToken', token);
    // Tokens expire after 2 hours
    await this.storage.put('authTokenExpiration', Date.now() + (2 * 60 * 60 * 1000));
    console.log(`[${this.jobId || 'unknown'}] Auth token set (expires in 2 hours)`);
    return { success: true };
  }

  /**
   * RPC Method: Refresh authentication token
   * Called by iOS client to extend token expiration for long-running jobs
   *
   * Security: Enforces 30-minute refresh window to prevent infinite token extension
   * Tokens can only be refreshed in the last 30 minutes before expiration
   *
   * @param {string} oldToken - Current token to validate
   * @returns {Promise<{token?: string, expiresIn?: number, error?: string}>}
   */
  async refreshAuthToken(oldToken) {
    // Prevent concurrent refresh race conditions
    if (this.refreshInProgress) {
      console.warn(`[${this.jobId || 'unknown'}] Token refresh already in progress`);
      return { error: 'Refresh in progress, please retry shortly' };
    }

    this.refreshInProgress = true;
    try {
      const storedToken = await this.storage.get('authToken');
      const expiration = await this.storage.get('authTokenExpiration');

      // Validate old token
      if (!storedToken || !oldToken || storedToken !== oldToken) {
        console.warn(`[${this.jobId || 'unknown'}] Token refresh failed - invalid token`);
        return { error: 'Invalid token' };
      }

      // Check if token is expired
      if (Date.now() > expiration) {
        console.warn(`[${this.jobId || 'unknown'}] Token refresh failed - token expired`);
        return { error: 'Token expired' };
      }

      // Enforce 30-minute refresh window (prevents infinite extension)
      // Tokens can only be refreshed in the last 30 minutes before expiration
      const REFRESH_WINDOW_MS = 30 * 60 * 1000; // 30 minutes
      const timeUntilExpiration = expiration - Date.now();
      if (timeUntilExpiration > REFRESH_WINDOW_MS) {
        const minutesRemaining = Math.floor(timeUntilExpiration / 60000);
        console.warn(`[${this.jobId || 'unknown'}] Token refresh too early - ${minutesRemaining} minutes remaining`);
        return {
          error: 'Refresh not allowed yet',
          details: `Token can be refreshed ${Math.floor((timeUntilExpiration - REFRESH_WINDOW_MS) / 60000)} minutes from now`
        };
      }

      // Generate new token and extend expiration by 2 hours
      const TOKEN_EXPIRATION_MS = 2 * 60 * 60 * 1000; // 2 hours
      const newToken = crypto.randomUUID();
      const newExpiration = Date.now() + TOKEN_EXPIRATION_MS;
      await this.storage.put('authToken', newToken);
      await this.storage.put('authTokenExpiration', newExpiration);

      console.log(`[${this.jobId || 'unknown'}] ✅ Token refreshed successfully (expires in 2 hours)`);

      return {
        token: newToken,
        expiresIn: 7200 // 2 hours in seconds
      };
    } finally {
      this.refreshInProgress = false;
    }
  }

  // =============================================================================
  // State Persistence Methods (Day 3: WebSocket Enhancements)
  // =============================================================================

  /**
   * RPC Method: Initialize job state with pipeline configuration
   * Called by handlers when starting a background job
   *
   * @param {string} pipeline - Pipeline type (batch_enrichment, csv_import, ai_scan)
   * @param {number} totalCount - Total items to process
   * @returns {Promise<{success: boolean}>}
   */
  async initializeJobState(pipeline, totalCount) {
    this.currentPipeline = pipeline;
    const state = {
      pipeline,
      totalCount,
      processedCount: 0,
      status: 'running',
      startTime: Date.now(),
      version: 1
    };

    await this.storage.put('jobState', state);
    this.lastPersistTime = Date.now();
    console.log(`[${this.jobId}] Job state initialized for ${pipeline}`);

    // NOTE: Cleanup alarm is NOT scheduled here to avoid conflicts with CSV processing alarm
    // Cleanup alarm is scheduled in completeJobState() and failJobState() after job finishes

    return { success: true };
  }

  /**
   * RPC Method: Update job state with throttling
   * Only persists every N updates or every T seconds (pipeline-specific)
   *
   * CRITICAL FIX (Issue #2): Throttle state now persisted to Durable Storage
   * to survive DO evictions and prevent lost state.
   *
   * @param {Object} updates - State updates (progress, processedCount, currentItem, etc.)
   * @returns {Promise<{success: boolean, persisted: boolean}>}
   */
  async updateJobState(updates) {
    if (!this.currentPipeline) {
      console.warn(`[${this.jobId}] Cannot update state: pipeline not initialized`);
      return { success: false, persisted: false };
    }

    // Validate pipeline exists in THROTTLE_CONFIG
    const config = THROTTLE_CONFIG[this.currentPipeline];
    if (!config) {
      console.error(`[${this.jobId}] Invalid pipeline: ${this.currentPipeline}`);
      throw new Error(`Invalid pipeline type: ${this.currentPipeline}. Valid types: ${Object.keys(THROTTLE_CONFIG).join(', ')}`);
    }

    // Load throttle state from Durable Storage (survives eviction)
    const throttleState = await this.storage.get('throttleState') || {
      updatesSinceLastPersist: 0,
      lastPersistTime: Date.now()
    };

    throttleState.updatesSinceLastPersist++;
    const timeSinceLastPersist = Date.now() - throttleState.lastPersistTime;

    const shouldPersist =
      throttleState.updatesSinceLastPersist >= config.updateCount ||
      timeSinceLastPersist >= (config.timeSeconds * 1000);

    if (shouldPersist) {
      const currentState = await this.storage.get('jobState') || {};
      const newState = {
        ...currentState,
        ...updates,
        lastUpdate: Date.now(),
        version: (currentState.version || 0) + 1
      };

      // Persist both job state and throttle state atomically
      await this.storage.put({
        jobState: newState,
        throttleState: {
          updatesSinceLastPersist: 0,
          lastPersistTime: Date.now()
        }
      });

      // Update in-memory cache for fast access
      this.updatesSinceLastPersist = 0;
      this.lastPersistTime = Date.now();

      console.log(`[${this.jobId}] State persisted (version ${newState.version})`);
      return { success: true, persisted: true };
    }

    // Update throttle state even if not persisting job state
    await this.storage.put('throttleState', throttleState);

    return { success: true, persisted: false };
  }

  /**
   * RPC Method: Get current job state
   * Used by iOS client after reconnection to sync state
   *
   * @returns {Promise<Object|null>}
   */
  async getJobState() {
    const state = await this.storage.get('jobState');
    if (state) {
      console.log(`[${this.jobId}] State retrieved (version ${state.version || 0})`);
    }
    return state || null;
  }

  /**
   * RPC Method: Get job state with authentication details
   * Used by /api/job-state endpoint for secure state sync after reconnection
   *
   * @returns {Promise<{jobState: Object, authToken: string, authTokenExpiration: number}|null>}
   */
  async getJobStateAndAuth() {
    const [jobState, authToken, authTokenExpiration] = await Promise.all([
      this.storage.get('jobState'),
      this.storage.get('authToken'),
      this.storage.get('authTokenExpiration')
    ]);

    if (!jobState) {
      console.log(`[${this.jobId}] No job state found`);
      return null;
    }

    console.log(`[${this.jobId}] State and auth retrieved (version ${jobState.version || 0})`);
    return { jobState, authToken, authTokenExpiration };
  }

  /**
   * RPC Method: Complete job and finalize state
   * Called when job finishes successfully
   *
   * @param {Object} results - Final job results
   * @returns {Promise<{success: boolean}>}
   */
  async completeJobState(results) {
    const currentState = await this.storage.get('jobState') || {};
    const finalState = {
      ...currentState,
      status: 'complete',
      endTime: Date.now(),
      results,
      version: (currentState.version || 0) + 1
    };

    await this.storage.put('jobState', finalState);
    console.log(`[${this.jobId}] Job state marked as complete`);

    // Schedule cleanup alarm for 24 hours from now (only after job completes)
    const cleanupTime = Date.now() + (24 * 60 * 60 * 1000);
    await this.storage.setAlarm(cleanupTime);
    console.log(`[${this.jobId}] Cleanup alarm scheduled for ${new Date(cleanupTime).toISOString()}`);

    return { success: true };
  }

  /**
   * RPC Method: Mark job as failed
   *
   * @param {Object} error - Error details
   * @returns {Promise<{success: boolean}>}
   */
  async failJobState(error) {
    const currentState = await this.storage.get('jobState') || {};
    const finalState = {
      ...currentState,
      status: 'failed',
      endTime: Date.now(),
      error,
      version: (currentState.version || 0) + 1
    };

    await this.storage.put('jobState', finalState);
    console.log(`[${this.jobId}] Job state marked as failed`);

    // Schedule cleanup alarm for 24 hours from now (only after job fails)
    const cleanupTime = Date.now() + (24 * 60 * 60 * 1000);
    await this.storage.setAlarm(cleanupTime);
    console.log(`[${this.jobId}] Cleanup alarm scheduled for ${new Date(cleanupTime).toISOString()}`);

    return { success: true };
  }

  // NOTE: Alarm handler is defined below at line 852 (consolidated version)

  /**
   * RPC Method: Push progress update to connected client
   * Called by background workers (enrichment, CSV import, etc.)
   */
  async pushProgress(progressData) {
    // NEW: Check if job has been canceled before pushing
    const isCanceled = (await this.storage.get("status")) === "canceled";
    if (isCanceled) {
      console.warn(`[${this.jobId}] Job is canceled, dropping progress message.`);
      // Stop the worker by throwing an error
      throw new Error("Job canceled by client");
    }

    console.log(`[ProgressDO] pushProgress called for job ${this.jobId}`, {
      hasWebSocket: !!this.webSocket,
      progressData
    });

    if (!this.webSocket) {
      const error = new Error('No WebSocket connection available');
      console.error(`[${this.jobId}] No WebSocket connection`, { error });
      throw error;
    }

    const message = JSON.stringify({
      type: 'progress',
      jobId: this.jobId,
      timestamp: Date.now(),
      data: progressData
    });

    try {
      this.webSocket.send(message);
      console.log(`[${this.jobId}] Progress sent successfully`, { messageLength: message.length });
      return { success: true };
    } catch (error) {
      console.error(`[${this.jobId}] Failed to send message:`, error);
      throw error;
    }
  }

  /**
   * RPC Method: Wait for client to send ready signal
   * Called by background processing before starting work
   *
   * @param {number} timeoutMs - Maximum time to wait (default 5000ms)
   * @returns {Promise<{success: boolean, timedOut?: boolean, disconnected?: boolean}>}
   */
  async waitForReady(timeoutMs = 5000) {
    console.log(`[${this.jobId}] waitForReady called (timeout: ${timeoutMs}ms)`);

    // If already ready, return immediately
    if (this.isReady) {
      console.log(`[${this.jobId}] Client already ready`);
      return { success: true };
    }

    // Check if WebSocket is null/closed before waiting
    if (!this.webSocket) {
      console.warn(`[${this.jobId}] ⚠️ WebSocket is null, cannot wait for ready`);
      return { success: false, disconnected: true };
    }

    // Race between ready signal, timeout, and disconnection
    const timeoutPromise = new Promise((resolve) => {
      setTimeout(() => {
        resolve({ success: false, timedOut: true });
      }, timeoutMs);
    });

    // Poll for WebSocket closure
    const disconnectPromise = new Promise((resolve) => {
      const checkInterval = setInterval(() => {
        if (!this.webSocket) {
          clearInterval(checkInterval);
          resolve({ success: false, disconnected: true });
        }
      }, 100); // Check every 100ms
    });

    const readyResult = await Promise.race([
      this.readyPromise.then(() => ({ success: true })),
      timeoutPromise,
      disconnectPromise
    ]);

    if (readyResult.timedOut) {
      console.warn(`[${this.jobId}] ⚠️ Ready timeout after ${timeoutMs}ms`);
    } else if (readyResult.disconnected) {
      console.warn(`[${this.jobId}] ⚠️ WebSocket disconnected while waiting for ready`);
    } else {
      console.log(`[${this.jobId}] ✅ Ready signal received`);
    }

    return readyResult;
  }

  /**
   * NEW RPC Method: Cancel the job and close the connection
   * Called by iOS client during library reset or explicit cancellation
   */
  async cancelJob(reason = "Job canceled by user") {
    console.log(`[${this.jobId}] Received cancelJob request`);

    // Set canceled status in durable storage
    await this.storage.put("status", "canceled");

    if (this.webSocket) {
      this.webSocket.close(1001, reason); // 1001 = Going Away
    }
    this.cleanup();
    return { success: true, status: "canceled" };
  }

  /**
   * NEW RPC Method: Check if the job has been canceled
   * Called by enrichment.js worker in processing loop
   */
  async isCanceled() {
    const status = await this.storage.get("status");
    return status === "canceled";
  }

  /**
   * RPC Method: Update progress for batch enrichment and CSV import
   * Called by background processors to send progress updates to iOS client
   *
   * @param {number} progress - Progress value (0.0 to 1.0)
   * @param {string} status - Human-readable status message
   * @param {boolean} keepAlive - If true, this is a keep-alive ping (optional)
   * @returns {Promise<{success: boolean}>}
   */
  async updateProgress(progress, status, keepAlive = false) {
    console.log(`[${this.jobId}] updateProgress called`, { progress, status, keepAlive });

    if (!this.webSocket) {
      console.warn(`[${this.jobId}] No WebSocket connection available`);
      return { success: false };
    }

    const message = {
      type: 'progress',
      jobId: this.jobId,
      timestamp: Date.now(),
      data: {
        progress,
        status,
        keepAlive
      }
    };

    try {
      this.webSocket.send(JSON.stringify(message));
      console.log(`[${this.jobId}] Progress update sent:`, { progress, status });
      return { success: true };
    } catch (error) {
      console.error(`[${this.jobId}] Failed to send progress:`, error);
      return { success: false };
    }
  }

  /**
   * RPC Method: Complete job successfully
   * Called by background processors when job finishes successfully
   *
   * @param {Object} data - Result data (books, errors, successRate, etc.)
   * @returns {Promise<{success: boolean}>}
   */
  async complete(data) {
    console.log(`[${this.jobId}] complete called`, { data });

    if (!this.webSocket) {
      console.warn(`[${this.jobId}] No WebSocket connection available`);
      return { success: false };
    }

    const message = {
      type: 'complete',
      jobId: this.jobId,
      timestamp: Date.now(),
      data
    };

    try {
      this.webSocket.send(JSON.stringify(message));
      console.log(`[${this.jobId}] Completion message sent`);

      // Close connection after completion
      setTimeout(() => {
        if (this.webSocket) {
          this.webSocket.close(1000, 'Job completed');
          this.cleanup();
        }
      }, 1000); // 1 second delay to ensure message is delivered

      return { success: true };
    } catch (error) {
      console.error(`[${this.jobId}] Failed to send completion:`, error);
      return { success: false };
    }
  }

  /**
   * RPC Method: Fail job with error
   * Called by background processors when job encounters an error
   *
   * @param {Object} errorData - Error details (error, suggestion, fallbackAvailable, etc.)
   * @returns {Promise<{success: boolean}>}
   */
  async fail(errorData) {
    console.log(`[${this.jobId}] fail called`, { errorData });

    if (!this.webSocket) {
      console.warn(`[${this.jobId}] No WebSocket connection available`);
      return { success: false };
    }

    const message = {
      type: 'error',
      jobId: this.jobId,
      timestamp: Date.now(),
      data: errorData
    };

    try {
      this.webSocket.send(JSON.stringify(message));
      console.log(`[${this.jobId}] Error message sent`);

      // Close connection after error
      setTimeout(() => {
        if (this.webSocket) {
          this.webSocket.close(1000, 'Job failed');
          this.cleanup();
        }
      }, 1000); // 1 second delay to ensure message is delivered

      return { success: true };
    } catch (error) {
      console.error(`[${this.jobId}] Failed to send error:`, error);
      return { success: false };
    }
  }

  /**
   * RPC Method: Close WebSocket connection
   */
  async closeConnection(reason = 'Job completed') {
    if (this.webSocket) {
      this.webSocket.close(1000, reason);
      this.cleanup();
    }
    return { success: true };
  }

  // =============================================================================
  // V2 Factory-Based Methods (Unified Schema)
  // =============================================================================

  /**
   * RPC Method: Send job_started message (v2 schema)
   *
   * @param {string} pipeline - Pipeline type ('batch_enrichment', 'csv_import', 'ai_scan')
   * @param {Object} payload - Job started payload (totalCount, estimatedDuration)
   * @returns {Promise<{success: boolean}>}
   */
  async sendJobStarted(pipeline, payload) {
    if (!this.webSocket) {
      console.warn(`[${this.jobId}] No WebSocket connection available`);
      return { success: false };
    }

    const message = {
      type: 'job_started',
      jobId: this.jobId,
      pipeline,
      timestamp: Date.now(),
      version: '1.0.0',
      payload: {
        type: 'job_started',
        ...payload
      }
    };

    try {
      this.webSocket.send(JSON.stringify(message));
      console.log(`[${this.jobId}] Job started message sent (v2 schema)`);
      return { success: true };
    } catch (error) {
      console.error(`[${this.jobId}] Failed to send job_started:`, error);
      return { success: false };
    }
  }

  /**
   * RPC Method: Send job_progress message (v2 schema)
   *
   * @param {string} pipeline - Pipeline type
   * @param {Object} payload - Progress payload (progress, status, processedCount, currentItem, keepAlive)
   * @returns {Promise<{success: boolean}>}
   */
  async updateProgressV2(pipeline, payload) {
    if (!this.webSocket) {
      console.warn(`[${this.jobId}] No WebSocket connection available`);
      return { success: false };
    }

    const message = {
      type: 'job_progress',
      jobId: this.jobId,
      pipeline,
      timestamp: Date.now(),
      version: '1.0.0',
      payload: {
        type: 'job_progress',
        ...payload
      }
    };

    try {
      this.webSocket.send(JSON.stringify(message));
      if (!payload.keepAlive) {
        console.log(`[${this.jobId}] Progress update sent (v2 schema): ${payload.progress}`);
      }
      return { success: true };
    } catch (error) {
      console.error(`[${this.jobId}] Failed to send job_progress:`, error);
      return { success: false };
    }
  }

  /**
   * RPC Method: Send job_complete message (v2 schema)
   *
   * @param {string} pipeline - Pipeline type
   * @param {Object} payload - Completion payload (pipeline-specific)
   * @returns {Promise<{success: boolean}>}
   */
  async completeV2(pipeline, payload) {
    if (!this.webSocket) {
      console.warn(`[${this.jobId}] No WebSocket connection available`);
      return { success: false };
    }

    const message = {
      type: 'job_complete',
      jobId: this.jobId,
      pipeline,
      timestamp: Date.now(),
      version: '1.0.0',
      payload: {
        type: 'job_complete',
        pipeline,
        ...payload
      }
    };

    try {
      this.webSocket.send(JSON.stringify(message));
      console.log(`[${this.jobId}] Job complete message sent (v2 schema)`);

      // Close connection after completion
      setTimeout(() => {
        if (this.webSocket) {
          this.webSocket.close(1000, 'Job completed');
          this.cleanup();
        }
      }, 1000); // 1 second delay to ensure message is delivered

      return { success: true };
    } catch (error) {
      console.error(`[${this.jobId}] Failed to send job_complete:`, error);
      return { success: false };
    }
  }

  /**
   * RPC Method: Send error message (v2 schema)
   *
   * @param {string} pipeline - Pipeline type
   * @param {Object} payload - Error payload (code, message, details, retryable)
   * @returns {Promise<{success: boolean}>}
   */
  async sendError(pipeline, payload) {
    if (!this.webSocket) {
      console.warn(`[${this.jobId}] No WebSocket connection available`);
      return { success: false };
    }

    const message = {
      type: 'error',
      jobId: this.jobId,
      pipeline,
      timestamp: Date.now(),
      version: '1.0.0',
      payload: {
        type: 'error',
        ...payload
      }
    };

    try {
      this.webSocket.send(JSON.stringify(message));
      console.log(`[${this.jobId}] Error message sent (v2 schema): ${payload.code}`);

      // Close connection after error
      setTimeout(() => {
        if (this.webSocket) {
          this.webSocket.close(1000, 'Job failed');
          this.cleanup();
        }
      }, 1000); // 1 second delay to ensure message is delivered

      return { success: true };
    } catch (error) {
      console.error(`[${this.jobId}] Failed to send error:`, error);
      return { success: false };
    }
  }

  /**
   * Internal cleanup
   */
  cleanup() {
    this.webSocket = null;
    this.jobId = null;
    // IMPORTANT: Do NOT clear "canceled" status from storage
    // Worker needs to check cancellation state after socket closes
  }

  /**
   * RPC Method: Schedule CSV processing via Durable Object alarm
   * Called by csv-import.js to avoid ctx.waitUntil() timeout
   *
   * @param {string} csvText - Raw CSV file content
   * @param {string} jobId - Job identifier
   * @returns {Promise<{success: boolean}>}
   */
  async scheduleCSVProcessing(csvText, jobId) {
    console.log(`[${jobId}] Scheduling CSV processing via alarm`);

    // Store CSV data and job metadata in Durable Object storage
    await this.storage.put('csvData', csvText);
    await this.storage.put('jobId', jobId);
    await this.storage.put('jobType', 'csv-import');

    // Schedule alarm with 2-second delay to ensure WebSocket connects
    // iOS needs time to: receive HTTP 202 → extract jobId → connect WebSocket → send ready
    const alarmTime = Date.now() + 2000;
    await this.storage.setAlarm(alarmTime);

    console.log(`[${jobId}] CSV processing alarm scheduled for ${new Date(alarmTime).toISOString()}`);

    return { success: true };
  }

  /**
   * Alarm handler: Process long-running background jobs or cleanup
   * Runs outside ctx.waitUntil() timeout limits
   *
   * Handles two types of alarms:
   * 1. CSV Import Processing - jobType='csv-import', scheduled 2s after upload
   * 2. State Cleanup - No jobType, scheduled 24h after job completion
   */
  async alarm() {
    const jobType = await this.storage.get('jobType');
    const jobId = await this.storage.get('jobId');

    if (jobType === 'csv-import') {
      // CSV processing alarm (scheduled at 2s by scheduleCSVProcessing)
      console.log(`[${jobId}] Alarm triggered for CSV import processing`);
      await this.processCSVImportAlarm();
    } else {
      // Cleanup alarm (scheduled at 24h by completeJobState/failJobState)
      console.log(`[${jobId || 'unknown'}] Cleanup alarm triggered - removing old state`);
      await this.storage.delete('jobState');
      await this.storage.delete('authToken');
      await this.storage.delete('authTokenExpiration');
    }
  }

  /**
   * Process CSV import inside Durable Object alarm
   * No ctx.waitUntil() timeout - can run indefinitely
   */
  async processCSVImportAlarm() {
    const csvText = await this.storage.get('csvData');
    const jobId = await this.storage.get('jobId');

    console.log(`[${jobId}] Starting CSV processing in alarm (no timeout limits)`);

    try {
      // Import processing logic (need to inline or import)
      const { processCSVImportCore } = await import('../handlers/csv-import.js');

      // Process CSV with access to this (DO stub methods)
      await processCSVImportCore(csvText, jobId, this, this.env);

      console.log(`[${jobId}] CSV processing completed successfully`);

      // Clean up storage
      await this.storage.delete('csvData');
      await this.storage.delete('jobId');
      await this.storage.delete('jobType');

    } catch (error) {
      console.error(`[${jobId}] CSV processing failed in alarm:`, error);

      // CRITICAL FIX (Issues #347, #379): Use v2 unified schema method
      // Send error to client using sendError (v2) instead of fail (v1 legacy)
      await this.sendError('csv_import', {
        code: 'CSV_PROCESSING_ERROR',
        message: error.message,
        details: {
          fallbackAvailable: true,
          suggestion: 'Try manual CSV import instead'
        },
        retryable: true
      });

      // Clean up storage even on error
      await this.storage.delete('csvData');
      await this.storage.delete('jobId');
      await this.storage.delete('jobType');
    }
  }

  /**
   * RPC Method: Initialize batch job with photo array
   * Called by batch-scan-handler.js when batch upload starts
   */
  async initBatch({ jobId, totalPhotos, status }) {
    console.log(`[ProgressDO] initBatch called for job ${jobId}`, { totalPhotos, status });

    // I2: Type validation
    if (typeof jobId !== 'string' || jobId.trim().length === 0) {
      throw new Error('jobId must be a non-empty string');
    }
    if (typeof totalPhotos !== 'number' || totalPhotos < 1 || totalPhotos > 5) {
      throw new Error('totalPhotos must be a number between 1 and 5');
    }

    // C2: Clear legacy state to prevent key collisions
    await this.storage.delete('status');

    // Initialize batch state with photo array
    const photos = Array.from({ length: totalPhotos }, (_, i) => ({
      index: i,
      status: 'queued',
      booksFound: 0
    }));

    const batchState = {
      jobId,
      type: 'batch',
      totalPhotos,
      photos,
      overallStatus: status,
      currentPhoto: null,
      totalBooksFound: 0,
      cancelRequested: false
    };

    await this.storage.put('batchState', batchState);

    // Broadcast initialization to connected clients
    this.broadcastToClients({
      type: 'batch-init',
      // No longer need top-level jobId, it's added by broadcastToClients
      totalPhotos,
      status
    });

    return { success: true };
  }

  /**
   * RPC Method: Update photo status in batch
   * Called by batch-scan-handler.js after each photo processes
   */
  async updatePhoto({ photoIndex, status, booksFound, error }) {
    console.log(`[ProgressDO] updatePhoto called`, { photoIndex, status, booksFound, error });

    // I2: Type validation
    if (typeof photoIndex !== 'number') {
      throw new Error('photoIndex must be a number');
    }

    const batchState = await this.storage.get('batchState');
    if (!batchState || batchState.type !== 'batch') {
      console.error('[ProgressDO] Batch job not found');
      return { error: 'Batch job not found' };
    }

    // C3: Array bounds validation
    if (photoIndex < 0 || photoIndex >= batchState.photos.length) {
      return { error: `Invalid photo index: ${photoIndex}` };
    }

    // Update photo state
    batchState.photos[photoIndex].status = status;

    if (booksFound !== undefined) {
      batchState.photos[photoIndex].booksFound = booksFound;
    }

    if (error) {
      batchState.photos[photoIndex].error = error;
    }

    // Update current photo pointer
    if (status === 'processing') {
      batchState.currentPhoto = photoIndex;
    }

    // Recalculate total books found
    batchState.totalBooksFound = batchState.photos.reduce(
      (sum, p) => sum + (p.booksFound || 0),
      0
    );

    await this.storage.put('batchState', batchState);

    // Broadcast update to connected clients
    this.broadcastToClients({
      type: 'batch-progress',
      currentPhoto: photoIndex,
      totalPhotos: batchState.totalPhotos,
      photoStatus: status,
      booksFound: booksFound || 0,
      totalBooksFound: batchState.totalBooksFound,
      photos: batchState.photos
    });

    return { success: true };
  }

  /**
   * RPC Method: Complete batch processing
   * Called by batch-scan-handler.js when all photos are processed
   */
  async completeBatch({ status, totalBooks, photoResults, books }) {
    console.log(`[ProgressDO] completeBatch called`, { status, totalBooks });

    // I2: Type validation
    if (typeof totalBooks !== 'number') {
      throw new Error('totalBooks must be a number');
    }

    const batchState = await this.storage.get('batchState');
    if (!batchState) {
      console.error('[ProgressDO] Job not found');
      return { error: 'Job not found' };
    }

    batchState.overallStatus = status || 'complete';
    batchState.totalBooksFound = totalBooks;
    batchState.finalResults = books;

    await this.storage.put('batchState', batchState);

    // Broadcast completion
    this.broadcastToClients({
      type: 'batch-complete',
      totalBooks,
      photoResults,
      books
    });

    return { success: true };
  }

  /**
   * RPC Method: Get current batch state
   * Called by test endpoints to verify state
   */
  async getState() {
    const batchState = await this.storage.get('batchState');
    return batchState || {};
  }

  /**
   * RPC Method: Check if batch has been canceled
   * Called by batch-scan-handler.js in processing loop
   */
  async isBatchCanceled() {
    const batchState = await this.storage.get('batchState');
    return { canceled: batchState?.cancelRequested || false };
  }

  /**
   * RPC Method: Cancel batch processing
   * Called by iOS client or test endpoints
   */
  async cancelBatch() {
    console.log(`[ProgressDO] cancelBatch called`);

    const batchState = await this.storage.get('batchState');

    if (!batchState) {
      return { error: 'Job not found' };
    }

    batchState.cancelRequested = true;
    batchState.overallStatus = 'canceling';

    await this.storage.put('batchState', batchState);

    // Broadcast cancellation
    this.broadcastToClients({
      type: 'batch-canceling'
    });

    return { success: true };
  }

  /**
   * Helper: Broadcast message to all connected WebSocket clients
   */
  broadcastToClients(data) {
    if (!this.webSocket) {
      console.warn('[ProgressDO] No WebSocket connection to broadcast to');
      return;
    }

    try {
      // Standardize message format to match `pushProgress` and prevent client-side parsing errors
      // The client expects a consistent top-level structure with a `data` payload.
      const message = {
        type: data.type || 'progress', // The payload should always have a type
        jobId: this.jobId,
        timestamp: Date.now(),
        data, // The original object is now the payload
      };

      this.webSocket.send(JSON.stringify(message));
      console.log(`[ProgressDO] Broadcast sent:`, message.type);
    } catch (error) {
      console.error('[ProgressDO] Failed to send to client:', error);
    }
  }
}
