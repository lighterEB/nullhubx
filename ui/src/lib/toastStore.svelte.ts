export type ToastType = 'info' | 'success' | 'warning' | 'error';

export interface ToastMessage {
  id: string;
  type: ToastType;
  message: string;
  duration?: number;
}

class ToastStore {
  toasts = $state<ToastMessage[]>([]);

  add(message: string, type: ToastType = 'info', duration = 3000) {
    const id = Date.now().toString() + Math.random().toString(36).substr(2, 9);
    this.toasts.push({ id, message, type, duration });
    
    if (duration > 0) {
      setTimeout(() => this.remove(id), duration);
    }
  }

  remove(id: string) {
    this.toasts = this.toasts.filter((t) => t.id !== id);
  }

  error(message: string, duration = 4000) {
    this.add(message, 'error', duration);
  }

  success(message: string, duration = 2500) {
    this.add(message, 'success', duration);
  }

  info(message: string, duration = 2500) {
    this.add(message, 'info', duration);
  }
}

export const toast = new ToastStore();
