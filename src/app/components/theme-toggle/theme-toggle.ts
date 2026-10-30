import { ChangeDetectionStrategy, Component, computed, inject } from '@angular/core';
import { ThemeService } from '../../services/theme.service';

@Component({
  selector: 'app-theme-toggle',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <button
      type="button"
      class="theme-toggle"
      [attr.aria-label]="label()"
      [attr.title]="label()"
      (click)="themeService.toggle()"
    >
      @if (isDark()) {
        <!-- soare -->
        <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false">
          <circle cx="12" cy="12" r="4.5" fill="none" stroke="currentColor" stroke-width="1.8" />
          <path
            d="M12 2v2.5M12 19.5V22M4.2 4.2 6 6M18 18l1.8 1.8M2 12h2.5M19.5 12H22M4.2 19.8 6 18M18 6l1.8-1.8"
            stroke="currentColor"
            stroke-width="1.8"
            stroke-linecap="round"
          />
        </svg>
      } @else {
        <!-- lună -->
        <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false">
          <path
            d="M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5Z"
            fill="none"
            stroke="currentColor"
            stroke-width="1.8"
            stroke-linejoin="round"
          />
        </svg>
      }
    </button>
  `,
  styles: `
    .theme-toggle {
      display: inline-grid;
      place-items: center;
      width: 2.75rem;
      height: 2.75rem;
      border: 1px solid var(--border);
      border-radius: 999px;
      background: var(--surface);
      color: var(--text);
      cursor: pointer;
      transition: border-color 0.15s ease, background-color 0.15s ease;
    }
    .theme-toggle:hover {
      border-color: var(--accent);
    }
  `,
})
export class ThemeToggle {
  protected readonly themeService = inject(ThemeService);
  protected readonly isDark = computed(() => this.themeService.theme() === 'dark');
  protected readonly label = computed(() =>
    this.isDark() ? 'Comută la tema luminoasă' : 'Comută la tema întunecată',
  );
}
