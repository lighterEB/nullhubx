import { writable, derived, get } from 'svelte/store';
import { api } from './api/client';

/**
 * Global status store - singleton pattern
 * Deduplicates API calls across components
 * 
 * Polling strategy:
 * - Start polling immediately on first subscription
 * - Keep polling across route changes for smoother UX
 * - Stop polling only when ALL subscribers are gone
 */

const REFRESH_INTERVAL = 3000; // 3 seconds
const MIN_REFRESH_GAP = 500; // Minimum gap between manual refreshes
const STATUS_RETRY_DELAY_MS = 200;
const STATUS_MAX_ATTEMPTS = 2;

let lastFetch = 0;
let pendingRequest: Promise<any> | null = null;
let intervalId: ReturnType<typeof setInterval> | null = null;
let subscriberCount = 0;
let consecutiveStatusFailures = 0;
let isPolling = false;
let hasInitialData = false;
let unsubscribeTimeout: ReturnType<typeof setTimeout> | null = null;

// Svelte stores
export const status = writable<any>(null);
export const statusError = writable<string | null>(null);
export const isLoading = writable(false);

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isTransientStatusError(err: unknown): boolean {
  if (!(err instanceof Error)) return false;
  const msg = err.message.toLowerCase();
  return (
    msg.includes('请求超时') ||
    msg.includes('failed to fetch') ||
    msg.includes('networkerror') ||
    msg.includes('abort')
  );
}

async function fetchStatusWithRetry(): Promise<any> {
  let lastErr: unknown = null;
  for (let attempt = 1; attempt <= STATUS_MAX_ATTEMPTS; attempt++) {
    try {
      return await api.getStatus();
    } catch (err) {
      lastErr = err;
      const canRetry = attempt < STATUS_MAX_ATTEMPTS && isTransientStatusError(err);
      if (canRetry) {
        await sleep(STATUS_RETRY_DELAY_MS);
        continue;
      }
      throw err;
    }
  }
  throw lastErr;
}

async function fetchStatus(): Promise<any> {
  // Deduplicate concurrent requests
  if (pendingRequest) {
    return pendingRequest;
  }

  // Throttle rapid successive calls
  const now = Date.now();
  const currentStatus = get(status);
  if (now - lastFetch < MIN_REFRESH_GAP && currentStatus && hasInitialData) {
    return currentStatus;
  }

  isLoading.set(true);
  pendingRequest = fetchStatusWithRetry();

  try {
    const result = await pendingRequest;
    const previous = get(status) ?? {};
    status.set({
      ...previous,
      ...result,
      instances: result?.instances ?? previous?.instances ?? {},
    });
    consecutiveStatusFailures = 0;
    statusError.set(null);
    hasInitialData = true;
    lastFetch = now;
    return get(status);
  } catch (e) {
    consecutiveStatusFailures += 1;
    const hasCachedStatus = Boolean(get(status));
    if (!hasCachedStatus || consecutiveStatusFailures >= 2) {
      statusError.set((e as Error).message);
    } else {
      statusError.set(null);
    }
    throw e;
  } finally {
    isLoading.set(false);
    pendingRequest = null;
  }
}

function startPolling() {
  if (isPolling) return;
  isPolling = true;

  // Immediate initial fetch - no delay for faster first paint
  fetchStatus().catch(() => {});

  intervalId = setInterval(() => {
    fetchStatus().catch(() => {});
  }, REFRESH_INTERVAL);
}

function stopPolling() {
  if (intervalId) {
    clearInterval(intervalId);
    intervalId = null;
  }
  isPolling = false;
  hasInitialData = false;
}

function scheduleStopPolling() {
  // Delay stopping to allow for quick re-subscription during navigation
  if (unsubscribeTimeout) {
    clearTimeout(unsubscribeTimeout);
  }
  
  unsubscribeTimeout = setTimeout(() => {
    if (subscriberCount <= 0) {
      stopPolling();
    }
    unsubscribeTimeout = null;
  }, 2000); // 2 second grace period
}

/**
 * Subscribe to status updates
 * Call the returned function to unsubscribe
 */
export function subscribeStatus() {
  subscriberCount++;
  
  // Cancel any pending stop
  if (unsubscribeTimeout) {
    clearTimeout(unsubscribeTimeout);
    unsubscribeTimeout = null;
  }
  
  startPolling();

  return () => {
    subscriberCount--;
    if (subscriberCount <= 0) {
      // Schedule stop with grace period for navigation
      scheduleStopPolling();
    }
  };
}

/**
 * Force refresh status
 */
export async function refreshStatus() {
  try {
    return await fetchStatus();
  } catch {
    return null;
  }
}

// Derived stores
export const instanceCount = derived(status, ($status) => {
  let count = 0;
  for (const instances of Object.values($status?.instances || {})) {
    count += Object.keys(instances as Record<string, any>).length;
  }
  return count;
});

export const runningCount = derived(status, ($status) => {
  let count = 0;
  for (const instances of Object.values($status?.instances || {})) {
    for (const inst of Object.values(instances as Record<string, any>)) {
      if ((inst as any).status === "running") count++;
    }
  }
  return count;
});

export const hubVersion = derived(status, ($status) => $status?.version || "unknown");

export const hubConnected = derived([status, statusError], ([$status, $error]) =>
  $status !== null && $error === null
);
