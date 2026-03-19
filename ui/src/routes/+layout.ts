import type { LoadEvent } from '@sveltejs/kit';
// @ts-ignore
import { api } from '$lib/api/client';
import { browser } from '$app/environment';

export const ssr = false;
export const prerender = false;

function hasAnyInstances(payload: any): boolean {
  const groups = payload?.instances ?? {};
  for (const instances of Object.values(groups) as Array<Record<string, unknown>>) {
    if (Object.keys(instances || {}).length > 0) return true;
  }
  return false;
}

export async function load({ url }: LoadEvent) {
  if (!browser) return;
  
  // 非阻塞检查：仅当“确认没有任何实例”时才跳转到 Hub。
  api.getInstances()
    .then((instancesPayload) => {
      if (!hasAnyInstances(instancesPayload) && !url.pathname.startsWith('/hub')) {
        if (browser && typeof window !== 'undefined') {
          window.location.href = '/hub';
        }
      }
    })
    .catch(() => {
      // API error - let page render
    });
}
