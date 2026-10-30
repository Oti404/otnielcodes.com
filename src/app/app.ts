import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { ProjectCard } from './components/project-card/project-card';
import { ThemeToggle } from './components/theme-toggle/theme-toggle';
import { ProjectsService } from './services/projects.service';
import { StatusService } from './services/status.service';

@Component({
  selector: 'app-root',
  imports: [ProjectCard, ThemeToggle],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './app.html',
  styleUrl: './app.scss',
})
export class App {
  protected readonly projects = inject(ProjectsService).state;
  protected readonly status = inject(StatusService).report;
  protected readonly year = new Date().getFullYear();
  protected readonly links = {
    site: 'https://otniel-iacob.com',
    github: 'https://github.com/Oti404',
  };
}
