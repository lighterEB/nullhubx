<script>
  import '../app.css';
  import { onMount } from 'svelte';
  import { preloadCode } from '$app/navigation';
  import TopBar from '$lib/components/TopBar.svelte';
  import StatusBar from '$lib/components/StatusBar.svelte';
  import { redirectToPreferredOrigin } from '$lib/nullhubxAccess';
  import { subscribeStatus } from '$lib/statusStore';
  import ToastContainer from '$lib/components/ToastContainer.svelte';

  let { children } = $props();

  // Run redirect check in background - don't block initial render
  onMount(() => {
    void redirectToPreferredOrigin(window.location);

    const unsubscribeStatus = subscribeStatus();

    void Promise.allSettled([
      preloadCode('/'),
      preloadCode('/instances'),
      preloadCode('/connections'),
      preloadCode('/orchestration'),
      preloadCode('/settings')
    ]);

    return () => {
      unsubscribeStatus();
    };
  });
</script>

<div class="app-layout">
  <TopBar />
  <ToastContainer />
  <main class="content">
    {@render children()}
  </main>
  <StatusBar />
</div>

<style>
  .app-layout {
    display: flex;
    flex-direction: column;
    min-height: 100vh;
  }

  .content {
    flex: 1;
    margin-top: var(--topbar-height);
    margin-bottom: var(--statusbar-height);
    overflow-y: auto;
  }
</style>
