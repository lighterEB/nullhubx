import { writable, derived, get } from 'svelte/store';
import { api } from './api/client';

/**
 * Global status store - singleton pattern
 * Deduplicates API calls across components
 *
 * Polling strategy:
 * - Adaptive interval with exponential backoff on failures
 * - Pauses when page is not visible (saves battery & bandwidth)
 * - Resumes when page becomes visible again
 * - Stops only when ALL subscribers are gone
 */

const BASE_REFRESH_INTERVAL = 5000; // 5 seconds base
const MAX_REFRESH_INTERVAL = 30000; // 30 seconds max on repeated failures
const MIN_REFRESH_GAP = 800; // Minimum gap between manual refreshes
const STATUS_RETRY_DELAY_MS = 200;
const STATUS_MAX_ATTEMPTS = 2;

let lastFetch = 0;
let pendingRequest: Promise<GlobalStatus> | null = null;
let intervalId: ReturnType<typeof setInterval> | null = null;
let subscriberCount = 0;
let consecutiveStatusFailures = 0;
let isPolling = false;
let hasInitialData = false;
let unsubscribeTimeout: ReturnType<typeof setTimeout> | null = null;
let currentRefreshInterval = BASE_REFRESH_INTERVAL;

// Svelte stores
import type { GlobalStatus, InstanceInfo, InstancesPayload } from './api/client';
export const status = writable<GlobalStatus | null>(null);
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

async function fetchStatusWithRetry(): Promise<GlobalStatus> {
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

async function fetchStatus(): Promise<GlobalStatus> {
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
    const previous = get(status);
    status.set({
      ...(previous ?? {}),
      ...result,
      instances: result.instances ?? previous?.instances ?? {},
    });
    consecutiveStatusFailures = 0;
    statusError.set(null);
    hasInitialData = true;
    lastFetch = now;
    // Reset interval on success
    currentRefreshInterval = BASE_REFRESH_INTERVAL;
    return get(status) ?? result;
  } catch (e) {
    consecutiveStatusFailures += 1;
    const hasCachedStatus = Boolean(get(status));
    if (!hasCachedStatus || consecutiveStatusFailures >= 2) {
      statusError.set((e as Error).message);
    } else {
      statusError.set(null);
    }
    // Exponential backoff: 5s -> 10s -> 20s -> 30s (max)
    currentRefreshInterval = Math.min(
      currentRefreshInterval * 1.5,
      MAX_REFRESH_INTERVAL
    );
    // Reconfigure interval with new timing
    if (intervalId && isPolling) {
      clearInterval(intervalId);
      intervalId = setInterval(() => {
        fetchStatus().catch(() => {});
      }, currentRefreshInterval);
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
  }, currentRefreshInterval);

  // Pause polling when page is not visible
  document.addEventListener('visibilitychange', handleVisibilityChange);
}

function handleVisibilityChange() {
  if (document.hidden) {
    // Page is hidden - pause polling to save resources
    if (intervalId) {
      clearInterval(intervalId);
      intervalId = null;
    }
  } else {
    // Page is visible again - resume polling
    if (isPolling && subscriberCount > 0) {
      intervalId = setInterval(() => {
        fetchStatus().catch(() => {});
      }, currentRefreshInterval);
      // Fresh fetch on resume
      fetchStatus().catch(() => {});
    }
  }
}

function stopPolling() {
  if (intervalId) {
    clearInterval(intervalId);
    intervalId = null;
  }
  isPolling = false;
  hasInitialData = false;
  document.removeEventListener('visibilitychange', handleVisibilityChange);
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
  const groups: InstancesPayload = $status?.instances ?? {};
  for (const instances of Object.values(groups)) {
    count += Object.keys(instances).length;
  }
  return count;
});

export const runningCount = derived(status, ($status) => {
  let count = 0;
  const groups: InstancesPayload = $status?.instances ?? {};
  for (const instances of Object.values(groups)) {
    for (const inst of Object.values(instances) as InstanceInfo[]) {
      if (inst.status === "running") count++;
    }
  }
  return count;
});

export const hubVersion = derived(status, ($status) => $status?.version || "unknown");

export const hubConnected = derived([status, statusError], ([$status, $error]) =>
  $status !== null && $error === null
);
