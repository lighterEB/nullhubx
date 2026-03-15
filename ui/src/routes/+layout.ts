import { redirect, type LoadEvent } from '@sveltejs/kit';
// @ts-ignore
import { api } from '$lib/api/client';
import { browser } from '$app/environment';

export const ssr = false;
export const prerender = false;

export async function load({ url }: LoadEvent) {
  if (!browser) return;
  
  // Non-blocking check - don't await, let it resolve in background
  // This prevents blocking the entire page load
  api.getStatus()
    .then((status) => {
      const hasNullClaw = Object.keys(status.instances || {}).includes('nullclaw');
      // 如果没有安装 nullclaw 且当前不在 hub 页，跳转
      if (!hasNullClaw && !url.pathname.startsWith('/hub')) {
        // Use window.location for client-side redirect after initial load
        if (browser && typeof window !== 'undefined') {
          window.location.href = '/hub';
        }
      }
    })
    .catch(() => {
      // API error - let the page handle it
    });
}
