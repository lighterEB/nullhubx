<script>
  import '../app.css';
  import { onMount } from 'svelte';
  import TopBar from '$lib/components/TopBar.svelte';
  import StatusBar from '$lib/components/StatusBar.svelte';
  import { redirectToPreferredOrigin } from '$lib/nullhubxAccess';
  import { subscribeStatus } from '$lib/statusStore';

  let { children } = $props();

  // Run redirect check in background - don't block initial render
  onMount(() => {
    const unsubscribeStatus = subscribeStatus();

    // Delay redirect check to let page render first
    setTimeout(() => {
      void redirectToPreferredOrigin(window.location);
    }, 100);

    return () => {
      unsubscribeStatus();
    };
  });
</script>

<div class="app-layout">
  <TopBar />
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
