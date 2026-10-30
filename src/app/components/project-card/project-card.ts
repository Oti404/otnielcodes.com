import { DatePipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';
import { LiveCheck, Project, ProjectStatus } from '../../models/project';

const STATUS_LABELS: Record<ProjectStatus, string> = {
  live: 'Live',
  beta: 'Beta',
  wip: 'În lucru',
  archived: 'Arhivat',
};

@Component({
  selector: 'app-project-card',
  imports: [DatePipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './project-card.html',
  styleUrl: './project-card.scss',
})
export class ProjectCard {
  readonly project = input.required<Project>();
  readonly check = input<LiveCheck | null>(null);
  readonly checkedAt = input<string | null>(null);

  /** Eticheta de stadiu apare doar când proiectul nu e pur și simplu „live”. */
  protected readonly statusLabel = computed(() => {
    const status = this.project().status;
    return status && status !== 'live' ? STATUS_LABELS[status] : null;
  });
}
