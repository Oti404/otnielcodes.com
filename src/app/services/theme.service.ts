import { DOCUMENT } from '@angular/common';
import { Injectable, inject, signal } from '@angular/core';

export type Theme = 'light' | 'dark';

const STORAGE_KEY = 'theme';

/**
 * Tema urmează prefers-color-scheme până când utilizatorul alege explicit una;
 * alegerea se salvează în localStorage și se aplică prin <html data-theme="...">.
 * Scriptul inline din index.html aplică tema salvată înainte de bootstrap (fără flicker).
 */
@Injectable({ providedIn: 'root' })
export class ThemeService {
  private readonly document = inject(DOCUMENT);
  private readonly media = this.document.defaultView?.matchMedia?.('(prefers-color-scheme: dark)');

  readonly theme = signal<Theme>(this.readStored() ?? this.systemTheme());

  constructor() {
    // Cât timp nu există o alegere salvată, urmărim schimbările din sistem.
    this.media?.addEventListener('change', () => {
      if (!this.readStored()) this.theme.set(this.systemTheme());
    });
  }

  toggle(): void {
    const next: Theme = this.theme() === 'dark' ? 'light' : 'dark';
    this.theme.set(next);
    this.document.documentElement.setAttribute('data-theme', next);
    try {
      localStorage.setItem(STORAGE_KEY, next);
    } catch {
      // Stocare indisponibilă (mod privat, cookie-uri blocate): tema rămâne doar pentru sesiune.
    }
  }

  private systemTheme(): Theme {
    return this.media?.matches ? 'dark' : 'light';
  }

  private readStored(): Theme | null {
    try {
      const value = localStorage.getItem(STORAGE_KEY);
      return value === 'light' || value === 'dark' ? value : null;
    } catch {
      return null;
    }
  }
}
