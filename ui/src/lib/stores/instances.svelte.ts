import { api } from '$lib/api/client';

let data = $state<any>({ hub: null, instances: {} });
let loading = $state(true);
let error = $state<string | null>(null);
let interval: ReturnType<typeof setInterval> | null = null;

async function refresh() {
  try {
    data = await api.getStatus();
    error = null;
  } catch (e) {
    error = (e as Error).message;
  } finally {
    loading = false;
  }
}

export function startPolling(ms = 5000) {
  refresh();
  interval = setInterval(refresh, ms);
}

export function stopPolling() {
  if (interval) clearInterval(interval);
}

export function getInstances() { return data; }
export function isLoading() { return loading; }
export function getError() { return error; }
