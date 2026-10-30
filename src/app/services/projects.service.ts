import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { catchError, map, of } from 'rxjs';
import { Project } from '../models/project';

export type ProjectsState =
  | { status: 'loading' }
  | { status: 'ready'; projects: Project[] }
  | { status: 'error' };

@Injectable({ providedIn: 'root' })
export class ProjectsService {
  private readonly http = inject(HttpClient);

  readonly state = toSignal(
    this.http.get<Project[]>('assets/projects.json').pipe(
      map((projects): ProjectsState => ({ status: 'ready', projects })),
      catchError(() => of<ProjectsState>({ status: 'error' })),
    ),
    { initialValue: { status: 'loading' } as ProjectsState },
  );
}
