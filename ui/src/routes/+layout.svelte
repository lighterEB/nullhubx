<script>
  import '../app.css';
  import Sidebar from '$lib/components/Sidebar.svelte';
  import TopBar from '$lib/components/TopBar.svelte';

  let { children } = $props();
</script>

<div class="app-layout">
  <Sidebar />
  <div class="main-area">
    <TopBar />
    <main class="content">
      {@render children()}
    </main>
  </div>
</div>

<style>
  .app-layout {
    display: flex;
    height: 100vh;
    overflow: hidden;
  }
  .main-area {
    flex: 1;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }
  .content {
    flex: 1;
    overflow-y: auto;
    padding: 1.5rem;
  }
</style>
