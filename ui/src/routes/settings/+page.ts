import { api, type JsonObject, type ServiceStatusResponse } from '$lib/api/client';
import type { PageLoad } from './$types';

export const load: PageLoad = async () => {
  const [settingsResult, serviceResult] = await Promise.allSettled([
    api.getSettings(),
    api.serviceStatus(),
  ]);

  return {
    settings:
      settingsResult.status === 'fulfilled'
        ? (settingsResult.value as JsonObject)
        : null,
    settingsLoadError:
      settingsResult.status === 'rejected'
        ? (settingsResult.reason as Error)?.message || 'Failed to load settings'
        : '',
    serviceStatus:
      serviceResult.status === 'fulfilled'
        ? serviceResult.value
        : null,
    serviceStatusError:
      serviceResult.status === 'rejected'
        ? (serviceResult.reason as Error)?.message || 'Failed to load service status'
        : '',
  } satisfies {
    settings: JsonObject | null;
    settingsLoadError: string;
    serviceStatus: ServiceStatusResponse | null;
    serviceStatusError: string;
  };
};
