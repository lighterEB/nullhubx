import { browser } from '$app/environment';
import { redirectToPreferredOrigin } from '$lib/nullhubxAccess';

export const ssr = false;
export const prerender = false;

export async function load() {
  if (browser) {
    await redirectToPreferredOrigin(window.location);
  }
}
