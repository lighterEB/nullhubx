/**
 * SSE Client for real-time log streaming
 *
 * Features:
 * - Automatic reconnection with exponential backoff
 * - Message buffering for late subscribers
 * - Proper cleanup on disconnect
 */

export type SseEvent = {
  type: 'connected' | 'snapshot' | 'log' | 'end' | 'error';
  source: 'instance' | 'nullhubx';
  data: unknown;
};

export type SseClientOptions = {
  bufferSize?: number;
  maxReconnectAttempts?: number;
  reconnectDelay?: number;
  onEvent?: (event: SseEvent) => void;
  onError?: (error: Error) => void;
  onClose?: () => void;
};

const DEFAULT_OPTIONS: Partial<SseClientOptions> = {
  bufferSize: 1000,
  maxReconnectAttempts: 5,
  reconnectDelay: 1000,
};

export class SseClient {
  private eventSource: EventSource | null = null;
  private url: string = '';
  private options: SseClientOptions;
  private messageBuffer: SseEvent[] = [];
  private reconnectAttempts = 0;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private isConnecting = false;
  private isClosed = false;
  private currentSource: 'instance' | 'nullhubx' = 'instance';

  constructor(options: SseClientOptions = {}) {
    this.options = { ...DEFAULT_OPTIONS, ...options };
  }

  connect(component: string, name: string, source: 'instance' | 'nullhubx' = 'instance') {
    if (this.isConnecting || this.eventSource) {
      this.close();
    }

    this.isClosed = false;
    this.isConnecting = true;
    this.currentSource = source;
    this.url = `/api/instances/${encodeURIComponent(component)}/${encodeURIComponent(name)}/logs/sse?source=${source}`;

    this.setupConnection();
  }

  private setupConnection() {
    try {
      if (this.reconnectTimer) {
        clearTimeout(this.reconnectTimer);
        this.reconnectTimer = null;
      }
      if (this.eventSource) {
        this.eventSource.close();
        this.eventSource = null;
      }

      this.eventSource = new EventSource(this.url);

      this.eventSource.onopen = () => {
        this.isConnecting = false;
        this.reconnectAttempts = 0;
        this.emitEvent({ type: 'connected', source: this.currentSource, data: { status: 'connected' } });
      };

      this.eventSource.onmessage = (event) => {
        try {
          const parsed = JSON.parse(event.data) as {
            type?: SseEvent['type'];
            source?: SseEvent['source'];
            data?: unknown;
          };
          const sseEvent: SseEvent = {
            type: parsed.type || 'log',
            source: parsed.source || 'instance',
            data: parsed.data || parsed,
          };

          // Buffer messages
          this.messageBuffer.push(sseEvent);
          if (this.messageBuffer.length > (this.options.bufferSize || 1000)) {
            this.messageBuffer.shift();
          }

          this.emitEvent(sseEvent);
        } catch (err) {
          console.error('[SSE] Failed to parse message:', err);
        }
      };

      this.eventSource.onerror = (err) => {
        this.isConnecting = false;
        if (this.eventSource) {
          this.eventSource.close();
          this.eventSource = null;
        }

        const error = new Error('SSE connection error');
        this.emitEvent({ type: 'error', source: this.currentSource, data: { error: err } });
        this.options.onError?.(error);

        // Attempt reconnection
        this.handleReconnect();
      };
    } catch (err) {
      this.isConnecting = false;
      this.options.onError?.(err as Error);
    }
  }

  private handleReconnect() {
    if (this.isClosed) return;

    const maxAttempts = this.options.maxReconnectAttempts ?? 5;
    if (this.reconnectAttempts >= maxAttempts) {
      if (this.eventSource) {
        this.eventSource.close();
        this.eventSource = null;
      }
      this.options.onClose?.();
      return;
    }

    this.reconnectAttempts++;
    const delay = Math.min(
      (this.options.reconnectDelay || 1000) * Math.pow(2, this.reconnectAttempts - 1),
      30000
    );

    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
    }
    this.reconnectTimer = setTimeout(() => {
      if (!this.isClosed) {
        this.setupConnection();
      }
    }, delay);
  }

  private emitEvent(event: SseEvent) {
    this.options.onEvent?.(event);
  }

  getBuffer(): SseEvent[] {
    return [...this.messageBuffer];
  }

  clearBuffer() {
    this.messageBuffer = [];
  }

  close() {
    this.isClosed = true;
    this.isConnecting = false;

    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    if (this.eventSource) {
      this.eventSource.close();
      this.eventSource = null;
    }
  }
}

/**
 * Hook-like helper for Svelte components
 */
export function createSseClient(
  component: string,
  name: string,
  source: 'instance' | 'nullhubx' = 'instance',
  callbacks?: {
    onLog?: (data: unknown) => void;
    onError?: (error: Error) => void;
    onClose?: () => void;
  }
) {
  const client = new SseClient({
    onEvent: (event) => {
      if (event.type === 'log' && callbacks?.onLog) {
        callbacks.onLog(event.data);
      }
    },
    onError: callbacks?.onError,
    onClose: callbacks?.onClose,
  });

  client.connect(component, name, source);

  return client;
}
