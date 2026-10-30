import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { catchError, of } from 'rxjs';
import { StatusReport } from '../models/project';

/**
 * status.json e publicat pe branch-ul "status" de un workflow programat, ca să nu declanșeze
 * deploy-uri și să nu ceară servicii noi pe server. Dacă lipsește, pagina nu arată starea.
 */
const STATUS_URL = 'https://raw.githubusercontent.com/Oti404/otnielcodes.com/status/status.json';

@Injectable({ providedIn: 'root' })
export class StatusService {
  private readonly http = inject(HttpClient);

  readonly report = toSignal(
    this.http.get<StatusReport>(STATUS_URL).pipe(catchError(() => of(null))),
    { initialValue: null },
  );
}
