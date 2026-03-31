import { get } from 'svelte/store';
import { status } from '$lib/statusStore';

export function load({ params }: { params: { component: string; name: string } }) {
  const { component, name } = params;
  const globalStatus = get(status);
  const initialStatus = globalStatus?.instances?.[component]?.[name] ?? null;
  
  return {
    initialStatus
  };
}
