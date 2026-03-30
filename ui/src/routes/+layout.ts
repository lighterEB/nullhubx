import { redirect, type LoadEvent } from '@sveltejs/kit';
import { api, type InstancesResponse } from '$lib/api/client';
import { browser } from '$app/environment';

export const ssr = false;
export const prerender = false;

function hasAnyInstances(payload: InstancesResponse | null | undefined): boolean {
  const groups = payload?.instances ?? {};
  for (const instances of Object.values(groups) as Array<Record<string, unknown>>) {
    if (Object.keys(instances || {}).length > 0) return true;
  }
  return false;
}

export async function load({ url }: LoadEvent) {
  if (!browser) return;

  if (!url.pathname.startsWith('/hub')) {
    let instancesPayload;
    try {
      instancesPayload = await api.getInstances();
    } catch {
      // API error - let page render
      return;
    }

    if (!hasAnyInstances(instancesPayload)) {
      redirect(302, '/hub');
    }
  }
}
