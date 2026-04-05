import {
  api,
  type CapabilitiesResponse,
  type JsonObject,
  type ServiceStatusResponse,
} from '$lib/api/client';
import type { PageLoad } from './$types';

export const load: PageLoad = async () => {
  const [settingsResult, serviceResult, capabilitiesResult] = await Promise.allSettled([
    api.getSettings(),
    api.serviceStatus(),
    api.getCapabilities(),
  ]);

  return {
    settings: settingsResult.status === 'fulfilled' ? (settingsResult.value as JsonObject) : null,
    settingsLoadError:
      settingsResult.status === 'rejected'
        ? (settingsResult.reason as Error)?.message || 'Failed to load settings'
        : '',
    serviceStatus: serviceResult.status === 'fulfilled' ? serviceResult.value : null,
    serviceStatusError:
      serviceResult.status === 'rejected'
        ? (serviceResult.reason as Error)?.message || 'Failed to load service status'
        : '',
    capabilities: capabilitiesResult.status === 'fulfilled' ? capabilitiesResult.value : null,
    capabilitiesLoadError:
      capabilitiesResult.status === 'rejected'
        ? (capabilitiesResult.reason as Error)?.message || 'Failed to load capability matrix'
        : '',
  } satisfies {
    settings: JsonObject | null;
    settingsLoadError: string;
    serviceStatus: ServiceStatusResponse | null;
    serviceStatusError: string;
    capabilities: CapabilitiesResponse | null;
    capabilitiesLoadError: string;
  };
};
