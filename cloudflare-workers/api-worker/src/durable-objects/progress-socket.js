import { DurableObject } from 'cloudflare:workers';

/**
 * Durable Object for managing WebSocket connections per job
 * One instance per jobId - stores WebSocket connection and forwards progress messages
 *
 * Migrated from progress-websocket-durable-object/src/index.js
 */
export class ProgressWebSocketDO extends DurableObject {
  constructor(state, env) {
    super(state, env);
    this.storage = state.storage; // Durable Object storage for cancellation state
    this.webSocket = null;
    this.jobId = null;
    this.isReady = false; // NEW: Track if client sent ready signal
    this.readyPromise = null; // NEW: Promise to await ready signal
    this.readyResolver = null; // NEW: Resolver for ready promise
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
      jobId,
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
      jobId: batchState.jobId,
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
      jobId: batchState.jobId,
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
      type: 'batch-canceling',
      jobId: batchState.jobId
    });

    return { success: true };
  }

  /**
   * Helper: Broadcast message to all connected WebSocket clients
   */
  broadcastToClients(message) {
    if (!this.webSocket) {
      console.warn('[ProgressDO] No WebSocket connection to broadcast to');
      return;
    }

    try {
      this.webSocket.send(JSON.stringify(message));
      console.log(`[ProgressDO] Broadcast sent:`, message.type);
    } catch (error) {
      console.error('[ProgressDO] Failed to send to client:', error);
    }
  }
}
