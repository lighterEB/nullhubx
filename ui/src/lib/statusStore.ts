import { writable, derived, get } from 'svelte/store';
import { api } from './api/client';

/**
 * Global status store - singleton pattern
 * Deduplicates API calls across components
 */

const REFRESH_INTERVAL = 5000; // 5 seconds
const MIN_REFRESH_GAP = 1000; // Minimum gap between manual refreshes

let lastFetch = 0;
let pendingRequest: Promise<any> | null = null;
let intervalId: ReturnType<typeof setInterval> | null = null;
let subscriberCount = 0;

// Svelte stores
export const status = writable<any>(null);
export const statusError = writable<string | null>(null);
export const isLoading = writable(false);

async function fetchStatus(): Promise<any> {
  // Deduplicate concurrent requests
  if (pendingRequest) {
    return pendingRequest;
  }

  // Throttle rapid successive calls
  const now = Date.now();
  const currentStatus = get(status);
  if (now - lastFetch < MIN_REFRESH_GAP && currentStatus) {
    return currentStatus;
  }

  isLoading.set(true);
  pendingRequest = api.getStatus();

  try {
    const result = await pendingRequest;
    status.set(result);
    statusError.set(null);
    lastFetch = now;
    return result;
  } catch (e) {
    statusError.set((e as Error).message);
    throw e;
  } finally {
    isLoading.set(false);
    pendingRequest = null;
  }
}

function startPolling() {
  if (intervalId) return;

  // Initial fetch
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
}

/**
 * Subscribe to status updates
 * Call the returned function to unsubscribe
 */
export function subscribeStatus() {
  subscriberCount++;
  startPolling();

  return () => {
    subscriberCount--;
    if (subscriberCount <= 0) {
      subscriberCount = 0;
      stopPolling();
    }
  };
}

/**
 * Force refresh status
 */
export async function refreshStatus() {
  return fetchStatus();
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